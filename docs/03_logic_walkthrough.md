# Premium Schedule Engine – Logic Walkthrough

This document explains how the premium schedule engine works, step by step.

The goal is to start from a raw extract of policy events (New, Renewal, Upgrade, Cancellation, etc.) and end up with a **payment schedule** that tells you:

- For each **underwritten month**
- And each **payment month**
- How much premium / tax is due for each product.

---

## 1. Raw data – `sample_policies_raw.csv`

This file simulates what you might get from a policy admin system or database.

Each row is a **policy event**:

- `PolicyID` – policy reference (can appear multiple times)
- `TransactionType` – e.g. `New`, `Renewal`, `Upgrade`, `Cancellation`
- `PolicyStartDate` – when this policy term starts
- `CancellationDate` – if/when the policy is cancelled
- `DaysUsed`, `DaysPaid` – used to flag fully-paid rows
- `PaymentFrequency` – `monthly`, `quarterly`, or `annual`
- Annual amounts split by product:
  - `ProductA_Premium`, `ProductA_TaxAmount`, `ProductA_Commission`, `ProductA_AdminFee`
  - `ProductB_Premium`, `ProductB_TaxAmount`, `ProductB_Commission`
  - `ProductC_Premium`, `ProductC_TaxAmount`, `ProductC_Commission`, `ProductC_AdminFee`

A single `PolicyID` can have multiple events, for example:

- New → Upgrade → Cancellation  
- New → Renewal  
- New only (no further changes)

---

## 2. Step 01 – Clean base table (`01_raw_to_clean_base.m`)

**Input:** `RawPolicies` (from `sample_policies_raw.csv`)  
**Output:** `CleanPolicies` → saved as `data/clean/sample_policies_clean.csv`

### 2.1 Keep only relevant columns

We select only the columns needed by the engine. Anything like names, addresses, or other descriptive fields can be removed or kept separately.

### 2.2 Optional date filter

For demo purposes, we filter to:

```text
PolicyStartDate >= 2023-01-01

2.3 Fully paid rule

Business rule example:

If DaysPaid >= 365, treat the policy as fully paid and zero out all monetary columns so the engine doesn’t double-count them.

Columns affected:

AnnualTotalCharge

All product premiums, tax, commissions, admin fees

You can change this rule to use your own logic (e.g. term length, paid flags, etc.).

2.4 EventEffectiveDate

We create one effective date per event row:
If CancellationDate is null or < PolicyStartDate:
    EventEffectiveDate = PolicyStartDate
Else:
    EventEffectiveDate = CancellationDate

This gives the engine a single “when does this event take effect” date, whether it’s a new policy, a renewal, or a cancellation.

If your system has separate effective dates for upgrades vs cancellations, you can adjust this to use the correct field.

2.5 PolicyEndDate

We model a generic 12-month policy:

PolicyEndDate = EndOfMonth(PolicyStartDate + 11 months)


If you have 6-month / 24-month terms etc., this is where you plug that in.

2.6 Result of Step 01

After Step 01, CleanPolicies has:

One row per policy event

All annual monetary values

A standardised:

EventEffectiveDate

PolicyEndDate

Fully paid events zeroed out

This is saved as:

data/clean/sample_policies_clean.csv

3. Step 02 – Payment schedule (02_generate_payment_schedule.m)

Input: CleanPolicies
Output: PaymentSchedule → saved as data/engine/sample_payment_schedule.csv

The goal here is to explode each event row into one row per scheduled payment date.

3.1 IntervalMonths (frequency as a number)

We convert the text frequency to “months per step”:

monthly → IntervalMonths = 1

quarterly → IntervalMonths = 3

annual → IntervalMonths = 12

anything unknown falls back to 1

This drives how far apart the payment dates are.

3.2 AlignedStart (for upgrades)

For most events, we just use EventEffectiveDate.

For Upgrade events, we often want the extra premium to follow the existing payment cycle, not start on some random day.

Logic:

Build the original schedule from PolicyStartDate to PolicyEndDate using IntervalMonths.

If the month of the upgrade is aligned with the cycle, we keep EventEffectiveDate as is.

Otherwise, we align the upgrade to the next scheduled payment date in the cycle.

Result:

AlignedStart holds the upgrade-aligned date for upgrades.

Non-upgrade events just reuse EventEffectiveDate.

3.3 PayStart

We set the actual start date for payment generation per event:

For Upgrade rows → PayStart = AlignedStart

For all other rows → PayStart = EventEffectiveDate

This is where the schedule begins for that event.

3.4 Generate PayDates and explode

For each event row, we generate a list:

PayStart,
PayStart + IntervalMonths,
PayStart + 2 * IntervalMonths,
...
up to PolicyEndDate


Then:

We expand the list so each payment date becomes its own row.

The table now has one row per event × payment date.

We also create:

PaymentMonthNum = YYYYMM of the PayDate

UnderwrittenMonthNum = YYYYMM of the PolicyStartDate

These are useful for building the cohort-style matrix in Power BI (underwritten month vs payment month).

3.5 CancellationEffectiveDate per policy

From the base table (CleanPolicies) we extract:

PolicyID

EventEffectiveDate for rows where TransactionType = "Cancellation"

We rename that to CancellationEffectiveDate and join it back to the schedule table by PolicyID.

Now each schedule row knows if and when the policy was cancelled.

3.6 CancellationStatus

For each scheduled payment row we classify the status:

No Cancellation – the policy was never cancelled

In Cancellation Month – PayDate is in the same month as CancellationEffectiveDate

After Cancellation – PayDate is after CancellationEffectiveDate

Before Cancellation – PayDate is before CancellationEffectiveDate

Renewal Cancellation – special case when cancellation happens at/after the renewal month

This flag is very helpful later when building the logic to:

stop normal instalments after cancellation, and

push the remaining amounts into a single “cancellation month” lump if required.

3.7 InstalmentCount

Per event, we estimate the number of scheduled instalments:

If TransactionType = "Cancellation" → InstalmentCount = 1

Else:

monthly → 12

quarterly → 4

annual → 1

This can be adapted if your policies don’t always run for 12 months.

3.8 Base instalments (Products A, B, C)

For non-Upgrade rows:

Base_Installment_Premium_X = ProductX_Premium   / InstalmentCount
Base_Installment_Tax_X     = ProductX_TaxAmount / InstalmentCount


for each product X ∈ {A,B,C}.

These represent the baseline schedule, before applying upgrades and cancellations.

3.9 UpgradeInstalmentCount

For Upgrade rows, we calculate how many remaining aligned instalments exist between the upgrade effective date and policy end.

Roughly:

Align the upgrade month to the payment cycle.

Count how many payment periods from that aligned month to PolicyEndDate.

Force at least 1 instalment.

For annual cases, treat as a single instalment.

This result is stored in UpgradeInstalmentCount.

3.10 Upgrade instalments (Products A, B, C)

For Upgrade rows:

Upgrade_Installment_Premium_X = ProductX_Premium   / UpgradeInstalmentCount
Upgrade_Installment_Tax_X     = ProductX_TaxAmount / UpgradeInstalmentCount


for X ∈ {A,B,C}.

Non-upgrade rows have these fields as null.

4. Final engine output

The final schedule table (saved as data/engine/sample_payment_schedule.csv) contains, for each PolicyID × Event × PayDate:

Original event context:

PolicyID, TransactionType, PolicyStartDate, EventEffectiveDate, PolicyEndDate

PaymentFrequency, IntervalMonths

Time keys:

PayDate, PaymentMonthNum, UnderwrittenMonthNum

Cancellation info:

CancellationEffectiveDate, CancellationStatus

Base instalments:

Base_Installment_Premium_A/B/C

Base_Installment_Tax_A/B/C

Upgrade instalments:

Upgrade_Installment_Premium_A/B/C

Upgrade_Installment_Tax_A/B/C

From here, your DAX model (or SQL / Python) can:

Aggregate by underwritten month vs payment month

Separate base vs upgrade effects

Apply cancellation rules (e.g. zero out normal instalments after cancellation and use the cancellation-month lump sum instead)

This mirrors the real project logic but uses anonymised column names and fake data, so you can safely adapt it to your own environment.
