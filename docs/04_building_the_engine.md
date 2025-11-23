# Building the Engine in Power BI

This guide explains how to use the Power Query M scripts in this repository to reproduce the payment schedule engine in your own Power BI project.

---

# 1. Import the raw sample data

1. Open Power BI Desktop  
2. Select **Get Data → Text/CSV**  
3. Load:

data/raw/sample_policies_raw.csv


Rename the query to:



RawPolicies


---

# 2. Create Step 01 (Raw → Clean)

1. In the **Queries pane**, choose **New Query → Blank Query**  
2. Open **Advanced Editor**  
3. Paste the content of:



powerquery/01_raw_to_clean_base.m


4. Rename the query:



CleanPolicies


This will generate the cleaned, standardised dataset.

---

# 3. Create Step 02 (Clean → Schedule)

1. Create another **Blank Query**  
2. Open **Advanced Editor**  
3. Paste:



powerquery/02_generate_payment_schedule.m


4. Rename the query:



PaymentSchedule


This will explode policies into monthly / quarterly / annual rows.

---

# 4. Review the output tables

You should now have:

- **RawPolicies**  
- **CleanPolicies**  
- **PaymentSchedule**

with sample data that aligns to the CSV files inside the repo.

---

# 5. Customising for your own data

You may need to adjust:

### Payment frequencies  
In Step 02:
```m
if freq = "monthly" then 1
else if freq = "quarterly" then 3
else if freq = "annual" then 12

Fully-paid rule

In Step 01, change the DaysPaid logic or remove it completely.

Cancellation logic

You can adjust how cancellation dates are determined and how cancellations flow into the schedule.

Annual premium allocation

If you need to:

treat admin fees separately

include commissions

handle partial-term premiums
you can extend Section 8 of Step 02.

6. Next steps (Power BI visual layer)

Once you have the PaymentSchedule table, you can:

Build a cohort matrix (underwritten vs payment month)

Create total premium measures

Add filters for Product A/B/C

Build time-series views for cashflow analysis

A full Power BI model walkthrough will be added later.

You now have the full transformation engine running inside Power BI.
Proceed to the main README for repository-level guidance.