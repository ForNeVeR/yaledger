{-# LANGUAGE ScopedTypeVariables, FlexibleContexts, OverlappingInstances, GADTs, RecordWildCards, TypeFamilies #-}

module YaLedger.Reports.Registry
  (Registry (..)) where

import YaLedger.Reports.API

data Registry = Registry

data ROptions =
    RLedgerBalances
  | RBothBalances
  | RCSV (Maybe String)
  deriving (Eq)

instance ReportClass Registry where
  type Options Registry = ROptions
  type Parameters Registry = Maybe Path

  reportHelp _ = "Show all entries in account or group of accounts."

  reportOptions _ =
    [Option "l" ["ledger"] (NoArg RLedgerBalances) "Show ledger balances instead of available balances",
     Option "b" ["both"] (NoArg RBothBalances) "Show both available and ledger balances",
     Option "C" ["csv"] (OptArg RCSV "SEPARATOR") "Output data in CSV format using given fields delimiter (semicolon by default)"]

  runReport _ qry options mbPath = 
      registry qry options mbPath
    `catchWithSrcLoc`
      (\l (e :: InternalError) -> handler l e)
    `catchWithSrcLoc`
      (\l (e :: InvalidPath) -> handler l e)
    `catchWithSrcLoc`
      (\l (e :: NoSuchRate) -> handler l e)

registry qry options mbPath = do
    fullCoA <- gets lsCoA
    coa <- case mbPath of
              Nothing   -> return fullCoA
              Just path -> getCoAItem (gets lsPosition) (gets lsCoA) path
    totals <- do
              res <- treeSaldo qry coa
              case res of
                Leaf {..}   -> return leafData
                Branch {..} -> return branchData
    case coa of
      Leaf {leafData = account} -> do
          balances <- readIOListL (accountBalances account)
          let balances' = filter (checkQuery qry) balances
          let bqry = if RBothBalances `elem` options
                        then BothBalances
                        else if RLedgerBalances `elem` options
                              then Only LedgerBalance
                              else Only AvailableBalance
          let format = case [s | RCSV s <- options] of
                         []    -> showEntriesBalances' bqry fullCoA ASCII totals
                         (x:_) -> showEntriesBalances' bqry fullCoA (CSV x) totals
          wrapIO $ putStrLn $ format (nub $ sort balances')
      Branch {} -> do
          let accounts = map snd $ leafs coa
          allEntries <- forM accounts getEntries
          let entries = concat $ map (filter $ checkQuery qry) allEntries
          let format = case [s | RCSV s <- options] of
                         []    -> showEntries' fullCoA ASCII totals
                         (x:_) -> showEntries' fullCoA (CSV x) totals
          wrapIO $ putStrLn $ format (nub $ sort entries)
  
