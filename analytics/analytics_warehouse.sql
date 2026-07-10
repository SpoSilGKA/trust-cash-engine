SQL
/* =========================================================================
   TRUST & CUSTODIAL FIXED-INCOME MANAGEMENT — CASH SWEEP ENGINE (v3)
   Adds: table-driven fiduciary rate rules + compliance-hold exception logic.
   Scope: Read-only analytical script against mock schema. No DML against
   ledger tables. DDL/seed data below is for the mock rule table only.
   ========================================================================= */

-- ---------------------------------------------------------------
-- 1. NEW LOOKUP TABLE: Fiduciary_Sweep_Rules
-- ---------------------------------------------------------------
CREATE TABLE Fiduciary_Sweep_Rules (
    Fiduciary_Type       VARCHAR(20) PRIMARY KEY,
    Max_Permissible_Rate DECIMAL(6,4) NOT NULL,   -- legal ceiling for sweep vehicle
    Compliance_Code      VARCHAR(20)  NOT NULL    -- e.g., APPROVED, RESTRICTED
);

-- Mock seed data — in production this would be maintained by
-- Trust/Compliance, not by the analytics team.
INSERT INTO Fiduciary_Sweep_Rules (Fiduciary_Type, Max_Permissible_Rate, Compliance_Code)
VALUES
    ('Revocable',   0.0450, 'APPROVED'),
    ('Irrevocable', 0.0400, 'RESTRICTED'),
    ('Custodial',   0.0425, 'APPROVED');

-- Suggested indexes on core tables (DDL only)
-- CREATE INDEX IX_FixedRateInventory_Maturity ON Fixed_Rate_Inventory (Maturity_Date) INCLUDE (Account_No, Face_Value, Coupon_Rate, Security_Desc);
-- CREATE INDEX IX_CashLedger_PrincipalCash ON Trust_Cash_Ledger (Principal_Cash) INCLUDE (Account_No, Income_Cash, Pending_Settlement_Drag);
-- CREATE INDEX IX_Portfolios_FiduciaryType ON Trust_Portfolios (Fiduciary_Type);

DECLARE @AsOfDate        DATE           = CAST(GETDATE() AS DATE);
DECLARE @RollWindowDays  INT            = 7;
DECLARE @IdleCashFloor   DECIMAL(18,2)  = 5000.00;
DECLARE @LowYieldRate    DECIMAL(6,4)   = 0.0005;   -- 0.05% checking sweep
DECLARE @DayCountBasis   INT            = 360;      -- money market Act/360 convention

/* =========================================================================
   1. MATURITY & ROLL LOGIC — Coupon/Discount split
   ========================================================================= */
;WITH MaturingPositions AS (
    SELECT
        fri.Position_ID,
        fri.Account_No,
        fri.CUSIP,
        fri.Security_Desc,
        fri.Face_Value,
        fri.Coupon_Rate,
        fri.Maturity_Date,
        DATEDIFF(DAY, @AsOfDate, fri.Maturity_Date) AS Days_To_Maturity,
        CASE
            WHEN fri.Security_Desc LIKE 'US TREASURY NOTE%'
              OR fri.Security_Desc LIKE 'US TREASURY BOND%'
                THEN ROUND(fri.Face_Value * (fri.Coupon_Rate / 2.0), 2)
            ELSE 0.00
        END AS Final_Coupon_To_Income,
        fri.Face_Value AS Principal_To_Principal
    FROM Fixed_Rate_Inventory AS fri
    WHERE fri.Security_Desc LIKE 'US TREASURY%'
      AND fri.Maturity_Date BETWEEN @AsOfDate AND DATEADD(DAY, @RollWindowDays, @AsOfDate)
)
SELECT
    mp.Account_No,
    tp.Client_Name,
    tp.Fiduciary_Type,
    COUNT(*)                              AS Maturing_Position_Count,
    SUM(mp.Principal_To_Principal)        AS Total_Principal_Crediting,
    SUM(mp.Final_Coupon_To_Income)        AS Total_Income_Crediting,
    MIN(mp.Maturity_Date)                 AS Earliest_Maturity,
    MAX(mp.Maturity_Date)                 AS Latest_Maturity
INTO #MaturitySummary
FROM MaturingPositions AS mp
INNER JOIN Trust_Portfolios AS tp
    ON tp.Account_No = mp.Account_No
GROUP BY mp.Account_No, tp.Client_Name, tp.Fiduciary_Type;

SELECT * FROM #MaturitySummary ORDER BY Total_Principal_Crediting DESC;


/* =========================================================================
   2. REINVESTMENT ALERTS ("Roll Execution" action log)
   ========================================================================= */
SELECT
    ms.Account_No,
    ms.Client_Name,
    ms.Fiduciary_Type,
    ms.Total_Principal_Crediting,
    ms.Total_Income_Crediting,
    tcl.Pending_Settlement_Drag,
    'ROLL_EXECUTION_RECOMMENDED'      AS Action_Code,
    CONCAT(
        'Recommend rolling $',
        FORMAT(ms.Total_Principal_Crediting, 'N2'),
        ' principal (+ $', FORMAT(ms.Total_Income_Crediting, 'N2'), ' final coupon to income) ',
        'from maturing Treasury position(s) into next available auction cycle for account ',
        ms.Account_No
    )                                  AS Action_Narrative,
    @AsOfDate                          AS Alert_Generated_On
FROM #MaturitySummary AS ms
INNER JOIN Trust_Cash_Ledger AS tcl
    ON tcl.Account_No = ms.Account_No
WHERE ISNULL(tcl.Pending_Settlement_Drag, 0) = 0
ORDER BY ms.Total_Principal_Crediting DESC;


/* =========================================================================
   3. IDLE CASH OPTIMIZATION — Table-driven fiduciary rules + compliance hold
   ========================================================================= */
SELECT
    tp.Account_No,
    tp.Client_Name,
    tp.Fiduciary_Type,
    tcl.Principal_Cash,
    tcl.Pending_Settlement_Drag,
    @LowYieldRate                          AS Current_Rate,
    fsr.Max_Permissible_Rate               AS Applied_Target_Rate,
    fsr.Compliance_Code,

    CASE
        WHEN fsr.Fiduciary_Type IS NULL THEN 'COMPLIANCE_HOLD'
        ELSE 'SWEEP_RECOMMENDED'
    END                                      AS Action_Code,

    CASE
        WHEN fsr.Fiduciary_Type IS NULL
            THEN CONCAT(
                'No sweep rule mapped for Fiduciary_Type = ''', tp.Fiduciary_Type,
                ''' on account ', tp.Account_No,
                '. Movement blocked pending Compliance/Trust review.'
            )
        ELSE CONCAT(
            'Approved to sweep idle Principal_Cash for account ', tp.Account_No,
            ' into vehicle yielding ', FORMAT(fsr.Max_Permissible_Rate, 'P2'),
            ' (Compliance Code: ', fsr.Compliance_Code, ').'
        )
    END                                      AS Action_Narrative,

    CASE
        WHEN fsr.Fiduciary_Type IS NULL THEN NULL
        ELSE ROUND(tcl.Principal_Cash * (fsr.Max_Permissible_Rate - @LowYieldRate) / @DayCountBasis, 4)
    END                                      AS Daily_Yield_Lift_Act360,

    CASE
        WHEN fsr.Fiduciary_Type IS NULL THEN NULL
        ELSE ROUND(tcl.Principal_Cash * (fsr.Max_Permissible_Rate - @LowYieldRate), 2)
    END                                      AS Annualized_Yield_Lift_Reference

FROM Trust_Cash_Ledger AS tcl
INNER JOIN Trust_Portfolios AS tp
    ON tp.Account_No = tcl.Account_No
LEFT JOIN Fiduciary_Sweep_Rules AS fsr
    ON fsr.Fiduciary_Type = tp.Fiduciary_Type
WHERE tcl.Principal_Cash > @IdleCashFloor
ORDER BY
    CASE WHEN fsr.Fiduciary_Type IS NULL THEN 0 ELSE 1 END,  -- surface holds first
    Daily_Yield_Lift_Act360 DESC;

-- Cleanup staged temp object
DROP TABLE IF EXISTS #MaturitySummary;
