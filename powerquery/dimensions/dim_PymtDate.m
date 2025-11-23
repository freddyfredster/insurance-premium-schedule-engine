let
    Source = fn_GenerateDates(#date(2022, 1, 1), #date(2026, 12, 31), 4),
// Use the start of month as the month anchor
    #"Inserted Start of Month" =
        Table.AddColumn(Source, "MonthStart", each Date.StartOfMonth([Date]), type date),

    // Short label like "Feb 24"
    #"Add MonthYearShort column" =
        Table.AddColumn(
            #"Inserted Start of Month",
            "MonthYearShort",
            each Date.ToText([MonthStart], "MMM yy"),
            type text
        ),

    // Numeric YYYYMM key – this is what joins to the fact table
    AddMonthYearNum =
        Table.AddColumn(
            #"Add MonthYearShort column",
            "MonthYearNum",
            each Date.Year([MonthStart]) * 100 + Date.Month([MonthStart]),
            Int64.Type
        ),

    // One row per MonthYearNum (monthly grain)
    #"Removed Duplicates" = Table.Distinct(AddMonthYearNum, {"MonthYearNum"})
in
    #"Removed Duplicates"