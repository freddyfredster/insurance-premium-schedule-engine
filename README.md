# insurance-premium-schedule-engine

An end-to-end, anonymised **premium payment allocation engine** for insurance brokers.

It turns raw policy events (new business, renewals, upgrades, cancellations) into:

- a **clean base table**,
- a fully **exploded payment schedule**, and
- a **Power BI data model** with a **cohort-style matrix** showing, for each underwritten month and payment month, how much **Net Premium, Tax, Commission and Admin** is due per product.

All sample data is fictitious and fully anonymised.

---

## Problem this solves

In many broker environments, month-end reporting looks like this:

- policies can be paid **monthly, quarterly, or annually**  
- customers can **upgrade or cancel** mid-term  
- there are **multiple products** per policy (Product A/B/C)  
- premium, tax, commission and admin all have to be allocated correctly  
- the finance team spends **days in Excel** manually adjusting schedules

This project shows how to:

1. Model the logic once in **Power Query + DAX**, and  
2. Produce a **repeatable, auditable payment schedule** that can refresh automatically.

---

### Repository layout
data/
  raw/      → anonymised input (sample_policies_raw.csv)
  clean/    → cleaned base table (sample_policies_clean.csv)
  engine/   → exploded payment schedule (sample_payment_schedule.csv)

powerquery/
  01_raw_to_clean_base.m            → RawPolicies → CleanPolicies
  02_generate_payment_schedule.m    → CleanPolicies → PaymentSchedule
  functions/
    fn_DateTable.m                  → reusable date table function
  dimensions/
    dim_PymtDate.m                  → payment month dimension
    dim_UWDate.m                    → underwritten month dimension

dax/
  01_measure_selection/
    productA_measure_selection_table.dax
    (optional) productB/C equivalents
  02_product_measures/
    productA_payment_total.dax
    productA_tax_total.dax
    productA_comm_total.dax
    productA_admin_total.dax
    (templates for Product B/C)
  03_engine_logic/
    final_measure_template.dax
    cancellation_logic_explainer.md

docs/
  01_overview.md
  02_raw_data_structure.md
  03_logic_walkthrough.md
  04_building_the_engine.md
  05_powerbi_model.md

### Quickstart

1. Open the sample in Power BI Desktop

Clone this repo and open Power BI Desktop.

Get Data → Text/CSV → load:

data/raw/sample_policies_raw.csv as RawPolicies

In Power Query:

Add a blank query and paste powerquery/01_raw_to_clean_base.m → name it CleanPolicies

Add another blank query and paste powerquery/02_generate_payment_schedule.m → name it PaymentSchedule

Add fn_DateTable.m, dim_PymtDate.m, dim_UWDate.m from powerquery/functions and powerquery/dimensions.

Close & Apply.

2. Build the model

In the Model view:

Create relationships:

dim_PymtDate[MonthYearNum] → PaymentSchedule[PaymentMonthNum] (1-* , single direction)

dim_UWDate[MonthYearNum] → PaymentSchedule[UnderwrittenMonthNum] (1-* , single direction)

Optionally create an inactive relationship:

dim_PymtDate[MonthYearNum] → PaymentSchedule[CancellationEffectiveDate_YearMonthNum]

Use USERELATIONSHIP in measures to bring remaining amounts into the cancellation month.

3. Add the measures

Create an empty table called _Measures:

_Measures = { "placeholder" }


Then delete the placeholder column so the table only holds measures.

In _Measures, add the measures from:

dax/02_product_measures/productA_*.dax

(Optional) Duplicate them for Product B/C if you want full parity.

4. Create measure selection (field parameter)

Create a new table in DAX from:

dax/01_measure_selection/productA_measure_selection_table.dax

Power BI will create:

ProductA Measure Selection

ProductA Measure Selection Fields

ProductA Measure Selection Order

Use ProductA Measure Selection Fields as the Values field in your matrix so you can toggle between:

Net Prem

Tax

Comm

Admin

5. Build the cohort matrix

Add a Matrix visual.

Set:

Rows: dim_UWDate[MonthYearShort]

Columns: dim_PymtDate[MonthYearShort]

Values: ProductA Measure Selection Fields

You now have a grid:

rows = the month the policy was underwritten (cohort)

columns = the month the premium/tax/comm/admin is due

values = one of the Product A metrics, dynamically switched via the selector.

Adapting to your own environment

To use this engine with your own data:

Replace sample_policies_raw.csv with an extract from your policy admin or bordereaux system.

Adjust the column names and rules in 01_raw_to_clean_base.m and 02_generate_payment_schedule.m.

Extend the fact table with additional components if needed (fees, surcharges, different products).

Use dax/03_engine_logic/final_measure_template.dax as a blueprint to create new measures.

Decide whether to:

keep a shared Admin component, or

split it per product in Power Query and DAX.

The logic is intentionally transparent so you can explain and audit how every number is calculated.

### Documentation

For more detail, read:

docs/01_overview.md – business context

docs/02_raw_data_structure.md – raw schema explanation

docs/03_logic_walkthrough.md – end-to-end logic

docs/04_building_the_engine.md – how to run the M scripts

docs/05_powerbi_model.md – Power BI model & cohort matrix

This repo is meant to be a blueprint:
you can fork it, swap the data, adjust the rules, and end up with a robust premium allocation engine tailored to your own products.