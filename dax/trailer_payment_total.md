trailer_payment_total = 

VAR RegularPayments = 
SUMX(
    FILTER(
        Fact_Trailer_bdx,
        Fact_Trailer_bdx[CancellationStatus] = "Before Cancellation" ||
        Fact_Trailer_bdx[CancellationStatus] = "No Cancellation" 
    ),
    Fact_Trailer_bdx[Base_Installment_Premium] + Fact_Trailer_bdx[Upgrade_Installment_Premium]
)

VAR RemainingPremium = 
CALCULATE(
    SUMX(
        FILTER(
            Fact_Trailer_bdx,
            (
                Fact_Trailer_bdx[CancellationStatus] = "After Cancellation" ||
                Fact_Trailer_bdx[CancellationStatus] = "In Cancellation Month"
            ) &&
                Fact_Trailer_bdx[type] <> "Cancelled"

        ),
        Fact_Trailer_bdx[Base_Installment_Premium] + Fact_Trailer_bdx[Upgrade_Installment_Premium]
    ),
    USERELATIONSHIP(
        Fact_Trailer_bdx[CancellationEffectiveDate_YearMonthNum], 'dim_BDXDate'[MonthYearNum]
    )
)

VAR CancelledRowPremium = 
CALCULATE(
    SUMX(
        FILTER(
            Fact_Trailer_bdx,
            Fact_Trailer_bdx[type] = "Cancelled" &&
            (
            Fact_Trailer_bdx[CancellationStatus] = "In Cancellation Month" ||
            Fact_Trailer_bdx[CancellationStatus] = "Renewal Cancellation"
            )
        ),
        Fact_Trailer_bdx[Base_Installment_Premium] + Fact_Trailer_bdx[Upgrade_Installment_Premium]
    ),
    USERELATIONSHIP(
        Fact_Trailer_bdx[CancellationEffectiveDate_YearMonthNum], 'dim_BDXDate'[MonthYearNum]
    )
)

VAR LumpSum = CancelledRowPremium + RemainingPremium

RETURN 
    RegularPayments + LumpSum