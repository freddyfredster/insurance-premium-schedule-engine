// 01_raw_to_clean_base.m
// Purpose:
//   Take the raw export of policies and normalise it into a clean base table
//   ready for the payment schedule / allocation engine.
//
//   IMPORTANT:
//   - A single PolicyID can appear multiple times (New, Renewal, Upgrade,
//     Cancellation, etc.).
//   - We KEEP every event row. We do NOT try to merge them here.
//   - Later steps in the engine will interpret these events and build the
//     correct payment schedule.
//
// How to adapt to your own data:
//   1. Replace the [Source] step with how you actually connect to your data
//      (SQL, dataflow, CSV, etc.).
//   2. Map your columns to the generic names used here:
//        - Policy ID          -> [PolicyID]
//        - Start date         -> [PolicyStartDate]
//        - Cancellation date  -> [CancellationDate]
//        - Payment frequency  -> [PaymentFrequency] (monthly / quarterly / annual)
//        - Product premiums   -> [ProductA_Premium], [ProductB_Premium], [ProductC_Premium]
//        - Tax / commission   -> [ProductA_TaxAmount], [ProductA_Commission], etc.
//   3. Review the business rules (e.g. "DaysPaid >= 365 ⇒ zero out amounts")
//      and change them to match your own logic.

let
    //---------------------------------------------
    // 0. Source: connect to your raw policies table
    //---------------------------------------------
    // For the GitHub sample, we assume the raw data is loaded into a table
    // named "RawPolicies" in Power Query.
    //
    // In a real project, this might be:
    //   - A SQL query
    //   - A Power BI dataflow
    //   - A CSV or Excel file
    //
    // Replace this Source step with your own.
    Source =
        Excel.CurrentWorkbook(){[Name = "RawPolicies"]}[Content],

    //---------------------------------------------
    // 1. Keep only the columns needed by the engine
    //---------------------------------------------
    KeepRelevantColumns =
        Table.SelectColumns(
            Source,
            {
                "RecordID",
                "PolicyID",
                "TransactionType",
                "PolicyStartDate",
                "CancellationDate",
                "DaysUsed",
                "DaysPaid",
                "PaymentFrequency",
                "AnnualTotalCharge",
                "ProductA_Premium",
                "ProductA_TaxAmount",
                "ProductA_Commission",
                "ProductA_AdminFee",
                "ProductB_Premium",
                "ProductB_TaxAmount",
                "ProductB_Commission",
                "ProductC_Premium",
                "ProductC_TaxAmount",
                "ProductC_Commission",
                "ProductC_AdminFee"
            }
        ),

    //---------------------------------------------
    // 2. (Optional) Filter to a relevant date range
    //---------------------------------------------
    // In the original implementation we filtered to a recent start date.
    // If you want full history, remove or change this filter.
    FilterByStartDate =
        Table.SelectRows(
            KeepRelevantColumns,
            each [PolicyStartDate] >= #date(2023, 1, 1)
        ),

    //---------------------------------------------
    // 3. Apply business rule: fully paid policies
    //---------------------------------------------
    // Original idea:
    //   - If [DaysPaid] >= 365, treat the policy as fully paid and
    //     set monetary columns to 0 so they don't get picked up
    //     again by the schedule engine.
    //
    // This is just an example. If your system has a different definition
    // of "fully paid", adapt the condition inside the function.
    WithFullyPaidZeroed =
        let
            colsToZero =
                {
                    "AnnualTotalCharge",
                    "ProductA_Premium",
                    "ProductA_TaxAmount",
                    "ProductA_Commission",
                    "ProductA_AdminFee",
                    "ProductB_Premium",
                    "ProductB_TaxAmount",
                    "ProductB_Commission",
                    "ProductC_Premium",
                    "ProductC_TaxAmount",
                    "ProductC_Commission",
                    "ProductC_AdminFee"
                },

            // Helper: if DaysPaid >= 365, force 0, otherwise keep value
            ZeroIfFullyPaid =
                (value as any, row as record) as any =>
                    if row[DaysPaid] >= 365 then
                        0
                    else
                        value,

            ZeroedTable =
                Table.TransformColumns(
                    FilterByStartDate,
                    List.Transform(
                        colsToZero,
                        (colName as text) =>
                            { colName, (v, r) => ZeroIfFullyPaid(v, r), type number }
                    )
                )
        in
            ZeroedTable,

    //---------------------------------------------
    // 4. Derive EventEffectiveDate
    //---------------------------------------------
    // We create a single "event effective date" per row so later logic
    // can decide when an event (new, upgrade, cancel, etc.) should start
    // affecting the schedule.
    //
    // Example generic rule:
    //   - If there is no cancellation date, or it's earlier than start,
    //     use PolicyStartDate.
    //   - Otherwise use CancellationDate.
    //
    // If you have explicit upgrade dates / cancel dates in separate columns,
    // you can adjust this logic to use those instead.
    AddEventEffectiveDate =
        Table.AddColumn(
            WithFullyPaidZeroed,
            "EventEffectiveDate",
            each
                if [CancellationDate] = null
                    or [CancellationDate] < [PolicyStartDate]
                then
                    [PolicyStartDate]
                else
                    [CancellationDate],
            type date
        ),

    //---------------------------------------------
    // 5. Derive PolicyEndDate
    //---------------------------------------------
    // Business rule used here:
    //   - Policies run for 12 months from the start date.
    //   - Model the end as the end of the month, 11 months after start.
    //
    // If your policies can be 6, 12, 24 months, etc., this is the place
    // to plug in that term logic instead of a hard-coded 11.
    AddPolicyEndDate =
        Table.AddColumn(
            AddEventEffectiveDate,
            "PolicyEndDate",
            each Date.EndOfMonth(Date.AddMonths([PolicyStartDate], 11)),
            type date
        ),

    //---------------------------------------------
    // 6. Set final data types
    //---------------------------------------------
    // At this point:
    //   - We still have ONE ROW per policy event.
    //   - A PolicyID may appear once (simple policy) or many times
    //     (New + Upgrade + Cancellation, etc.).
    //   - Later steps in the engine will interpret these events
    //     when generating the payment schedule.
    CleanTypes =
        Table.TransformColumnTypes(
            AddPolicyEndDate,
            {
                {"RecordID", Int64.Type},
                {"PolicyID", type text},
                {"TransactionType", type text},
                {"PolicyStartDate", type date},
                {"CancellationDate", type date},
                {"DaysUsed", Int64.Type},
                {"DaysPaid", Int64.Type},
                {"PaymentFrequency", type text},
                {"AnnualTotalCharge", type number},
                {"ProductA_Premium", type number},
                {"ProductA_TaxAmount", type number},
                {"ProductA_Commission", type number},
                {"ProductA_AdminFee", type number},
                {"ProductB_Premium", type number},
                {"ProductB_TaxAmount", type number},
                {"ProductB_Commission", type number},
                {"ProductC_Premium", type number},
                {"ProductC_TaxAmount", type number},
                {"ProductC_Commission", type number},
                {"ProductC_AdminFee", type number},
                {"EventEffectiveDate", type date},
                {"PolicyEndDate", type date}
            }
        )

in
    CleanTypes
