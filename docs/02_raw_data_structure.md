# Raw Data Structure – `sample_policies_raw.csv`

This file represents a simplified version of what an insurance broker might extract from their policy administration system. It is **entirely anonymised** but reflects the real behaviour of policy events.

A single policy can appear in multiple rows because events occur throughout its lifetime:

- New business  
- Renewal  
- Upgrade  
- Cancellation  

Each row describes **one event**.

---

## Columns

| Column | Description |
|-------|-------------|
| **RecordID** | Unique row identifier (sample only). |
| **PolicyID** | Policy reference. Can appear multiple times due to upgrades/cancellations. |
| **TransactionType** | One of: `New`, `Renewal`, `Upgrade`, `Cancellation`. |
| **PolicyStartDate** | Start of the policy term. |
| **CancellationDate** | Only filled for cancellation events. |
| **DaysUsed** | Provided by the original system. Unused in simplified logic but preserved. |
| **DaysPaid** | Used to determine if a policy is “fully paid”. |
| **PaymentFrequency** | `monthly`, `quarterly`, or `annual`. |
| **AnnualTotalCharge** | Total annual amount due. |
| **ProductA_* fields** | Annualised amounts for Product A (premium, tax, commission, admin). |
| **ProductB_* fields** | Annualised amounts for Product B (premium, tax, commission). |
| **ProductC_* fields** | Annualised amounts for Product C (premium, tax, commission, admin). |

---

## Example rows

A shortened sample:

RecordID,PolicyID,TransactionType,PolicyStartDate,PaymentFrequency,...
1001, POL-1001, New, 2024-01-01, monthly, ...
1002, POL-1001, Upgrade, 2024-04-15, monthly, ...
1003, POL-1001, Cancellation, 2024-09-10, monthly, ...


Here:
- The customer took a policy on **1 Jan**  
- Upgraded on **15 Apr**  
- Cancelled on **10 Sep**

---

## What you should customise for your own business

Replace/extend any of these fields based on your own system:

- Product names or number of products  
- Additional financial columns (fees, discounts, surcharges, IPT rules)  
- Payment frequencies  
- Effective date rules  
- Policy term lengths  

The engine will work with any dataset as long as you provide:
- a policy start date  
- an annualised amount  
- a payment frequency  
- separate event rows for upgrades/cancellations  

Continue to the next document to see how this raw data becomes a clean base table.
