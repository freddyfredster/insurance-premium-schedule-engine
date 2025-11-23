// dim_UWDate.m
// Underwritten date dimension – one row per calendar month.
//
// Depends on fnDateTable function.
// Adjust date range and FYStartMonth as needed.

let
    Source = fnDateTable(#date(2022, 1, 1), #date(2026, 12, 31), 4),

    #"Inserted Start of Month" =
        Table.AddColumn(Source, "MonthStart", each Date.StartOfMonth([Date]), type date),

    #"Add MonthYearShort column" =
        Table.AddColumn(
            #"Inserted Start of Month",
            "MonthYearShort",
            each Date.ToText([MonthStart], "MMM yy"),
            type text
        ),

    AddMonthYearNum =
        Table.AddColumn(
            #"Add MonthYearShort column",
            "MonthYearNum",
            each Date.Year([MonthStart]) * 100 + Date.Month([MonthStart]),
            Int64.Type
        ),

    #"Removed Duplicates" = Table.Distinct(AddMonthYearNum, {"MonthYearNum"}),

    FinalSelection =
        Table.SelectColumns(
            #"Removed Duplicates",
            {
                "MonthYearNum",     // join key
                "MonthStart",
                "MonthYearShort"
            }
        )

in
    FinalSelection
