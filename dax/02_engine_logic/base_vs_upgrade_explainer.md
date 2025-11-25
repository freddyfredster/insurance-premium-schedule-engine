# Base vs Upgrade Logic – How the Engine Treats Each

The premium schedule engine works with **two layers** of amounts for each product:

1. **Base instalments** – amounts coming from the original policy or renewal  
2. **Upgrade instalments** – additional amounts coming from mid-term changes

Both are kept separate in the fact table so you can see exactly what came from the original contract vs changes made later.

---

## 1. Base instalments

Base instalments come from rows where the event type is something like:

- `New`
- `Renewal`

For each of these rows, the engine computes:

- the number of instalments based on the payment frequency:
  - monthly   → 12
  - quarterly → 4
  - annual    → 1
- the **base instalment amount** for each component (per product):

Examples (Product A):

- `Base_Installment_ProductA`
- `Base_Installment_Tax_ProductA`
- `Base_Installment_Commission_ProductA`
- `Base_Installment_Admin_Generic` (shared admin in the sample)

Conceptually:

> Annual amount ÷ InstalmentCount = amount per scheduled payment.

These base amounts are then **spread across the full policy term** according to the payment interval.

---

## 2. Upgrade instalments

Upgrade instalments come from rows where the event type is:

- `Upgrade`

An upgrade row represents a **change in cover mid-term** – for example, a customer increasing their level of protection partway through the year.

The engine handles upgrades in three steps:

1. **Find when the upgrade takes effect**  
   - Uses the `Effective_Date` (or `AlignedStart` if you align upgrades to the original payment pattern).

2. **Work out how many payments remain**  
   - From the upgrade effective date to the policy end date.  
   - Aligned to the same payment frequency as the policy (monthly / quarterly / annual).

3. **Spread the upgrade amounts evenly over those remaining payments**  
   - For each component, the engine creates:
     - `Upgrade_Installment_ProductA`
     - `Upgrade_Installment_Tax_ProductA`
     - `Upgrade_Installment_Commission_ProductA`
     - `Upgrade_Installment_Admin_Generic` (if admin is affected)

Conceptually:

> Upgrade amount ÷ RemainingInstalmentCount = extra amount per remaining payment.

The key idea:

> Upgrades are **layered on top** of the existing schedule – they don’t rewrite history.

---

## 3. How base & upgrade interact in the fact table

Once the schedule is exploded, each row in the `PaymentSchedule` table can contain:

- a **base instalment** for each component  
- an **upgrade instalment** for each component (if there was an upgrade affecting that period)

For Product A net premium, for example, one row may have:

- `Base_Installment_ProductA`  
- `Upgrade_Installment_ProductA`  

The measures always **add these together**:

```DAX
Base_Installment_ProductA +
Upgrade_Installment_ProductA

so you get the full amount due in that payment period.

4. Cancellation and upgrades

When a policy is cancelled mid-term:

Any remaining base instalments after the cancellation month are summed up.

Any remaining upgrade instalments after the cancellation month are also summed up.

The DAX measures then bring these amounts into the cancellation month as a lump sum.

In the DAX pattern:

Regular... variables handle months before cancellation.

Remaining... variables handle amounts after cancellation that should be pulled forward.

CancelledRow... variables pick up the cancellation row itself (often a negative adjustment).

The final measure returns:

RegularComponent + (RemainingComponent + CancelledRowComponent)


This is applied equally to:

Base instalments

Upgrade instalments

And each component (Net Prem, Tax, Commission, Admin)

So upgrades are treated consistently with the original cover when a cancellation occurs.

5. Adapting the pattern

To adapt this to your own scenario:

Ensure your fact table has separate columns for:

Base instalments per component

Upgrade instalments per component

Use the generic pattern in final_measure_template.dax:

Point {{Base_Installment_Component}} to your base column

Point {{Upgrade_Installment_Component}} to your upgrade column

Keep the cancellation logic unchanged unless your business rules differ.

The result is a transparent, auditable split between:

what was agreed at the start, and

what was added mid-term, with both behaving correctly under cancellation.