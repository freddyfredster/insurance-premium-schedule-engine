// 02_generate_payment_schedule.m
// Purpose:
//   Starting from the cleaned base table (one row per policy *event*),
//   generate a payment schedule with one row per *scheduled payment date*,
//   including:
//     - Payment dates aligned to frequency (monthly / quarterly / annual)
//     - Handling of upgrades (aligned start date logic)
//     - Cancellation-aware flags
//     - Base instalments for three products (A, B, C)
//     - Upgrade instalments for the same components
//
// Assumptions:
//   - A single PolicyID can appear multiple times (New, Renewal, Upgrade, Cancellation, etc.).
//   - Monetary columns are annualised amounts at event level:
//       * ProductA_Premium / ProductA_TaxAmount / ProductA_Commission / ProductA_AdminFee
//       * ProductB_Premium / ProductB_TaxAmount / ProductB_Commission
//       * ProductC_Premium / ProductC_TaxAmount / ProductC_Commission / ProductC_AdminFee
//   - Step 01 has already created:
//       * [EventEffectiveDate]
//       * [PolicyEndDate]
//
// How to adapt to your own data:
//   1. Replace `CleanPolicies` in the Source step with the name of your own
//      base query (output of 01_raw_to_clean_base.m).
//   2. Make sure your columns are mapped to the generics used here:
//        - [PolicyID], [TransactionType], [PolicyStartDate], [CancellationDate]
//        - [PaymentFrequency] ("monthly", "quarterly", "annual")
//        - Product A/B/C premiums, taxes, commissions, admin fees
//   3. Review business rules for:
//        - Instalment counts (monthly=12, quarterly=4, annual=1, cancellation=1)
//        - CancellationStatus labels
//        - Upgrade instalment logic
//   4. Adjust or remove any sections that do not apply to your business.

let
    //---------------------------------------------
    // 0. Source: cleaned base table (one row per event)
    //---------------------------------------------
    // In your model, replace `CleanPolicies` with the name of the output
    // of Step 01 (01_raw_to_clean_base.m).
    Source = CleanPolicies,

    // Keep a reference to the original base table if we need it later
    Base = Source,

    //---------------------------------------------
    // Step 1: Add numeric interval months
    //---------------------------------------------
    // Convert payment frequency text into "months per instalment":
    //   - monthly   -> 1
    //   - quarterly -> 3
    //   - annual    -> 12
    // Any unknown frequency defaults to 1 month.
    AddIntervalMonths =
        Table.AddColumn(
            Base,
            "IntervalMonths",
            each
                let
                    freq =
                        if [PaymentFrequency] = null then
                            null
                        else
                            Text.Lower(Text.Trim([PaymentFrequency]))
                in
                    if freq = "monthly" then
                        1
                    else if freq = "quarterly" then
                        3
                    else if freq = "annual" then
                        12
                    else
                        1,
            Int64.Type
        ),

    //---------------------------------------------
    // Step 2: Aligned start date for upgrades
    //---------------------------------------------
    // Idea:
    //   For base events (New, Renewal, etc.), the payment schedule
    //   simply starts from EventEffectiveDate.
    //
    //   For Upgrades, we often want to "align" their payments to the
    //   existing schedule. That means:
    //     - If the upgrade month lines up with the policy's schedule cycle,
    //       keep the upgrade effective date (day included).
    //     - Otherwise, start at the next scheduled payment date in the cycle.
    //
    // This step calculates an [AlignedStart] used later for Upgrades only.
    AddAlignedStart =
        Table.AddColumn(
            AddIntervalMonths,
            "AlignedStart",
            each
                let
                    base       = [PolicyStartDate],
                    eff        = [EventEffectiveDate],
                    m          = [IntervalMonths],   // 1, 3, or 12
                    policyEnd  = [PolicyEndDate],

                    // Helper: difference in months between two dates (month-only logic)
                    MonthsBetween = (a as date, b as date) as number =>
                        (Date.Year(b) - Date.Year(a)) * 12
                        + (Date.Month(b) - Date.Month(a)),

                    // Work at month granularity
                    startM     = Date.StartOfMonth(base),
                    effM       = Date.StartOfMonth(eff),
                    rem        = Number.Mod(MonthsBetween(startM, effM), m),
                    isAlignedMonth = (rem = 0),

                    // Original schedule on the policy-start day-of-month
                    originalSchedule =
                        List.Generate(
                            () => base,
                            (d) => d <= policyEnd,
                            (d) => Date.AddMonths(d, m)
                        ),

                    // First schedule date on or after EventEffectiveDate
                    futurePayments = List.Select(originalSchedule, each _ >= eff),
                    nextPayment    = if List.Count(futurePayments) = 0 then null else List.First(futurePayments),

                    // RULE:
                    //   - If upgrade month is aligned to the cycle -> keep eff (day included)
                    //   - Else -> shift to next aligned schedule date (policy-start day-of-month)
                    aligned =
                        if isAlignedMonth then
                            eff
                        else if nextPayment = null then
                            eff
                        else
                            nextPayment
                in
                    if [TransactionType] = "Upgrade" then
                        aligned
                    else
                        eff,
            type date
        ),

    //---------------------------------------------
    // Step 3: PayStart (where schedule begins for each event)
    //---------------------------------------------
    // For Upgrade rows: use [AlignedStart].
    // For all other event types: use [EventEffectiveDate].
    AddPayStart =
        Table.AddColumn(
            AddAlignedStart,
            "PayStart",
            each
                if [TransactionType] = "Upgrade" then
                    [AlignedStart]
                else
                    [EventEffectiveDate],
            type date
        ),

    //---------------------------------------------
    // Step 4: Generate PayDates as a list, then expand
    //---------------------------------------------
    // For each event row, we generate a list of payment dates from [PayStart]
    // to [PolicyEndDate], jumping by [IntervalMonths]:
    //
    //   PayStart, PayStart + IntervalMonths, PayStart + 2*IntervalMonths, ...
    //
    // Then we expand that list so we get one row per payment date.
    AddPayList =
        Table.AddColumn(
            AddPayStart,
            "PayList",
            each
                List.Generate(
                    () => [PayStart],
                    (d) => d <= [PolicyEndDate],
                    (d) => Date.AddMonths(d, [IntervalMonths])
                )
        ),

    ExpandedPayList =
        Table.ExpandListColumn(AddPayList, "PayList"),

    RenamePayListToPayDate =
        Table.RenameColumns(ExpandedPayList, {{"PayList", "PayDate"}}),

    // Safety: if for some reason PayDate is null, fall back to PayStart
    EnsurePayDateNotNull =
        Table.AddColumn(
            RenamePayListToPayDate,
            "PayDate_temp",
            each if [PayDate] = null then [PayStart] else [PayDate],
            type date
        ),

    ReplacePayDate =
        Table.RemoveColumns(EnsurePayDateNotNull, {"PayDate"}),

    FinalPayDate =
        Table.RenameColumns(ReplacePayDate, {{"PayDate_temp", "PayDate"}}),

    //---------------------------------------------
    // Step 5: Add Month IDs (for allocation matrix)
    //---------------------------------------------
    // These are numeric YearMonth keys, e.g. 202405 = May 2024.
    //
    //   - [PaymentMonthNum]      -> month of PayDate
    //   - [UnderwrittenMonthNum] -> month of PolicyStartDate
    AddPaymentMonthNum =
        Table.AddColumn(
            FinalPayDate,
            "PaymentMonthNum",
            each Date.Year([PayDate]) * 100 + Date.Month([PayDate]),
            Int64.Type
        ),

    AddUnderwrittenMonthNum =
        Table.AddColumn(
            AddPaymentMonthNum,
            "UnderwrittenMonthNum",
            each Date.Year([PolicyStartDate]) * 100 + Date.Month([PolicyStartDate]),
            Int64.Type
        ),

    //---------------------------------------------
    // Step 6: Bring in a single CancellationEffectiveDate per policy
    //---------------------------------------------
    // We want to know, per PolicyID, when (if at all) it was cancelled.
    // To do that:
    //   - Filter the *base* table to rows where TransactionType = "Cancellation"
    //   - Keep PolicyID + EventEffectiveDate
    //   - Rename EventEffectiveDate -> CancellationEffectiveDate
    //   - Left-join that back onto every schedule row by PolicyID
    CancelRows =
        Table.SelectRows(
            Base,
            each [TransactionType] = "Cancellation"
        ),

    CancelEffective =
        Table.SelectColumns(
            CancelRows,
            {"RecordID", "PolicyID", "EventEffectiveDate"}
        ),

    RenameCancelDate =
        Table.RenameColumns(
            CancelEffective,
            {{"EventEffectiveDate", "CancellationEffectiveDate"}}
        ),

    JoinCancelOnPolicy =
        Table.NestedJoin(
            AddUnderwrittenMonthNum,
            "PolicyID",
            RenameCancelDate,
            "PolicyID",
            "CancelTable",
            JoinKind.LeftOuter
        ),

    ExpandCancelDate =
        Table.ExpandTableColumn(
            JoinCancelOnPolicy,
            "CancelTable",
            {"CancellationEffectiveDate"},
            {"CancellationEffectiveDate"}
        ),

    //---------------------------------------------
    // Step 7: Flag cancellation status per PayDate
    //---------------------------------------------
    // This gives us a text label for each scheduled payment row that
    // describes how it relates to the cancellation (if any).
    //
    // Generic logic:
    //   - If this row itself is a cancellation event AND
    //     the cancellation is at or after the renewal date -> "Renewal Cancellation"
    //   - If there's no cancellation at all               -> "No Cancellation"
    //   - If PayDate is in the same month as cancellation -> "In Cancellation Month"
    //   - If PayDate is strictly after cancellation       -> "After Cancellation"
    //   - Otherwise                                       -> "Before Cancellation"
    //
    // Adjust or simplify these labels to fit your own process.
    AddCancellationStatus =
        Table.AddColumn(
            ExpandCancelDate,
            "CancellationStatus",
            each
                let
                    renewalDate    = Date.AddYears([PolicyStartDate], 1),
                    renewalMonth   = Date.Year(renewalDate) * 100 + Date.Month(renewalDate),
                    cancelMonthNum =
                        if [CancellationEffectiveDate] = null then
                            null
                        else
                            Date.Year([CancellationEffectiveDate]) * 100
                            + Date.Month([CancellationEffectiveDate])
                in
                    if [TransactionType] = "Cancellation"
                        and cancelMonthNum <> null
                        and cancelMonthNum >= renewalMonth
                    then
                        "Renewal Cancellation"
                    else if [CancellationEffectiveDate] = null then
                        "No Cancellation"
                    else if
                        Date.Year([PayDate]) = Date.Year([CancellationEffectiveDate])
                            and Date.Month([PayDate]) = Date.Month([CancellationEffectiveDate])
                    then
                        "In Cancellation Month"
                    else if [PayDate] > [CancellationEffectiveDate] then
                        "After Cancellation"
                    else
                        "Before Cancellation",
            type text
        ),

    //---------------------------------------------
    // Step 8: Calculate InstalmentCount per event
    //---------------------------------------------
    // For each combination of:
    //   - PolicyID
    //   - EventEffectiveDate
    //   - PaymentFrequency
    //   - TransactionType
    //
    // we calculate how many *scheduled* instalments are expected.
    //
    // Generic rule:
    //   - If TransactionType = "Cancellation" -> 1 (lump sum)
    //   - Else if monthly   -> 12
    //   - Else if quarterly -> 4
    //   - Else if annual    -> 1
    //
    // You can change these numbers if your business has different rules
    // (e.g. 10-month terms, mid-term endorsements, etc.).
    GroupInstalmentCount =
        Table.Group(
            AddCancellationStatus,
            {"RecordID", "EventEffectiveDate", "PolicyID", "PaymentFrequency", "TransactionType"},
            {
                {
                    "InstalmentCount",
                    each
                        let
                            firstRow  = Table.FirstN(_, 1){0},
                            t         = firstRow[TransactionType],
                            freqRaw   = firstRow[PaymentFrequency],
                            freqNorm  =
                                if freqRaw = null then
                                    null
                                else
                                    Text.Lower(Text.Trim(freqRaw)),

                            count =
                                if t = "Cancellation" then
                                    1
                                else if freqNorm = "monthly" then
                                    12
                                else if freqNorm = "quarterly" then
                                    4
                                else if freqNorm = "annual" then
                                    1
                                else
                                    null
                        in
                            count,
                    Int64.Type
                }
            }
        ),

    JoinInstCount =
        Table.NestedJoin(
            AddCancellationStatus,
            {"PolicyID", "TransactionType", "EventEffectiveDate"},
            GroupInstalmentCount,
            {"PolicyID", "TransactionType", "EventEffectiveDate"},
            "InstTbl",
            JoinKind.LeftOuter
        ),

    ExpandInstCount =
        Table.ExpandTableColumn(
            JoinInstCount,
            "InstTbl",
            {"InstalmentCount"},
            {"InstalmentCount"}
        ),

    //---------------------------------------------
    // Step 9–11: Base instalments for Products A, B, C
    //---------------------------------------------
    // For non-Upgrade events, we split the annual amounts evenly across
    // the expected instalment count. Upgrades are handled separately.
    //
    // If your business rules are more complex (e.g. uneven splits), this
    // is the place to implement them.
    AddBasePremA =
        Table.AddColumn(
            ExpandInstCount,
            "Base_Installment_Premium_A",
            each
                if [TransactionType] = "Upgrade"
                    or [InstalmentCount] = null
                    or [ProductA_Premium] = null
                then
                    null
                else
                    [ProductA_Premium] / [InstalmentCount],
            type number
        ),

    AddBaseTaxA =
        Table.AddColumn(
            AddBasePremA,
            "Base_Installment_Tax_A",
            each
                if [TransactionType] = "Upgrade"
                    or [InstalmentCount] = null
                    or [ProductA_TaxAmount] = null
                then
                    null
                else
                    [ProductA_TaxAmount] / [InstalmentCount],
            type number
        ),

    AddBasePremB =
        Table.AddColumn(
            AddBaseTaxA,
            "Base_Installment_Premium_B",
            each
                if [TransactionType] = "Upgrade"
                    or [InstalmentCount] = null
                    or [ProductB_Premium] = null
                then
                    null
                else
                    [ProductB_Premium] / [InstalmentCount],
            type number
        ),

    AddBaseTaxB =
        Table.AddColumn(
            AddBasePremB,
            "Base_Installment_Tax_B",
            each
                if [TransactionType] = "Upgrade"
                    or [InstalmentCount] = null
                    or [ProductB_TaxAmount] = null
                then
                    null
                else
                    [ProductB_TaxAmount] / [InstalmentCount],
            type number
        ),

    AddBasePremC =
        Table.AddColumn(
            AddBaseTaxB,
            "Base_Installment_Premium_C",
            each
                if [TransactionType] = "Upgrade"
                    or [InstalmentCount] = null
                    or [ProductC_Premium] = null
                then
                    null
                else
                    [ProductC_Premium] / [InstalmentCount],
            type number
        ),

    AddBaseTaxC =
        Table.AddColumn(
            AddBasePremC,
            "Base_Installment_Tax_C",
            each
                if [TransactionType] = "Upgrade"
                    or [InstalmentCount] = null
                    or [ProductC_TaxAmount] = null
                then
                    null
                else
                    [ProductC_TaxAmount] / [InstalmentCount],
            type number
        ),

    //---------------------------------------------
    // Step 11b: Additional base fees/commissions
    //---------------------------------------------
    AddBaseAdminC =
        Table.AddColumn(
            AddBaseTaxC,
            "Base_Installment_Admin_C",
            each
                if [TransactionType] = "Upgrade"
                    or [InstalmentCount] = null
                    or [ProductC_AdminFee] = null
                then
                    null
                else
                    [ProductC_AdminFee] / [InstalmentCount],
            type number
        ),

    AddBaseCommissionC =
        Table.AddColumn(
            AddBaseAdminC,
            "Base_Installment_Commission_C",
            each
                if [TransactionType] = "Upgrade"
                    or [InstalmentCount] = null
                    or [ProductC_Commission] = null
                then
                    null
                else
                    [ProductC_Commission] / [InstalmentCount],
            type number
        ),

    AddBaseAdminGeneric =
        Table.AddColumn(
            AddBaseCommissionC,
            "Base_Installment_Admin_Generic",
            each
                if [TransactionType] = "Upgrade"
                    or [InstalmentCount] = null
                    or [ProductA_AdminFee] = null
                then
                    null
                else
                    [ProductA_AdminFee] / [InstalmentCount],
            type number
        ),

    AddBaseCommissionB =
        Table.AddColumn(
            AddBaseAdminGeneric,
            "Base_Installment_Commission_B",
            each
                if [TransactionType] = "Upgrade"
                    or [InstalmentCount] = null
                    or [ProductB_Commission] = null
                then
                    null
                else
                    [ProductB_Commission] / [InstalmentCount],
            type number
        ),

    AddBaseCommissionA =
        Table.AddColumn(
            AddBaseCommissionB,
            "Base_Installment_Commission_A",
            each
                if [TransactionType] = "Upgrade"
                    or [InstalmentCount] = null
                    or [ProductA_Commission] = null
                then
                    null
                else
                    [ProductA_Commission] / [InstalmentCount],
            type number
        ),

    //---------------------------------------------
    // Step 12: Upgrade instalment counts
    //---------------------------------------------
    // For Upgrade events, we want to know how many remaining aligned
    // instalments exist between the effective date and policy end.
    //
    // This drives the per-instalment upgrade amounts.
    UpgradeRows =
        Table.SelectRows(
            AddBaseCommissionA,
            each [TransactionType] = "Upgrade"
        ),

    GroupUpgradeCount =
        Table.Group(
            UpgradeRows,
            {"RecordID", "PolicyID", "EventEffectiveDate", "PolicyStartDate", "PaymentFrequency", "AlignedStart"},
            {
                {
                    "UpgradeInstalmentCount",
                    each
                        let
                            firstRow   = Table.FirstN(_, 1){0},
                            eff        = firstRow[EventEffectiveDate],
                            polStart   = firstRow[PolicyStartDate],
                            polEnd     = firstRow[PolicyEndDate],
                            interval   = firstRow[IntervalMonths],   // 1, 3, or 12

                            result =
                                if eff = null
                                    or polStart = null
                                    or polEnd = null
                                    or interval = null
                                then
                                    null
                                else
                                    let
                                        // Work at month-start granularity
                                        effM   = Date.StartOfMonth(eff),
                                        startM = Date.StartOfMonth(polStart),
                                        endM   = Date.StartOfMonth(polEnd),

                                        MonthsBetween = (a as date, b as date) as number =>
                                            (Date.Year(b) - Date.Year(a)) * 12
                                            + (Date.Month(b) - Date.Month(a)),

                                        // How far effM is into the schedule cycle
                                        mDiff  = MonthsBetween(startM, effM),
                                        rem    = Number.Mod(mDiff, interval),

                                        // Next aligned month on/after effM
                                        addToAlign    = Number.Mod(interval - rem, interval),
                                        firstAlignedM = Date.AddMonths(effM, addToAlign),

                                        // If first aligned month is beyond policy end,
                                        // we still return at least 1 (one lump).
                                        rawCount =
                                            if firstAlignedM > endM then
                                                1
                                            else
                                                Number.IntegerDivide(MonthsBetween(firstAlignedM, endM), interval) + 1,

                                        finalCount = if rawCount < 1 then 1 else rawCount
                                    in
                                        // For annual upgrades, we treat as a single instalment
                                        if interval = 12 then 1 else finalCount
                        in
                            result,
                    Int64.Type
                }
            }
        ),

    JoinUpgradeCount =
        Table.NestedJoin(
            AddBaseCommissionA,
            {"PolicyID", "EventEffectiveDate"},
            GroupUpgradeCount,
            {"PolicyID", "EventEffectiveDate"},
            "UpgradeCount",
            JoinKind.LeftOuter
        ),

    ExpandUpgradeCount =
        Table.ExpandTableColumn(
            JoinUpgradeCount,
            "UpgradeCount",
            {"UpgradeInstalmentCount"},
            {"UpgradeInstalmentCount"}
        ),

    //---------------------------------------------
    // Step 13: Upgrade instalments for A/B/C
    //---------------------------------------------
    // For Upgrade rows:
    //   Upgrade per-instalment = annual upgrade amount / UpgradeInstalmentCount
    //
    // For non-Upgrade rows, these stay null.
    AddUpgradePremA =
        Table.AddColumn(
            ExpandUpgradeCount,
            "Upgrade_Installment_Premium_A",
            each
                if [TransactionType] = "Upgrade"
                    and [UpgradeInstalmentCount] <> null
                    and [ProductA_Premium] <> null
                then
                    [ProductA_Premium] / [UpgradeInstalmentCount]
                else
                    null,
            type number
        ),

    AddUpgradeTaxA =
        Table.AddColumn(
            AddUpgradePremA,
            "Upgrade_Installment_Tax_A",
            each
                if [TransactionType] = "Upgrade"
                    and [UpgradeInstalmentCount] <> null
                    and [ProductA_TaxAmount] <> null
                then
                    [ProductA_TaxAmount] / [UpgradeInstalmentCount]
                else
                    null,
            type number
        ),

    AddUpgradePremB =
        Table.AddColumn(
            AddUpgradeTaxA,
            "Upgrade_Installment_Premium_B",
            each
                if [TransactionType] = "Upgrade"
                    and [UpgradeInstalmentCount] <> null
                    and [ProductB_Premium] <> null
                then
                    [ProductB_Premium] / [UpgradeInstalmentCount]
                else
                    null,
            type number
        ),

    AddUpgradeTaxB =
        Table.AddColumn(
            AddUpgradePremB,
            "Upgrade_Installment_Tax_B",
            each
                if [TransactionType] = "Upgrade"
                    and [UpgradeInstalmentCount] <> null
                    and [ProductB_TaxAmount] <> null
                then
                    [ProductB_TaxAmount] / [UpgradeInstalmentCount]
                else
                    null,
            type number
        ),

    AddUpgradePremC =
        Table.AddColumn(
            AddUpgradeTaxB,
            "Upgrade_Installment_Premium_C",
            each
                if [TransactionType] = "Upgrade"
                    and [UpgradeInstalmentCount] <> null
                    and [ProductC_Premium] <> null
                then
                    [ProductC_Premium] / [UpgradeInstalmentCount]
                else
                    null,
            type number
        ),

    AddUpgradeTaxC =
        Table.AddColumn(
            AddUpgradePremC,
            "Upgrade_Installment_Tax_C",
            each
                if [TransactionType] = "Upgrade"
                    and [UpgradeInstalmentCount] <> null
                    and [ProductC_TaxAmount] <> null
                then
                    [ProductC_TaxAmount] / [UpgradeInstalmentCount]
                else
                    null,
            type number
        ),

    //---------------------------------------------
    // Step 13b: Upgrade fees/commissions
    //---------------------------------------------
    AddUpgradeAdminC =
        Table.AddColumn(
            AddUpgradeTaxC,
            "Upgrade_Installment_Admin_C",
            each
                if [TransactionType] = "Upgrade"
                    and [UpgradeInstalmentCount] <> null
                    and [ProductC_AdminFee] <> null
                then
                    [ProductC_AdminFee] / [UpgradeInstalmentCount]
                else
                    null,
            type number
        ),

    AddUpgradeCommissionC =
        Table.AddColumn(
            AddUpgradeAdminC,
            "Upgrade_Installment_Commission_C",
            each
                if [TransactionType] = "Upgrade"
                    and [UpgradeInstalmentCount] <> null
                    and [ProductC_Commission] <> null
                then
                    [ProductC_Commission] / [UpgradeInstalmentCount]
                else
                    null,
            type number
        ),

    AddUpgradeAdminGeneric =
        Table.AddColumn(
            AddUpgradeCommissionC,
            "Upgrade_Installment_Admin_Generic",
            each
                if [TransactionType] = "Upgrade"
                    and [UpgradeInstalmentCount] <> null
                    and [ProductA_AdminFee] <> null
                then
                    [ProductA_AdminFee] / [UpgradeInstalmentCount]
                else
                    null,
            type number
        ),

    AddUpgradeCommissionB =
        Table.AddColumn(
            AddUpgradeAdminGeneric,
            "Upgrade_Installment_Commission_B",
            each
                if [TransactionType] = "Upgrade"
                    and [UpgradeInstalmentCount] <> null
                    and [ProductB_Commission] <> null
                then
                    [ProductB_Commission] / [UpgradeInstalmentCount]
                else
                    null,
            type number
        ),

    AddUpgradeCommissionA =
        Table.AddColumn(
            AddUpgradeCommissionB,
            "Upgrade_Installment_Commission_A",
            each
                if [TransactionType] = "Upgrade"
                    and [UpgradeInstalmentCount] <> null
                    and [ProductA_Commission] <> null
                then
                    [ProductA_Commission] / [UpgradeInstalmentCount]
                else
                    null,
            type number
        ),

    //---------------------------------------------
    // Step 14: Helper year-month for cancellation
    //---------------------------------------------
    AddCancelMonthNum =
        Table.AddColumn(
            AddUpgradeCommissionA,
            "CancellationEffectiveDate_YearMonthNum",
            each
                if [CancellationEffectiveDate] = null then
                    null
                else
                    Date.Year([CancellationEffectiveDate]) * 100
                    + Date.Month([CancellationEffectiveDate]),
            Int64.Type
        ),

    //---------------------------------------------
    // Final tidy up
    //---------------------------------------------
    SetTypes =
        Table.TransformColumnTypes(
            AddCancelMonthNum,
            {
                {"CancellationStatus", type text},
                {"PayDate", type date},
                {"PayStart", type date},
                {"AlignedStart", type date}
            }
        ),

    RemoveDuplicates =
        Table.Distinct(SetTypes)

in
    RemoveDuplicates
