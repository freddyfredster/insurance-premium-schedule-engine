// fn_DateTable.m
// Reusable function to generate a rich date table.
// Parameters:
//   StartDate    - first date to include
//   EndDate      - last date to include
//   FYStartMonth - month number your financial year starts on (e.g. 4 for April)
//
// Usage in a query:
//   = fnDateTable(#date(2022, 1, 1), #date(2026, 12, 31), 4)

let
    fnDateTable = (StartDate as date, EndDate as date, FYStartMonth as number) as table =>
    let
        // List of all dates between StartDate and EndDate
        DayCount       = Duration.Days(Duration.From(EndDate - StartDate)) + 1,
        Source         = List.Dates(StartDate, DayCount, #duration(1, 0, 0, 0)),
        TableFromList  = Table.FromList(Source, Splitter.SplitByNothing()),
        ChangedType    = Table.TransformColumnTypes(TableFromList, {{"Column1", type date}}),
        RenamedColumns = Table.RenameColumns(ChangedType, {{"Column1", "Date"}}),

        // Hardcoded UK Bank Holidays (2023–2025)
        // Adjust for your own country / years as needed.
        BankHolidays = {
            // 2023
            #date(2023, 1, 2), #date(2023, 4, 7), #date(2023, 4, 10), #date(2023, 5, 1),
            #date(2023, 5, 8), #date(2023, 5, 29), #date(2023, 8, 28), #date(2023, 12, 25), #date(2023, 12, 26),
            // 2024
            #date(2024, 1, 1), #date(2024, 3, 29), #date(2024, 4, 1), #date(2024, 5, 6),
            #date(2024, 5, 27), #date(2024, 8, 26), #date(2024, 12, 25), #date(2024, 12, 26),
            // 2025
            #date(2025, 1, 1), #date(2025, 4, 18), #date(2025, 4, 21), #date(2025, 5, 5),
            #date(2025, 5, 26), #date(2025, 8, 25), #date(2025, 12, 25), #date(2025, 12, 26)
        },

        // Standard calendar fields
        InsertYear          = Table.AddColumn(RenamedColumns, "Year", each Date.Year([Date]), type text),
        InsertYearNumber    = Table.AddColumn(InsertYear, "YearNumber", each Date.Year([Date])),
        InsertQuarter       = Table.AddColumn(InsertYearNumber, "QuarterOfYear", each Date.QuarterOfYear([Date])),
        InsertMonth         = Table.AddColumn(InsertQuarter, "MonthOfYear", each Date.Month([Date]), type text),
        InsertDay           = Table.AddColumn(InsertMonth, "DayOfMonth", each Date.Day([Date])),
        InsertDayInt        = Table.AddColumn(InsertDay, "DateInt", each [YearNumber] * 10000 + Number.From([MonthOfYear]) * 100 + [DayOfMonth]),
        InsertMonthName     = Table.AddColumn(InsertDayInt, "MonthName", each Date.ToText([Date], "MMMM"), type text),
        InsertCalendarMonth = Table.AddColumn(InsertMonthName, "MonthInCalendar", each Text.Start([MonthName], 3) & " " & Text.From([YearNumber])),
        InsertCalendarQtr   = Table.AddColumn(InsertCalendarMonth, "QuarterInCalendar", each "Q" & Text.From([QuarterOfYear]) & " " & Text.From([YearNumber])),
        InsertDayWeek       = Table.AddColumn(InsertCalendarQtr, "DayInWeek", each Date.DayOfWeek([Date], Day.Monday)),  // Monday = 0
        InsertDayName       = Table.AddColumn(InsertDayWeek, "DayOfWeekName", each Date.ToText([Date], "dddd"), type text),
        InsertWeekStarting  = Table.AddColumn(InsertDayName, "WeekStarting", each Date.StartOfWeek([Date], Day.Monday), type date),
        InsertWeekEnding    = Table.AddColumn(InsertWeekStarting, "WeekEnding", each Date.EndOfWeek([Date], Day.Monday), type date),
        InsertWeekNumber    = Table.AddColumn(InsertWeekEnding, "Week Number", each Date.WeekOfYear([Date], Day.Monday)),

        // FY start (week containing 1 April, UK-style FY)
        AddFYStartDate =
            Table.AddColumn(
                InsertWeekNumber,
                "FYStartDate",
                each
                    let
                        current = [Date],
                        fyYear  = if current >= #date(Date.Year(current), 4, 1) then Date.Year(current) else Date.Year(current) - 1,
                        apr1    = #date(fyYear, 4, 1),
                        fyStart = Date.StartOfWeek(apr1, Day.Monday)
                    in
                        fyStart,
                type date
            ),

        AddFYWeekNumber =
            Table.AddColumn(
                AddFYStartDate,
                "FY Week Number",
                each
                    let
                        daysBetween = Duration.Days([Date] - [FYStartDate]),
                        weekNumber  = Number.RoundDown(daysBetween / 7) + 1
                    in
                        if daysBetween < 0 then null else weekNumber,
                Int64.Type
            ),

        InsertMonthnYear   = Table.AddColumn(AddFYWeekNumber, "MonthnYear", each [YearNumber] * 10000 + Number.From([MonthOfYear]) * 100),
        InsertQuarternYear = Table.AddColumn(InsertMonthnYear, "QuarternYear", each [YearNumber] * 10000 + [QuarterOfYear] * 100),

        ChangedType1 =
            Table.TransformColumnTypes(
                InsertQuarternYear,
                {
                    {"QuarternYear", Int64.Type}, {"Week Number", Int64.Type}, {"Year", type text},
                    {"MonthnYear", Int64.Type}, {"DateInt", Int64.Type}, {"DayOfMonth", Int64.Type},
                    {"MonthOfYear", Int64.Type}, {"QuarterOfYear", Int64.Type},
                    {"MonthInCalendar", type text}, {"QuarterInCalendar", type text},
                    {"DayInWeek", Int64.Type}
                }
            ),

        InsertShortYear = Table.AddColumn(ChangedType1, "ShortYear", each Text.End(Text.From([Year]), 2), type text),

        AddFY =
            Table.AddColumn(
                InsertShortYear,
                "FY",
                each "FY" &
                    (if [MonthOfYear] >= FYStartMonth
                        then Text.From(Number.From([ShortYear]) + 1)
                        else [ShortYear]
                    )
            ),

        // Working day flag (0 = weekend or bank holiday)
        AddWorkingDayFlag =
            Table.AddColumn(
                AddFY,
                "IsWorkingDay",
                each if List.Contains(BankHolidays, [Date]) or [DayInWeek] >= 5 then 0 else 1,
                Int64.Type
            )

    in
        AddWorkingDayFlag
in
    fnDateTable
