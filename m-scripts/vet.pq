let
    Source = Fact_Vet_bbx_base,

    // Step 1: Add interval month logic
    AddIntervalMonths = Table.AddColumn(Source, "IntervalMonths", each 
        if [interval] = "monthly" then 1 
        else if [interval] = "quarterly" then 3 
        else if [interval] = "annual" then 12 
        else 1, Int64.Type),

    // Step 2: Aligned start (for upgrade payment alignment)
    AddAlignedStart = Table.AddColumn(AddIntervalMonths, "AlignedStart", each 
        let
            base = [policy_start_date],
            eff = [Effective_Date],
            m = [IntervalMonths],
            offset = Number.RoundUp(Duration.Days(eff - base) / 30),
            aligned = Number.RoundUp(offset / m) * m
        in
            Date.AddMonths(base, aligned)
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

    // Step 5: Add Month IDs
    AddPayMonth = Table.AddColumn(Renamed, "payment_month_num", each Date.Year([PayDate]) * 100 + Date.Month([PayDate]), Int64.Type),
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

    // Step 8.5: Base Instalments (Premium, IPT, Commission, Admin Fee)
    AddPrem = Table.AddColumn(ExpandInst, "Base_Installment_Premium", each 
        if [type] = "Upgrade" or [InstalmentCount] = null or [InstalmentCount] = 0 or [annual_vet_net_premium] = null then null 
        else [annual_vet_net_premium] / [InstalmentCount], type number),
    AddIPT = Table.AddColumn(AddPrem, "Base_Installment_IPT", each 
        if [type] = "Upgrade" or [InstalmentCount] = null or [InstalmentCount] = 0 or [ipt] = null then null 
        else [ipt] / [InstalmentCount], type number),
    AddCommission = Table.AddColumn(AddIPT, "Base_Installment_Commission", each 
        if [type] = "Upgrade" or [InstalmentCount] = null or [InstalmentCount] = 0 or [annual_vet_commission] = null then null 
        else [annual_vet_commission] / [InstalmentCount], type number),
    AddAdminFee = Table.AddColumn(AddCommission, "Base_Installment_AdminFee", each 
        if [type] = "Upgrade" or [InstalmentCount] = null or [InstalmentCount] = 0 or [admin_fee] = null then null 
        else [admin_fee] / [InstalmentCount], type number),

    // Step 9: Upgrade Instalment Count
    UpgradeRows = Table.SelectRows(AddCancelFlag, each [type] = "Upgrade"),
    GroupUpgradeCount = Table.Group(
        UpgradeRows,
        {"reference", "Effective_Date", "policy_start_date", "interval", "AlignedStart"},
        {
            {"upgrade_instalment_count", each 
                let
                    firstRow = Table.FirstN(_, 1){0},
                    aligned = firstRow[AlignedStart],
                    policyEnd = firstRow[policy_end_date],
                    interval = firstRow[IntervalMonths],
                    count = if interval = 12 then 1
                            else List.Count(
                                List.Generate(
                                    () => aligned,
                                    (d) => d <= policyEnd,
                                    (d) => Date.AddMonths(d, interval)
                                )
                            )
                in count, Int64.Type}
        }
    ),
    JoinUpgradeCount = Table.NestedJoin(AddAdminFee, {"reference", "Effective_Date"}, GroupUpgradeCount, {"reference", "Effective_Date"}, "UpgradeCount", JoinKind.LeftOuter),
    ExpandUpgrade = Table.ExpandTableColumn(JoinUpgradeCount, "UpgradeCount", {"upgrade_instalment_count"}),

    // Step 10: Upgrade Instalments (Premium, IPT, Commission, Admin Fee)
    AddUpgradePrem = Table.AddColumn(ExpandUpgrade, "Upgrade_Installment_Premium", each 
        if [type] = "Upgrade" 
            and [upgrade_instalment_count] <> null 
            and [upgrade_instalment_count] > 0 
            and [annual_vet_net_premium] <> null then 
            [annual_vet_net_premium] / [upgrade_instalment_count] 
        else null, type number),
    AddUpgradeIPT = Table.AddColumn(AddUpgradePrem, "Upgrade_Installment_IPT", each 
        if [type] = "Upgrade" 
            and [upgrade_instalment_count] <> null 
            and [upgrade_instalment_count] > 0 
            and [ipt] <> null then 
            [ipt] / [upgrade_instalment_count] 
        else null, type number),
    AddUpgradeCommission = Table.AddColumn(AddUpgradeIPT, "Upgrade_Installment_Commission", each 
        if [type] = "Upgrade" 
            and [upgrade_instalment_count] <> null 
            and [upgrade_instalment_count] > 0 
            and [annual_vet_commission] <> null then 
            [annual_vet_commission] / [upgrade_instalment_count] 
        else null, type number),
    AddUpgradeAdminFee = Table.AddColumn(AddUpgradeCommission, "Upgrade_Installment_AdminFee", each 
        if [type] = "Upgrade" 
            and [upgrade_instalment_count] <> null 
            and [upgrade_instalment_count] > 0 
            and [admin_fee] <> null then 
            [admin_fee] / [upgrade_instalment_count] 
        else null, type number),

    // Final formatting
    #"Changed Type" = Table.TransformColumnTypes(AddUpgradeAdminFee, {
        {"policy_start_date", type date}, {"reference", type text}, {"cancelled_date", type date},
        {"days_used", Int64.Type}, {"days_paid", Int64.Type}, {"interval", type text}, {"type", type text},
        {"annual_cost", type number}, {"annual_vet_net_premium", type number}, {"ipt", type number}, 
        {"annual_vet_commission", type number}, {"admin_fee", type number},
        {"Effective_Date", type date}, {"policy_end_date", type date}, {"IntervalMonths", Int64.Type},
        {"AlignedStart", type date}, {"PayStart", type date}, {"PayDate", type date}, 
        {"payment_month_num", Int64.Type}, {"underwritten_month_num", Int64.Type}, 
        {"CancellationEffectiveDate", type date}, {"CancellationStatus", type text},
        {"InstalmentCount", Int64.Type}, 
        {"Base_Installment_Premium", type number}, {"Base_Installment_IPT", type number}, {"Base_Installment_Commission", type number}, {"Base_Installment_AdminFee", type number},
        {"upgrade_instalment_count", Int64.Type}, 
        {"Upgrade_Installment_Premium", type number}, {"Upgrade_Installment_IPT", type number}, {"Upgrade_Installment_Commission", type number}, {"Upgrade_Installment_AdminFee", type number}
    }),
    #"Added Custom" = Table.AddColumn(#"Changed Type", "CancellationEffectiveDate_YearMonthNum", each Date.Year([CancellationEffectiveDate]) * 100 + Date.Month([CancellationEffectiveDate]), Int64.Type)
in
    #"Added Custom"