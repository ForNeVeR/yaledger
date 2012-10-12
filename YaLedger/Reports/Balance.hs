{-# LANGUAGE ScopedTypeVariables, FlexibleContexts, OverlappingInstances, TypeFamilies #-}

module YaLedger.Reports.Balance where

import YaLedger.Reports.API

data Balances = Balances

data BOptions = BNoZeros
  deriving (Eq)

instance ReportClass Balances where
  type Options Balances = BOptions
  type Parameters Balances = Maybe Path
  reportOptions _ = 
    [Option "z" ["no-zeros"] (NoArg BNoZeros) "Do not show accounts with zero balance"]
  defaultOptions _ = []
  reportHelp _ = "Show accounts balances. One optional parameter: account or accounts group."

  runReport _ qry opts mbPath = balance [qry] opts mbPath
  runReportL _ queries opts mbPath = balance queries opts mbPath

showTreeList n qrys tree =
  let struct = showTreeStructure tree
      cols = [map (\l -> show (l !! i)) (allNodes tree) | i <- [0..n-1]]
  in  unlines $ columns $ (["","ACCOUNT",""], ALeft, struct):
                          [(showI qry, ARight, col) | (col,qry) <- zip cols qrys]

showI :: Query -> [String]
showI qry = [showD "beginning" (qStart qry), "...", showD "now" (qEnd qry)]
  where
    showD s Nothing = s
    showD _ (Just date) = showDate date

balance queries options mbPath = (do
    coa <- case mbPath of
              Nothing   -> gets lsCoA
              Just path -> getCoAItem (gets lsPosition) (gets lsCoA) path
    results <- treeSaldos queries coa
    let results' = if BNoZeros `elem` options
                     then filterLeafs (any isNotZero) results
                     else results
    wrapIO $ putStrLn $ showTreeList (length queries) queries results')
  `catchWithSrcLoc`
    (\l (e :: InvalidPath) -> handler l e)
  `catchWithSrcLoc`
    (\l (e :: NoSuchRate) -> handler l e)

