{-# LANGUAGE ScopedTypeVariables, FlexibleContexts, OverlappingInstances, GADTs, RecordWildCards, TypeFamilies #-}

module YaLedger.Reports.Turnovers where

import YaLedger.Reports.API

data Turnovers = Turnovers

data TOptions = TNoZeros | TShowTotals
  deriving (Eq)

instance ReportClass Turnovers where
  type Options Turnovers = TOptions
  type Parameters Turnovers = Maybe Path
  defaultOptions Turnovers = []
  reportHelp _ = "Show debit/credit, and, optionally, total turnovers for each account."
  reportOptions _ =
    [Option "z" ["no-zeros"] (NoArg TNoZeros) "Do not show accounts with zero balance",
     Option "t" ["show-totals"] (NoArg TShowTotals) "Show total turnovers" ]

  runReportL _ queries opts mbPath =
    turnoversL queries opts mbPath
      `catchWithSrcLoc`
        (\l (e :: InvalidPath) -> handler l e)
      `catchWithSrcLoc`
        (\l (e :: NoSuchRate) -> handler l e)

  runReport _ qry opts mbPath =
    turnoversL [qry] opts mbPath
      `catchWithSrcLoc`
        (\l (e :: InvalidPath) -> handler l e)
      `catchWithSrcLoc`
        (\l (e :: NoSuchRate) -> handler l e)

data TRecord v = TRecord {
  trCredit :: v,
  trDebit  :: v,
  trIncSaldo :: v,
  trOutSaldo :: v,
  trTotals   :: Maybe v }
  deriving (Eq, Show)

sumTurnovers mbDate calcTotals ag list = do
  let c = agCurrency ag
  list' <- forM list $ \tr -> do
                cr' :# _  <- convert mbDate c (trCredit tr)
                dt' :# _  <- convert mbDate c (trDebit tr)
                inc' :# _ <- convert mbDate c (trIncSaldo tr)
                out' :# _ <- convert mbDate c (trOutSaldo tr)
                t'  <- case trTotals tr of
                         Nothing -> return Nothing
                         Just t -> do
                                   x :# _ <- convert mbDate c t
                                   return (Just x)
                return $ TRecord {
                           trCredit = cr',
                           trDebit  = dt',
                           trIncSaldo = inc',
                           trOutSaldo = out',
                           trTotals = t' }
  let credits = sum $ map trCredit list'
      debits  = sum $ map trDebit  list'
      inc     = sum $ map trIncSaldo list'
      out     = sum $ map trOutSaldo list'
      totals  = if calcTotals
                  then Just $ (sum $ map (fromJust . trTotals) list') :# c
                  else Nothing
  return $ TRecord {
             trCredit = credits :# c,
             trDebit  = debits  :# c,
             trIncSaldo = inc :# c,
             trOutSaldo = out :# c,
             trTotals = totals }

allTurnovers calcTotals qry account = do
  cr :# c <- creditTurnovers qry account
  dt :# _ <- debitTurnovers  qry account
  incomingSaldo :# _ <-
      case qStart qry of
        Nothing -> return (0 :# c)
        Just date -> do
            let startQry = qry {
                   qStart = Nothing,
                   qEnd   = Just date }
            saldo startQry account
  let outgoingSaldo = cr - dt + incomingSaldo
  return $ TRecord {
             trCredit = cr :# c,
             trDebit  = dt :# c,
             trIncSaldo = incomingSaldo :# c,
             trOutSaldo = outgoingSaldo :# c,
             trTotals = if calcTotals
                          then Just $ (cr + dt) :# c
                          else Nothing }

noZeroTurns tr =
  case trTotals tr of
    Nothing -> isNotZero (trCredit tr) || isNotZero (trDebit tr)
    Just t  -> isNotZero t

turnoversL :: (Throws InvalidPath l,
               Throws NoSuchRate l,
               Throws InternalError l)
           => [Query] -> [TOptions] -> Maybe Path -> Ledger l ()
turnoversL queries options mbPath = do
    coa <- case mbPath of
              Nothing   -> gets lsCoA
              Just path -> getCoAItem (gets lsPosition) (gets lsCoA) path
    case coa of
      Leaf {..} -> byOneAccount queries options leafData
      _ -> forM_ queries $ \qry -> do
                wrapIO $ putStrLn $ showInterval qry
                turnovers qry options coa

byOneAccount queries options account = do
  let calcTotals = TShowTotals `elem` options
  turns <- forM queries $ \qry ->
               allTurnovers calcTotals qry account
  let check
        | TNoZeros `elem` options = noZeroTurns
        | otherwise               = const True
      xs = [(tr,qry) | (tr,qry) <- zip turns queries, check tr]
      turns'   = map fst xs
      queries' = map snd xs 
  let credits = map trCredit turns'
      debits  = map trDebit  turns'
      inc     = map trIncSaldo turns'
      out     = map trOutSaldo turns'
      totals  = map trTotals   turns'
      starts  = map qStart queries'
      ends    = map qEnd   queries'
  wrapIO $ putStrLn $ unlines $
    columns $
      [(["FROM"], ALeft, map showMaybeDate starts),
       (["TO"],   ALeft, map showMaybeDate ends),
       (["BALANCE C/F"], ARight, map show inc),
       (["CREDIT"],      ARight, map show credits),
       (["DEBIT"],       ARight, map show debits),
       (["BALANCE B/D"], ARight, map show out)] ++
      if calcTotals
        then [(["TOTALS"], ARight, map (show . fromJust) totals)]
        else []

turnovers qry options coa = do
  let calcTotals = TShowTotals `elem` options
  tree <- mapTreeM (sumTurnovers (qEnd qry) calcTotals) (allTurnovers calcTotals qry) coa
  let tree' = if TNoZeros `elem` options
                then filterLeafs noZeroTurns tree
                else tree
  let struct = showTreeStructure tree'
      nodes = allNodes tree'
      credits = map trCredit nodes
      debits  = map trDebit  nodes
      inc     = map trIncSaldo nodes
      out     = map trOutSaldo nodes
      totals  = map trTotals nodes
  wrapIO $ putStrLn $ unlines $
    columns $
      [(["ACCOUNT"],     ALeft, struct),
       (["BALANCE C/F"], ARight, map show inc),
       (["CREDIT"],      ARight, map show credits),
       (["DEBIT"],       ARight, map show debits),
       (["BALANCE B/D"], ARight,  map show out)] ++
      if calcTotals
        then [(["TOTALS"], ARight, map (show . fromJust) totals)]
        else []
                  
