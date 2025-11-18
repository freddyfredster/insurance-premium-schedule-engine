vet_payment_total = 

VAR RegularPayments = 
SUMX(
    FILTER(
        Fact_Vet_bdx,
        Fact_Vet_bdx[CancellationStatus] = "Before Cancellation" ||
        Fact_Vet_bdx[CancellationStatus] = "No Cancellation"
    ),
    Fact_Vet_bdx[Base_Installment_Premium]
)

VAR RemainingPremium = 
CALCULATE(
    SUMX(
        FILTER(
            Fact_Vet_bdx,
            (
                Fact_Vet_bdx[CancellationStatus] = "After Cancellation" ||
                Fact_Vet_bdx[CancellationStatus] = "In Cancellation Month"
            ) &&
                Fact_Vet_bdx[type] <> "Cancelled"

        ),
        Fact_Vet_bdx[Base_Installment_Premium]
    ),
    USERELATIONSHIP(
        Fact_Vet_bdx[CancellationEffectiveDate_YearMonthNum], 'dim_BDXDate'[MonthYearNum]
    )
)

VAR CancelledRowPremium = 
CALCULATE(
    SUMX(
        FILTER(
            Fact_Vet_bdx,
            Fact_Vet_bdx[type] = "Cancelled" &&
            (
            Fact_Vet_bdx[CancellationStatus] = "In Cancellation Month" ||
            Fact_Vet_bdx[CancellationStatus] = "Renewal Cancellation"
            )
        ),
        Fact_Vet_bdx[Base_Installment_Premium]
    ),
    USERELATIONSHIP(
        Fact_Vet_bdx[CancellationEffectiveDate_YearMonthNum], 'dim_BDXDate'[MonthYearNum]
    )
)

VAR LumpSum = CancelledRowPremium + RemainingPremium

RETURN 
    RegularPayments + LumpSum