let
    Source = Fact_Memberships_bdx_base,

    // Step 1: Add interval month logic
    AddIntervalMonths = Table.AddColumn(Source, "IntervalMonths", each 
        if [interval] = "monthly" then 1 
        else if [interval] = "quarterly" then 3 
        else if [interval] = "annual" then 12 
        else 1, Int64.Type),

    // Step 2: Aligned start (for upgrade payment alignment)
    AddAlignedStart = Table.AddColumn(
    AddIntervalMonths,
    "AlignedStart",
    each
    let
        base       = [policy_start_date],
        eff        = [Effective_Date],
        m          = [IntervalMonths],        // 1, 3, or 12
        policyEnd  = [policy_end_date],

        // helpers
        MonthsBetween = (a as date, b as date) as number =>
            (Date.Year(b) - Date.Year(a)) * 12 + (Date.Month(b) - Date.Month(a)),

        // month-only alignment
        startM     = Date.StartOfMonth(base),
        effM       = Date.StartOfMonth(eff),
        rem        = Number.Mod(MonthsBetween(startM, effM), m),
        isAlignedMonth = (rem = 0),

        // original schedule on the policy-start day (Date.AddMonths auto-clamps day)
        originalSchedule =
            List.Generate(
                () => base,
                (d) => d <= policyEnd,
                (d) => Date.AddMonths(d, m)
            ),

        // first schedule date on/after Effective_Date
        futurePayments = List.Select(originalSchedule, each _ >= eff),
        nextPayment    = if List.Count(futurePayments) = 0 then null else List.First(futurePayments),

        // RULE:
        // - if effective month is aligned -> keep Effective_Date (keep its day)
        // - else -> next aligned schedule date (policy-start day-of-month)
        aligned =
            if isAlignedMonth then
                eff
            else if nextPayment = null then
                eff
            else
                nextPayment
    in
        if [type] = "Upgrade" then aligned else eff,
    type date
),

    // Step 3: Set payment start date (aligned for upgrades)
    AddPayStart = Table.AddColumn(AddAlignedStart, "PayStart", each 
        if [type] = "Upgrade" then [AlignedStart] else [Effective_Date]
    ),

    // Step 4: Generate PayDates
    AddPayList = Table.AddColumn(AddPayStart, "PayList", each 
        List.Generate(
            () => [PayStart],
            (d) => d <= [policy_end_date],
            (d) => Date.AddMonths(d, [IntervalMonths])
        )
    ),
    Expanded = Table.ExpandListColumn(AddPayList, "PayList"),
    Renamed = Table.RenameColumns(Expanded, {{"PayList", "PayDate"}}),
    #"Added Conditional Column" = Table.AddColumn(Renamed, "PayDate_temp", each if [PayDate] = null then [PayStart] else [PayDate]),
    #"Removed Columns" = Table.RemoveColumns(#"Added Conditional Column",{"PayDate"}),
    #"Renamed Columns" = Table.RenameColumns(#"Removed Columns",{{"PayDate_temp", "PayDate"}}),
    // Step 5: Add Month IDs
    AddPayMonth = Table.AddColumn(#"Renamed Columns", "payment_month_num", each Date.Year([PayDate]) * 100 + Date.Month([PayDate]), Int64.Type),
    AddUWMonth = Table.AddColumn(AddPayMonth, "underwritten_month_num", each Date.Year([policy_start_date]) * 100 + Date.Month([policy_start_date]), Int64.Type),

    // Step 6: Add CancellationEffectiveDate per reference
    CancelRows = Table.SelectRows(Source, each [type] = "Cancelled"),
    CancelEffective = Table.SelectColumns(CancelRows, {"id", "reference", "Effective_Date"}),
    RenameCancel = Table.RenameColumns(CancelEffective, {{"Effective_Date", "CancellationEffectiveDate"}}),
    JoinCancel = Table.NestedJoin(AddUWMonth, "reference", RenameCancel, "reference", "CancelTable", JoinKind.LeftOuter),
    ExpandCancel = Table.ExpandTableColumn(JoinCancel, "CancelTable", {"CancellationEffectiveDate"}),

    // Step 7: Flag cancellation status
    AddCancelFlag = Table.AddColumn(ExpandCancel, "CancellationStatus", each 
    let
        renewalDate = Date.AddYears([policy_start_date], 1),
        renewalMonthNum = Date.Year(renewalDate) * 100 + Date.Month(renewalDate),
        cancelMonthNum = Date.Year([CancellationEffectiveDate]) * 100 + Date.Month([CancellationEffectiveDate])
    in
        if [type] = "Cancelled" and cancelMonthNum >= renewalMonthNum then
            "Renewal Cancellation"
        else if [CancellationEffectiveDate] = null then 
            "No Cancellation"
        else if Date.Year([PayDate]) = Date.Year([CancellationEffectiveDate]) and Date.Month([PayDate]) = Date.Month([CancellationEffectiveDate]) then 
            "In Cancellation Month"
        else if [PayDate] > [CancellationEffectiveDate] then 
            "After Cancellation"
        else 
            "Before Cancellation"
),

    // Step 8: Calculate instalment count
    GroupInstCount = Table.Group(
    AddCancelFlag,
    {"id", "Effective_Date", "reference", "interval", "type"},
    {
        {"InstalmentCount", each 
            let
                t        = try [type]{0} otherwise null,
                intvRaw  = try [interval]{0} otherwise null,
                intv     = if intvRaw = null then null else Text.Lower(Text.Trim(intvRaw)),
                count =
                    if t = "Cancelled" then
                        1
                    else if intv = "monthly" then
                        12
                    else if intv = "quarterly" then
                        4
                    else if intv = "annual" then
                        1
                    else
                    null
            in
                count,
            Int64.Type}
    }
),
    JoinInst = Table.NestedJoin(AddCancelFlag, {"reference", "type"}, GroupInstCount, {"reference", "type"}, "InstTbl", JoinKind.LeftOuter),
    ExpandInst = Table.ExpandTableColumn(JoinInst, "InstTbl", {"InstalmentCount"}),

    // Step 9–11: Base instalments (PL, PA, FR)
    AddPremPL = Table.AddColumn(ExpandInst, "Base_Installment_Premium_PL", each if [type] = "Upgrade" or [InstalmentCount] = null or [annual_pl_premium] = null then null else [annual_pl_premium] / [InstalmentCount], type number),
    AddIPTPL = Table.AddColumn(AddPremPL, "Base_Installment_IPT_PL", each if [type] = "Upgrade" or [InstalmentCount] = null or [ipt_pl] = null then null else [ipt_pl] / [InstalmentCount], type number),
    AddPremPA = Table.AddColumn(AddIPTPL, "Base_Installment_Premium_PA", each if [type] = "Upgrade" or [InstalmentCount] = null or [annual_pa_premium] = null then null else [annual_pa_premium] / [InstalmentCount], type number),
    AddIPTPA = Table.AddColumn(AddPremPA, "Base_Installment_IPT_PA", each if [type] = "Upgrade" or [InstalmentCount] = null or [ipt_pa] = null then null else [ipt_pa] / [InstalmentCount], type number),
    AddPremFR = Table.AddColumn(AddIPTPA, "Base_Installment_Premium_FR", each if [type] = "Upgrade" or [InstalmentCount] = null or [annual_fr_premium] = null then null else [annual_fr_premium] / [InstalmentCount], type number),
    AddIPTFR = Table.AddColumn(AddPremFR, "Base_Installment_IPT_FR", each if [type] = "Upgrade" or [InstalmentCount] = null or [ipt_fracture] = null then null else [ipt_fracture] / [InstalmentCount], type number),

    // Step 11b: Additional base fee/commission fields
    AddAdminFR = Table.AddColumn(AddIPTFR, "Base_Installment_Admin_FR", each if [type] = "Upgrade" or [InstalmentCount] = null or [admin_fee_fracture] = null then null else [admin_fee_fracture] / [InstalmentCount], type number),
    AddCommissionFR = Table.AddColumn(AddAdminFR, "Base_Installment_Commission_FR", each if [type] = "Upgrade" or [InstalmentCount] = null or [commission_fracture] = null then null else [commission_fracture] / [InstalmentCount], type number),
    AddAdminGeneric = Table.AddColumn(AddCommissionFR, "Base_Installment_Admin_Generic", each if [type] = "Upgrade" or [InstalmentCount] = null or [admin_fee] = null then null else [admin_fee] / [InstalmentCount], type number),
    AddCommissionPA = Table.AddColumn(AddAdminGeneric, "Base_Installment_Commission_PA", each if [type] = "Upgrade" or [InstalmentCount] = null or [commision_on_pa] = null then null else [commision_on_pa] / [InstalmentCount], type number),
    AddCommissionPL = Table.AddColumn(AddCommissionPA, "Base_Installment_Commission_PL", each if [type] = "Upgrade" or [InstalmentCount] = null or [commision_on_pl] = null then null else [commision_on_pl] / [InstalmentCount], type number),

    // Step 12: Upgrade instalment counts
    UpgradeRows = Table.SelectRows(AddCancelFlag, each [type] = "Upgrade"),
    GroupUpgradeCount = Table.Group(
    UpgradeRows,
    {"id", "reference", "Effective_Date", "policy_start_date", "interval", "AlignedStart"},
    {
        {"upgrade_instalment_count", each 
            let
                firstRow   = Table.FirstN(_, 1){0},
                eff        = firstRow[Effective_Date],
                polStart   = firstRow[policy_start_date],
                polEnd     = firstRow[policy_end_date],
                interval   = firstRow[IntervalMonths],      // 1, 3, or 12

                result =
                    if eff = null or polStart = null or polEnd = null or interval = null then
                        null
                    else
                        let
                            // normalize to month starts
                            effM     = Date.StartOfMonth(eff),
                            startM   = Date.StartOfMonth(polStart),
                            endM     = Date.StartOfMonth(polEnd),

                            // months between two month-starts
                            MonthsBetween = (a as date, b as date) as number =>
                                (Date.Year(b) - Date.Year(a)) * 12 + (Date.Month(b) - Date.Month(a)),

                            // how far effM is into the cycle
                            mDiff    = MonthsBetween(startM, effM),
                            rem      = Number.Mod(mDiff, interval),

                            // round UP to the next aligned month on/after effM (month-only logic)
                            addToAlign    = Number.Mod(interval - rem, interval),
                            firstAlignedM = Date.AddMonths(effM, addToAlign),

                            // if first aligned month is beyond policy end, still return 1 (your rule)
                            rawCount =
                                if firstAlignedM > endM then
                                    1
                                else
                                    Number.IntegerDivide(MonthsBetween(firstAlignedM, endM), interval) + 1,

                            final = if rawCount < 1 then 1 else rawCount
                        in
                            if interval = 12 then 1 else final
            in
                result,
            Int64.Type}
    }
),
    JoinUpgradeCount = Table.NestedJoin(AddCommissionPL, {"reference", "Effective_Date"}, GroupUpgradeCount, {"reference", "Effective_Date"}, "UpgradeCount", JoinKind.LeftOuter),
    ExpandUpgrade = Table.ExpandTableColumn(JoinUpgradeCount, "UpgradeCount", {"upgrade_instalment_count"}),

    // Step 13: Upgrade instalments
    AddUpgradePL = Table.AddColumn(ExpandUpgrade, "Upgrade_Installment_Premium_PL", each if [type] = "Upgrade" and [upgrade_instalment_count] <> null and [annual_pl_premium] <> null then [annual_pl_premium] / [upgrade_instalment_count] else null, type number),
    AddUpgradeIPTPL = Table.AddColumn(AddUpgradePL, "Upgrade_Installment_IPT_PL", each if [type] = "Upgrade" and [ipt_pl] <> null then [ipt_pl] / [upgrade_instalment_count] else null, type number),
    AddUpgradePA = Table.AddColumn(AddUpgradeIPTPL, "Upgrade_Installment_Premium_PA", each if [type] = "Upgrade" and [annual_pa_premium] <> null then [annual_pa_premium] / [upgrade_instalment_count] else null, type number),
    AddUpgradeIPTPA = Table.AddColumn(AddUpgradePA, "Upgrade_Installment_IPT_PA", each if [type] = "Upgrade" and [ipt_pa] <> null then [ipt_pa] / [upgrade_instalment_count] else null, type number),
    AddUpgradeFR = Table.AddColumn(AddUpgradeIPTPA, "Upgrade_Installment_Premium_FR", each if [type] = "Upgrade" and [annual_fr_premium] <> null then [annual_fr_premium] / [upgrade_instalment_count] else null, type number),
    AddUpgradeIPTFR = Table.AddColumn(AddUpgradeFR, "Upgrade_Installment_IPT_FR", each if [type] = "Upgrade" and [ipt_fracture] <> null then [ipt_fracture] / [upgrade_instalment_count] else null, type number),

    // Step 13b: Additional upgrade fee/commission fields
    AddUpgradeAdminFR = Table.AddColumn(AddUpgradeIPTFR, "Upgrade_Installment_Admin_FR", each if [type] = "Upgrade" and [admin_fee_fracture] <> null then [admin_fee_fracture] / [upgrade_instalment_count] else null, type number),
    AddUpgradeCommissionFR = Table.AddColumn(AddUpgradeAdminFR, "Upgrade_Installment_Commission_FR", each if [type] = "Upgrade" and [commission_fracture] <> null then [commission_fracture] / [upgrade_instalment_count] else null, type number),
    AddUpgradeAdminGeneric = Table.AddColumn(AddUpgradeCommissionFR, "Upgrade_Installment_Admin_Generic", each if [type] = "Upgrade" and [admin_fee] <> null then [admin_fee] / [upgrade_instalment_count] else null, type number),
    AddUpgradeCommissionPA = Table.AddColumn(AddUpgradeAdminGeneric, "Upgrade_Installment_Commission_PA", each if [type] = "Upgrade" and [commision_on_pa] <> null then [commision_on_pa] / [upgrade_instalment_count] else null, type number),
    AddUpgradeCommissionPL = Table.AddColumn(AddUpgradeCommissionPA, "Upgrade_Installment_Commission_PL", each if [type] = "Upgrade" and [commision_on_pl] <> null then [commision_on_pl] / [upgrade_instalment_count] else null, type number),

    // Step 14: Final
    AddCancelMonthNum = Table.AddColumn(AddUpgradeCommissionPL, "CancellationEffectiveDate_YearMonthNum", each Date.Year([CancellationEffectiveDate]) * 100 + Date.Month([CancellationEffectiveDate]), Int64.Type),
    #"Changed Type" = Table.TransformColumnTypes(AddCancelMonthNum,{{"CancellationStatus", type text}, {"PayDate", type date}, {"PayStart", type date}, {"AlignedStart", type date}}),
    #"Removed Duplicates" = Table.Distinct(#"Changed Type")
in
    #"Removed Duplicates"