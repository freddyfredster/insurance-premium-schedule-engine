let
    Source = Fact_Trailer_bdx_base,

    // Step 1: Add interval month logic
    AddIntervalMonths = Table.AddColumn(Source, "IntervalMonths", each 
        if [interval] = "monthly" then 1 
        else if [interval] = "quarterly" then 3 
        else if [interval] = "annual" then 12 
        else 1, Int64.Type),
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
    #"Renamed PayList To PayDate" = Table.RenameColumns(Expanded, {{"PayList", "PayDate"}}),
    #"Added Conditional Column" = Table.AddColumn(#"Renamed PayList To PayDate", "PayDate_temp", each if [PayDate] = null then [Effective_Date] else [PayDate]),
    #"Removed Columns" = Table.RemoveColumns(#"Added Conditional Column",{"PayDate"}),
    #"Renamed Columns" = Table.RenameColumns(#"Removed Columns",{{"PayDate_temp", "PayDate"}}),
    // Step 5: Add Month IDs
    AddPayMonth = Table.AddColumn(#"Renamed Columns", "payment_month_num", each Date.Year([PayDate]) * 100 + Date.Month([PayDate]), Int64.Type),
    AddUWMonth = Table.AddColumn(AddPayMonth, "underwritten_month_num", each Date.Year([policy_start_date]) * 100 + Date.Month([policy_start_date]), Int64.Type),

    // Step 6: Add CancellationEffectiveDate per reference
    CancelRows = Table.SelectRows(Source, each [type] = "Cancelled"),
    CancelEffective = Table.SelectColumns(CancelRows, {"id","reference", "Effective_Date"}),
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
                        null  // unknown interval → return null (adjust if you want a default)
            in
                count,
            Int64.Type}
    }
),
    JoinInst = Table.NestedJoin(AddCancelFlag, {"reference", "type"}, GroupInstCount, {"reference", "type"}, "InstTbl", JoinKind.LeftOuter),
    ExpandInst = Table.ExpandTableColumn(JoinInst, "InstTbl", {"InstalmentCount"}),

    // Step 9: Base Premium/IPT/Admin/Commission per instalment
    AddPrem = Table.AddColumn(ExpandInst, "Base_Installment_Premium", each 
        if [type] = "Upgrade" or [InstalmentCount] = null or [InstalmentCount] = 0 or [annual_net_premium] = null then null 
        else [annual_net_premium] / [InstalmentCount]),
    AddIPT = Table.AddColumn(AddPrem, "Base_Installment_IPT", each 
        if [type] = "Upgrade" or [InstalmentCount] = null or [InstalmentCount] = 0 or [ipt] = null then null 
        else [ipt] / [InstalmentCount]),
    AddCommission = Table.AddColumn(AddIPT, "Base_Installment_Commission", each 
        if [type] = "Upgrade" or [InstalmentCount] = null or [InstalmentCount] = 0 or [annual_commision] = null then null 
        else [annual_commision] / [InstalmentCount]),
    AddAdminFee = Table.AddColumn(AddCommission, "Base_Installment_AdminFee", each 
        if [type] = "Upgrade" or [InstalmentCount] = null or [InstalmentCount] = 0 or [admin_fee] = null then null 
        else [admin_fee] / [InstalmentCount]),

    // Step 10: Upgrade-specific logic — count aligned months from AlignedStart to policy_end_date
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
    JoinUpgradeCount = Table.NestedJoin(AddAdminFee, {"reference", "Effective_Date"}, GroupUpgradeCount, {"reference", "Effective_Date"}, "UpgradeCount", JoinKind.LeftOuter),
    ExpandUpgrade = Table.ExpandTableColumn(JoinUpgradeCount, "UpgradeCount", {"upgrade_instalment_count"}),
    // Step 11: Upgrade Premium/IPT/Admin/Commission per aligned month (null-safe)
    AddUpgradePrem = Table.AddColumn(ExpandUpgrade, "Upgrade_Installment_Premium", each 
        if [type] = "Upgrade" 
            and [upgrade_instalment_count] <> null 
            and [upgrade_instalment_count] > 0 
            and [annual_net_premium] <> null then 
            [annual_net_premium] / [upgrade_instalment_count] 
        else null),
    AddUpgradeIPT = Table.AddColumn(AddUpgradePrem, "Upgrade_Installment_IPT", each 
        if [type] = "Upgrade" 
            and [upgrade_instalment_count] <> null 
            and [upgrade_instalment_count] > 0 
            and [ipt] <> null then 
            [ipt] / [upgrade_instalment_count] 
        else null),
    AddUpgradeCommission = Table.AddColumn(AddUpgradeIPT, "Upgrade_Installment_Commission", each 
        if [type] = "Upgrade" 
            and [upgrade_instalment_count] <> null 
            and [upgrade_instalment_count] > 0 
            and [annual_commision] <> null then 
            [annual_commision] / [upgrade_instalment_count] 
        else null),
    AddUpgradeAdminFee = Table.AddColumn(AddUpgradeCommission, "Upgrade_Installment_AdminFee", each 
        if [type] = "Upgrade" 
            and [upgrade_instalment_count] <> null 
            and [upgrade_instalment_count] > 0 
            and [admin_fee] <> null then 
            [admin_fee] / [upgrade_instalment_count] 
        else null),

    // Final formatting
    #"Changed Type" = Table.TransformColumnTypes(AddUpgradeAdminFee, {
        {"policy_start_date", type date}, {"reference", type text}, {"cancelled_date", type date}, {"days_used", Int64.Type}, {"days_paid", Int64.Type}, {"interval", type text}, {"type", type text}, 
        {"annual_cost", type number}, {"annual_premium_excl_ipt", type number}, {"annual_net_premium", type number}, {"ipt", type number}, {"annual_commision", type number}, {"admin_fee", type number}, 
        {"Effective_Date", type date}, {"policy_end_date", type date}, {"IntervalMonths", Int64.Type}, {"AlignedStart", type date}, {"PayStart", type date}, {"PayDate", type date}, 
        {"payment_month_num", Int64.Type}, {"underwritten_month_num", Int64.Type}, {"CancellationEffectiveDate", type date}, {"CancellationStatus", type text}, 
        {"InstalmentCount", Int64.Type}, 
        {"Base_Installment_Premium", type number}, {"Base_Installment_IPT", type number}, {"Base_Installment_Commission", type number}, {"Base_Installment_AdminFee", type number}, 
        {"upgrade_instalment_count", type number}, 
        {"Upgrade_Installment_Premium", type number}, {"Upgrade_Installment_IPT", type number}, {"Upgrade_Installment_Commission", type number}, {"Upgrade_Installment_AdminFee", type number}
    }),
    #"Added Custom" = Table.AddColumn(#"Changed Type", "CancellationEffectiveDate_YearMonthNum", each Date.Year([CancellationEffectiveDate]) * 100 + Date.Month([CancellationEffectiveDate]), Int64.Type),
    #"Removed Duplicates" = Table.Distinct(#"Added Custom")
in
    #"Removed Duplicates"