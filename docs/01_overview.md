# Insurance Premium Schedule Engine – Overview

This project demonstrates a fully anonymised, fully reproducible version of a premium payment allocation engine built for an insurance brokerage context.

Insurance brokers often need to reconcile premium payments between:
- policy holders (who pay the broker), and  
- the insurance underwriter (who receives the money).

This becomes extremely complex when policies can:
- be paid monthly, quarterly, or annually  
- be upgraded mid-term  
- be cancelled mid-term  
- have multiple products inside one policy  
- have adjustments and administrative fees  
- generate obligations that stretch months into the future  

Traditionally this reconciliation is done manually in spreadsheets and can take **several days** every month.

This project shows how to automate that logic end-to-end using:
- **Sample anonymised policy data**  
- **Power Query (M) logic** to transform and model the calculation engine  
- **A fully exploded payment schedule** showing what is due when  
- **A cohort-style layout** (underwritten month × payment month) that makes reporting and auditing simple  

Everything in this repository is built from **fully anonymised data** and **generic rules** so you can adapt it to your environment.

---

## What this project delivers

**1. A clean base table**  
A prepared version of the raw policy dataset with:
- a consistent “event effective date”
- a standardised policy-end date
- handling of fully-paid rows
- removal of non-essential fields

**2. A full payment schedule engine**  
This engine:
- generates every scheduled payment date  
- allocates the annual premium and tax into instalments  
- classifies rows relative to cancellations  
- handles upgrades separately  
- produces a dataset ready for analytics and Power BI reporting  

**3. A complete documentation trail**  
Each step is described clearly so others can:
- plug in their own data  
- adjust the business rules  
- use the logic as a blueprint for their own solution  

---

## Who this project is for

- **Insurance brokers** wanting to streamline month-end reporting  
- **BI developers** building automated reconciliation tools  
- **Data teams** dealing with complex renewal/upgrade/cancellation logic  
- **Consultants** needing a reliable, reusable template  
- **Anyone** who wants to learn how to convert messy business rules into a robust analytical engine  

---

## Repository structure (high-level)

data/
raw/ → anonymised sample input
clean/ → processed base table
engine/ → exploded payment schedule

powerquery/
01_raw_to_clean_base.m
02_generate_payment_schedule.m

docs/
01_overview.md
02_raw_data_structure.md
03_logic_walkthrough.md
04_building_the_engine.md

README.md → main entry point

You can now continue to the next document for details on the raw data structure.