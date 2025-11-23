# Cancellation Logic – Premium Schedule Engine

The DAX pattern for `productX_*_total` measures uses three building blocks:

1. **RegularPayments**  
   - Uses the *active* relationship (underwritten → payment month).  
   - Includes rows where `CancellationStatus` is:
     - `No Cancellation`
     - `Before Cancellation`

2. **RemainingPremium / RemainingTax / etc.**  
   - Uses `USERELATIONSHIP` to activate the **cancellation month → payment date** mapping.  
   - Includes rows where `CancellationStatus` is:
     - `In Cancellation Month`
     - `After Cancellation`  
   - Excludes rows where `EventType = "Cancelled"` (we handle those separately).

3. **CancelledRowPremium / Tax / etc.**  
   - Also uses `USERELATIONSHIP`.  
   - Filters only `EventType = "Cancelled"` and:
     - `In Cancellation Month`
     - `Renewal Cancellation`

The final result is:

```DAX
RegularPayments + (RemainingPremium + CancelledRowPremium)

Business meaning:

Normal instalments run until the cancellation effective month.

All remaining future instalments (after cancellation) are brought forward into a single lump sum in the cancellation month.

The cancellation row itself (often a negative) is included in that lump.

This gives you a clean, auditable representation of what should be paid or refunded in each month, per product.