pa_payment_total = 

VAR RegularPayments = 
SUMX(
    FILTER(
        Fact_Memberships_bdx,
        Fact_Memberships_bdx[CancellationStatus] = "Before Cancellation" ||
        Fact_Memberships_bdx[CancellationStatus] = "No Cancellation"
    ),
    Fact_Memberships_bdx[Base_Installment_Premium_PA] + Fact_Memberships_bdx[Upgrade_Installment_Premium_PA]
)

VAR RemainingPremium = 
CALCULATE(
    SUMX(
        FILTER(
            Fact_Memberships_bdx,
            (
                Fact_Memberships_bdx[CancellationStatus] = "After Cancellation" ||
                Fact_Memberships_bdx[CancellationStatus] = "In Cancellation Month"
            ) &&
                Fact_Memberships_bdx[type] <> "Cancelled"

        ),
        Fact_Memberships_bdx[Base_Installment_Premium_PA] + Fact_Memberships_bdx[Upgrade_Installment_Premium_PA]
    ),
    USERELATIONSHIP(
        Fact_Memberships_bdx[CancellationEffectiveDate_YearMonthNum], 'dim_BDXDate'[MonthYearNum]
    )
)

VAR CancelledRowPremium = 
CALCULATE(
    SUMX(
        FILTER(
            Fact_Memberships_bdx,
            Fact_Memberships_bdx[type] = "Cancelled" &&
            (
            Fact_Memberships_bdx[CancellationStatus] = "In Cancellation Month" ||
            Fact_Memberships_bdx[CancellationStatus] = "No Cancellation"
            )
        ),
        Fact_Memberships_bdx[Base_Installment_Premium_PA] + Fact_Memberships_bdx[Upgrade_Installment_Premium_PA]
    ),
    USERELATIONSHIP(
        Fact_Memberships_bdx[CancellationEffectiveDate_YearMonthNum], 'dim_BDXDate'[MonthYearNum]
    )
)

VAR LumpSum = CancelledRowPremium + RemainingPremium

RETURN 
    RegularPayments + LumpSum