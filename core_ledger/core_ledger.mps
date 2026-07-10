ZTMCSWEEP ; Trust & Custodial Cash-Sweep Engine — Core Ledger Layer (MUMPS)
 ; ---------------------------------------------------------------
 ; Globals (mock structure):
 ;   ^Portfolio(AccountNo)          = ClientName^FiduciaryType
 ;   ^Ledger(AccountNo)             = PrincipalCash^IncomeCash^PendingSettlementDrag
 ;   ^Inventory(AccountNo,CUSIP)    = SecurityDesc^FaceValue^CouponRate^MaturityDate
 ;   ^Rules(FiduciaryType)          = MaxPermissibleRate^ComplianceCode
 ; No SET commands are issued against ^Ledger, ^Inventory, or ^Portfolio.
 ; This routine is read-only / reporting, mirroring the T-SQL layer.
 ; ---------------------------------------------------------------
 QUIT
 ;
RUN ; Main entry point — runs both maturity roll and idle cash sections
 DO MATURITYROLL
 DO IDLECASHSWEEP
 QUIT
 ;
MATURITYROLL ; Section 1 & 2 — Maturity/roll loop with coupon/discount split
 NEW AccountNo,CusipId,SecurityDesc,FaceValue,CouponRate,MaturityDate
 NEW TodayDate,RollWindowEnd,DaysToMaturity
 NEW PrincipalCredit,IncomeCredit,ClientName,FiduciaryType
 ;
 SET TodayDate=$$TODAYHOROLOG^ZTMCSWEEP
 SET RollWindowEnd=TodayDate+7
 ;
 WRITE !,"=== MATURITY & ROLL EXECUTION LOG ===",!
 ;
 SET AccountNo=""
 FOR  SET AccountNo=$ORDER(^Inventory(AccountNo)) QUIT:AccountNo=""  DO
 . SET CusipId=""
 . FOR  SET CusipId=$ORDER(^Inventory(AccountNo,CusipId)) QUIT:CusipId=""  DO
 . . SET SecurityDesc=$PIECE(^Inventory(AccountNo,CusipId),"^",1)
 . . SET FaceValue=$PIECE(^Inventory(AccountNo,CusipId),"^",2)
 . . SET CouponRate=$PIECE(^Inventory(AccountNo,CusipId),"^",3)
 . . SET MaturityDate=$PIECE(^Inventory(AncoyntNo,CusipId),"^",4)
 . . ;
 . . ; Only Treasury instruments, only within the 7-day roll window
 . . IF SecurityDesc'["TREASURY" QUIT
 . . IF (MaturityDate<TodayDate)!(MaturityDate>RollWindowEnd) QUIT
 . . ;
 . . SET DaysToMaturity=MaturityDate-TodayDate
 . . ;
 . . ; Coupon/Discount split logic
 . . IF (SecurityDesc["NOTE")!(SecurityDesc["BOND") DO
 . . . SET IncomeCredit=FaceValue*(CouponRate/2)
 . . . SET PrincipalCredit=FaceValue
 . . ELSE  DO
 . . . SET IncomeCredit=0
 . . . SET PrincipalCredit=FaceValue
 . . ;
 . . ; Pull client/fiduciary context for the alert narrative
 . . SET ClientName=$PIECE(^Portfolio(AccountNo),"^",1)
 . . SET FiduciaryType=$PIECE(^Portfolio(AccountNo),"^",2)
 . . ;
 . . ; Filter out accounts with pending settlement drag
 . . IF $PIECE(^Ledger(AccountNo),"^",3)'=0 DO  QUIT
 . . . WRITE "Account ",AccountNo," (",ClientName,"): ROLL SUPPRESSED — pending settlement drag present.",!
 . . ;
 . . WRITE "Account ",AccountNo," (",ClientName,", ",FiduciaryType,"): ROLL_EXECUTION_RECOMMENDED",!
 . . WRITE "  CUSIP: ",CusipId," | Maturity: ",MaturityDate," | Days Out: ",DaysToMaturity,!
 . . WRITE "  Principal to credit: $",PrincipalCredit," | Final coupon to Income: $",IncomeCredit,!
 QUIT
 ;
IDLECASHSWEEP ; Section 3 & 4 — $DATA compliance safety net + Act/360 yield lift
 NEW AccountNo,ClientName,FiduciaryType
 NEW PrincipalCash,IncomeCash,PendingSettlementDrag
 NEW IdleCashFloor,LowYieldRate,DayCountBasis
 NEW RuleExists,MaxPermissibleRate,ComplianceCode
 NEW DailyYieldLift,ActionCode,ActionNarrative
 ;
 SET IdleCashFloor=5000
 SET LowYieldRate=0.0005
 SET DayCountBasis=360
 ;
 WRITE !,"=== IDLE CASH OPTIMIZATION — COMPLIANCE-AWARE SWEEP LOG ===",!
 ;
 SET AccountNo=""
 FOR  SET AccountNo=$ORDER(^Ledger(AccountNo)) QUIT:AccountNo=""  DO
 . SET PrincipalCash=$PIECE(^Ledger(AccountNo),"^",1)
 . SET IncomeCash=$PIECE(^Ledger(AccountNo),"^",2)
 . SET PendingSettlementDrag=$PIECE(^Ledger(AccountNo),"^",3)
 . ;
 . ; Only accounts above the idle-cash floor with no settlement block
 . IF PrincipalCash'>IdleCashFloor QUIT
 . IF PendingSettlementDrag'=0 QUIT
 . ;
 . SET ClientName=$PIECE(^Portfolio(AccountNo),"^",1)
 . SET FiduciaryType=$PIECE(^Portfolio(AccountNo),"^",2)
 . ;
 . ; --- $DATA compliance safety net (the LEFT JOIN equivalent) ---
 . SET RuleExists=$DATA(^Rules(FiduciaryType))
 . ;
 . IF RuleExists=0 DO  QUIT
 . . SET ActionCode="COMPLIANCE_HOLD"
 . . SET DailyYieldLift=""   ; explicit null, never zero — same principle as T-SQL NULL
 . . SET ActionNarrative="No sweep rule mapped for Fiduciary_Type '"_FiduciaryType_"' on account "_AccountNo_". Movement blocked pending Compliance/Trust review."
 . . WRITE "Account ",AccountNo," (",ClientName,"): ",ActionCode,!
 . . WRITE "  ",ActionNarrative,!
 . . WRITE "  Daily_Yield_Lift_Act360: [NULL]",!
 . ;
 . ; --- Rule exists: approved sweep path ---
 . SET MaxPermissibleRate=$PIECE(^Rules(FiduciaryType),"^",1)
 . SET ComplianceCode=$PIECE(^Rules(FiduciaryType),"^",2)
 . SET DailyYieldLift=(PrincipalCash*(MaxPermissibleRate-LowYieldRate))/DayCountBasis
 . SET ActionCode="SWEEP_RECOMMENDED"
 . SET ActionNarrative="Approved to sweep idle Principal_Cash for account "_AccountNo_" into vehicle yielding "_MaxPermissibleRate_" (Compliance Code: "_ComplianceCode_")."
 . ;
 . WRITE "Account ",AccountNo," (",ClientName,", ",FiduciaryType,"): ",ActionCode,!
 . WRITE "  ",ActionNarrative,!
 . WRITE "  Daily_Yield_Lift_Act360: $",$$ROUND^ZTMCSWEEP(DailyYieldLift,4),!
 QUIT
 ;
ROUND(NumericValue,DecimalPlaces) ; Utility — rounds to N decimal places
 NEW ScaleFactor,RoundedResult
 SET ScaleFactor=10**DecimalPlaces
 SET RoundedResult=(NumericValue*ScaleFactor+.5)\1/ScaleFactor
 QUIT RoundedResult
 ;
TODAYHOROLOG() ; Utility — returns today's date as $HOROLOG day count (integer)
 QUIT +$HOROLOG
