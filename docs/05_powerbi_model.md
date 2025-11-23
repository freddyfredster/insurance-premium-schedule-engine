# Power BI Data Model – Cohort Matrix for Premium Payments

This document explains how the **payment schedule engine** is wired into a Power BI model so we can build a **cohort-style matrix**:

> Underwritten Month (rows) × Payment Month (columns)  
> → Premium / Tax / Commission / Admin by Product (A, B, C)

The focus is on the **semantic model** and the **DAX logic**, not on visuals styling.

---

## 1. Tables in the model

### 1.1 Fact table – `PaymentSchedule`

Loaded from the query built with:

- `powerquery/02_generate_payment_schedule.m`

Key columns:

- `PolicyID`
- `PayDate`
- `PaymentMonthNum` (YYYYMM)
- `UnderwrittenMonthNum` (YYYYMM)
- `CancellationStatus`  
  (`No Cancellation`, `Before Cancellation`, `In Cancellation Month`, `After Cancellation`, `Renewal Cancellation`)
- (optional) `CancellationEffectiveDate_YearMonthNum` (YYYYMM of cancellation)
- Base instalments:
  - `Base_Installment_ProductA`
  - `Base_Installment_ProductB`
  - `Base_Installment_ProductC`
- Upgrade instalments:
  - `Upgrade_Installment_ProductA`
  - `Upgrade_Installment_ProductB`
  - `Upgrade_Installment_ProductC`

> In your own model, you can add extra columns for tax, commission, admin etc. The DAX measures assume you’ve separated out the base and upgrade portions per product.

---

### 1.2 Date dimensions

We use **two separate date tables**, both generated from the same reusable function in:

- `powerquery/functions/fn_DateTable.m`

#### `dim_PymtDate` – Payment Date

Created from:

- `powerquery/dimensions/dim_PymtDate.m`

Important columns:

- `MonthYearNum`   (YYYYMM) – **joins to `PaymentSchedule[PaymentMonthNum]`**
- `MonthStart`     (date)
- `MonthYearShort` (e.g. `Feb 24`)

#### `dim_UWDate` – Underwritten Date

Created from:

- `powerquery/dimensions/dim_UWDate.m`

Important columns:

- `MonthYearNum`   (YYYYMM) – **joins to `PaymentSchedule[UnderwrittenMonthNum]`**
- `MonthStart`
- `MonthYearShort`

Both tables are **monthly grain** (one row per calendar month). If you need daily granularity, you can keep the full date table and aggregate in DAX instead.

---

### 1.3 Measures table (optional but recommended)

Create an empty table in Power BI:

```DAX
_Measures = { "placeholder" }

Delete the placeholder column so it becomes a measure-only table.
All measures for Product A/B/C live here and are referenced by the field parameter tables.

2. Relationships

Configure relationships as follows:

2.1 Payment month relationship

From:

dim_PymtDate[MonthYearNum] (1)

To:

PaymentSchedule[PaymentMonthNum] (many)

Cardinality: One-to-many
Cross-filter direction: Single (from dim_PymtDate to PaymentSchedule)

2.2 Underwritten month relationship

From:

dim_UWDate[MonthYearNum] (1)

To:

PaymentSchedule[UnderwrittenMonthNum] (many)

Cardinality: One-to-many
Cross-filter direction: Single

2.3 Optional cancellation relationship

If you have a numeric cancellation month (YYYYMM) like:

PaymentSchedule[CancellationEffectiveDate_YearMonthNum]

you can create an inactive relationship to the payment date dim:

From:

dim_PymtDate[MonthYearNum] (1)

To:

PaymentSchedule[CancellationEffectiveDate_YearMonthNum] (many)

Set this relationship to Inactive and use USERELATIONSHIP inside DAX when you want to calculate amounts “in cancellation month” or “after cancellation”.

3. Why two date tables?

We separate:

Underwritten date → defines the cohort (when the business was written)

Payment date → defines cashflow/earnings timing (when the money is due)

This lets the matrix answer questions like:

“For policies written in Feb 2023, how does the premium play out month by month?”

“How long does it take each cohort to fully earn out?”

“Which cohorts are still generating cash in a given period?”

4. Cohort matrix setup

Create a Matrix visual in Power BI:

Rows: dim_UWDate[MonthYearShort]

Columns: dim_PymtDate[MonthYearShort]

Values: field parameter from the measure selection table (see below)

This gives a grid:

rows = underwritten month (cohort)

columns = payment month

values = selectable metric (net premium, tax, commission, admin) for Product A / B / C.

5. Measure selection (field parameter) pattern

To avoid building separate pages for each metric, we use field parameters as a measure selector.

5.1 Example: Product A measure selection table

In Power BI, create a new table with this DAX:

ProductA Measure Selection = {
    ("Net Prem", NAMEOF('_Measures'[productA_payment_total]), 0),
    ("Tax",      NAMEOF('_Measures'[productA_tax_total]),     1),
    ("Comm",     NAMEOF('_Measures'[productA_comm_total]),    2),
    ("Admin",    NAMEOF('_Measures'[productA_admin_total]),   3)
}


Power BI will automatically create:

ProductA Measure Selection

ProductA Measure Selection Fields (field parameter)

ProductA Measure Selection Order

Do the same for Product B and Product C if you want separate selectors.

In the sample report, the user selects which metric they want to see (Net Prem, Tax, Comm, Admin) via buttons tied to this parameter.

5.2 Using the selector in the matrix

For Product A:

Add ProductA Measure Selection Fields to the Values bucket of the matrix.

Optionally use the measure selection table in a slicer or set of buttons to limit which metrics appear.

Repeat per product if you build separate pages or separate matrices.

6. DAX – generic product payment logic

Below is a generic pattern for Product A.
You can copy and adapt it for Product B and C.

Table and column names assume you’ve renamed your fact to PaymentSchedule and used the engine’s column naming. Adjust as needed.

6.1 Total net premium – productA_payment_total
productA_payment_total =

VAR RegularPayments =
    SUMX(
        FILTER(
            PaymentSchedule,
            PaymentSchedule[CancellationStatus] IN {
                "Before Cancellation",
                "No Cancellation"
            }
        ),
        PaymentSchedule[Base_Installment_ProductA] +
        PaymentSchedule[Upgrade_Installment_ProductA]
    )

VAR RemainingPremium =
    CALCULATE(
        SUMX(
            FILTER(
                PaymentSchedule,
                PaymentSchedule[CancellationStatus] IN {
                    "After Cancellation",
                    "In Cancellation Month"
                }
                && PaymentSchedule[EventType] <> "Cancelled"
            ),
            PaymentSchedule[Base_Installment_ProductA] +
            PaymentSchedule[Upgrade_Installment_ProductA]
        ),
        USERELATIONSHIP(
            PaymentSchedule[CancellationEffectiveDate_YearMonthNum],
            dim_PymtDate[MonthYearNum]
        )
    )

VAR CancelledRowPremium =
    CALCULATE(
        SUMX(
            FILTER(
                PaymentSchedule,
                PaymentSchedule[EventType] = "Cancelled"
                    && PaymentSchedule[CancellationStatus] IN {
                        "In Cancellation Month",
                        "Renewal Cancellation"
                    }
            ),
            PaymentSchedule[Base_Installment_ProductA] +
            PaymentSchedule[Upgrade_Installment_ProductA]
        ),
        USERELATIONSHIP(
            PaymentSchedule[CancellationEffectiveDate_YearMonthNum],
            dim_PymtDate[MonthYearNum]
        )
    )

VAR LumpSum = CancelledRowPremium + RemainingPremium

RETURN
    RegularPayments + LumpSum


This mirrors the business rules:

normal instalments run up to cancellation

remaining instalments are pulled into a lump sum in the cancellation month

the cancellation row itself is also included (often a negative adjustment)

6.2 Other components (Tax, Commission, Admin)

Repeat the same pattern, but swap which columns you sum.

For example, for Tax on Product A:

productA_tax_total =

VAR RegularPayments =
    SUMX(
        FILTER(
            PaymentSchedule,
            PaymentSchedule[CancellationStatus] IN {
                "Before Cancellation",
                "No Cancellation"
            }
        ),
        PaymentSchedule[Base_Installment_Tax_ProductA] +
        PaymentSchedule[Upgrade_Installment_Tax_ProductA]
    )

VAR RemainingTax =
    CALCULATE(
        SUMX(
            FILTER(
                PaymentSchedule,
                PaymentSchedule[CancellationStatus] IN {
                    "After Cancellation",
                    "In Cancellation Month"
                }
                && PaymentSchedule[EventType] <> "Cancelled"
            ),
            PaymentSchedule[Base_Installment_Tax_ProductA] +
            PaymentSchedule[Upgrade_Installment_Tax_ProductA]
        ),
        USERELATIONSHIP(
            PaymentSchedule[CancellationEffectiveDate_YearMonthNum],
            dim_PymtDate[MonthYearNum]
        )
    )

VAR CancelledRowTax =
    CALCULATE(
        SUMX(
            FILTER(
                PaymentSchedule,
                PaymentSchedule[EventType] = "Cancelled"
                    && PaymentSchedule[CancellationStatus] IN {
                        "In Cancellation Month",
                        "Renewal Cancellation"
                    }
            ),
            PaymentSchedule[Base_Installment_Tax_ProductA] +
            PaymentSchedule[Upgrade_Installment_Tax_ProductA]
        ),
        USERELATIONSHIP(
            PaymentSchedule[CancellationEffectiveDate_YearMonthNum],
            dim_PymtDate[MonthYearNum]
        )
    )

VAR LumpSum = CancelledRowTax + RemainingTax

RETURN
    RegularPayments + LumpSum


Create similar measures for:

productA_comm_total

productA_admin_total

…and then replicate for Product B and Product C.

7. Matrix example

For a Product A page:

Rows: dim_UWDate[MonthYearShort]

Columns: dim_PymtDate[MonthYearShort]

Values: ProductA Measure Selection Fields (field parameter)

Filters: optional slicers for product / policy type / reference

You now get a matrix very similar to the screenshot in the repo:
each cell = chosen metric for (Underwritten Month, Payment Month).

8. Adapting to your own environment

To use this in your own model:

Adjust the engine so it produces the base/upgrade columns you need.

Make sure you expose:

PaymentMonthNum

UnderwrittenMonthNum

(optional) CancellationEffectiveDate_YearMonthNum

Generate your date tables using fnDateTable.

Copy the DAX templates into your own _Measures table and rename columns.

Adjust the field parameter tables to point to your measures.

The pattern stays the same even if your products, tax rules, or policy structures differ.


---

## 2️⃣ DAX files for `/dax` folder

You don’t *have* to mirror this structure 1:1, but here’s a clean, reusable layout.

### `dax/01_measure_selection/productA_measure_selection_table.dax`

```DAX
// Product A – field parameter acting as a measure selector.
// Drop 'ProductA Measure Selection Fields' into your matrix Values area.

ProductA Measure Selection = {
    ("Net Prem", NAMEOF('_Measures'[productA_payment_total]), 0),
    ("Tax",      NAMEOF('_Measures'[productA_tax_total]),     1),
    ("Comm",     NAMEOF('_Measures'[productA_comm_total]),    2),
    ("Admin",    NAMEOF('_Measures'[productA_admin_total]),   3)
}


You can copy this and replace ProductA with ProductB / ProductC for the other products.