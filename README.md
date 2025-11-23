# 📘 Insurance Premium Schedule Engine  
_An anonymised template for calculating automated insurance payment schedules._

---

## 📌 Overview

This project provides a **reusable, fully anonymised framework** for converting raw insurance policy events into a complete, automated **premium payment schedule**.

It supports:

- Monthly, quarterly, and annual instalments  
- Upgrades and mid-term changes  
- Cancellations (including lump-sum logic)  
- Base vs upgrade instalments  
- Net Premium, Tax, Commission, Admin components  
- Cohort-style reporting (Underwritten Month × Payment Month)

The goal is to replace days of manual reconciliation with a **transparent, auditable calculation engine**.

---

## 🔧 How It Works

### **1. Raw → Clean (Power Query)**  
The raw policy dataset is cleaned and normalised.  
Key steps include:

- Deriving effective dates  
- Handling fully-paid policies  
- Adjusting annual amounts  
- Identifying policy events (new, renewal, upgrade, cancellation)  
- Preparing columns used downstream (premiums, IPT, commissions, admin fees)

---

### **2. Payment Schedule Engine (Power Query)**  
This step builds a **complete instalment schedule** for each policy.

The engine:

- Generates payment dates based on frequency  
- Aligns upgrade events to the correct future instalments  
- Spreads upgrade amounts across remaining periods  
- Detects cancellations and calculates lump-sum settlements  
- Tags each row with payment month & underwritten month  
- Produces the final fact table for reporting

---

### **3. Date Tables**  
Two simple date dimensions support flexible reporting:

- **Underwritten Date Table** → cohort grouping  
- **Payment Date Table** → cashflow timing  

Both tables are built using a reusable date-table function.

---

### **4. Power BI Model**  
The final model links:

- Fact_Payments → dim_PymtDate  
- Fact_Payments → dim_UWDate  

This allows creation of a matrix showing:

- Underwritten Month on rows  
- Payment Month on columns  
- Any premium component (Net Prem, Tax, Commission, Admin) as values  

---

### **5. DAX Measures**  
Each product (A, B, C) includes four measures:

- Net Premium  
- Tax  
- Commission  
- Admin  

The DAX handles:

- Regular payments  
- Upgrade overlays  
- Cancellation adjustments  
- Lump sums  
- Correct month attribution via `USERELATIONSHIP`

All measure templates are included in the `/dax` folder and can be adapted to any data model.

---

## 🔄 Adapting This Template

1. Replace the sample raw dataset with your own policy events.  
2. Update column mappings in `01_raw_to_clean_base.m`.  
3. Regenerate the payment schedule using `02_generate_payment_schedule.m`.  
4. Rebuild the Power BI model using the date tables provided.  
5. Adjust the DAX measures using the templates.  

Once connected, the model produces a **fully automated, accurate premium schedule** that is easy to validate and audit.

---

If you'd like, I can also prepare:

- An even shorter README  
- A business-focused (“consulting style”) version  
- A README with icons/badges for extra GitHub polish  
- A version formatted like an internal technical specification  
