{-# LANGUAGE GADTs, FlexibleContexts #-}

module YaLedger.Reports.Common where

import Control.Applicative ((<$>))
import Control.Monad.Exception
import Control.Monad.Loc
import Data.Maybe
import Data.Decimal
import Data.Dates

import YaLedger.Types
import YaLedger.Output.Tables
import YaLedger.Output.ASCII
import YaLedger.Output.Pretty
import YaLedger.Monad
import YaLedger.Exceptions

isNotZero :: Amount -> Bool
isNotZero (x :# _) = x /= 0

datesBackFrom :: DateTime -> DateInterval -> [DateTime]
datesBackFrom date int = go date
  where
    go dt = dt: go (dt `minusInterval` int)

datesBetween :: DateTime -> DateTime -> DateInterval -> [DateTime]
datesBetween start end int =
  reverse $ takeWhile (>= start) $ datesBackFrom end int

intervalsBetween :: DateTime -> DateTime -> DateInterval -> [(DateTime, DateTime)]
intervalsBetween start end int =
  let dates = datesBetween start end int
      first = if head dates > start
                then [(start, head dates)]
                else []
  in  first ++ zip dates (tail dates)
      
splitQuery :: DateTime -> DateTime -> Query -> DateInterval -> [Query]
splitQuery first now qry int =
  let start = fromMaybe first (qStart qry)
      end   = fromMaybe now   (qEnd   qry)
      pairs = intervalsBetween start end int
      attrs = qAttributes qry
      adm   = qAllAdmin qry
  in  map (\(s, e) -> Query (Just s) (Just e) adm attrs) pairs

showE :: Ext (Entry Decimal Checked) -> [[String]]
showE (Ext {getDate = date, getContent = (CEntry dt cr rd)}) =
    [prettyPrint date: replicate (m-1) "",
     map posting cr, map posting dt, rdS]
  where
    m = max (length cr) (length dt)
    rdS
      | rd == OneCurrency = []
      | otherwise = [show rd]

showB :: Currency -> Ext (Balance Checked) -> [[String]]
showB currency (Ext {getDate = date, getContent = balance}) =
  let bd = balanceValue balance
      dt :: [Posting Decimal Debit]
      cr :: [Posting Decimal Credit]
      (dt, cr) = case causedBy balance of
                   Nothing -> ([], [])
                   Just (CEntry dt cr _) -> (dt, cr)
      m = max (length cr) (length dt)
      padding = replicate (m-1) ""
  in  [prettyPrint date: padding,
       map posting cr, map posting dt,
       padding ++ [show bd ++ show currency]]

posting :: Posting Decimal t -> String
posting (DPosting acc x) = getName acc ++ ": " ++ show (x :# getCurrency acc)
posting (CPosting acc x) = getName acc ++ ": " ++ show (x :# getCurrency acc)

showEntries :: (TableFormat a) => a -> Amount -> [Ext (Entry Decimal Checked)] -> String
showEntries fmt totals list =
  let l = map showE list
      footer = ["    TOTALS: " ++ show totals]
  in  unlines $
      tableGrid fmt [(ALeft,  ["DATE"]),
                     (ARight, ["CREDIT"]),
                     (ARight, ["DEBIT"]),
                     (ARight, ["RATES DIFF."])] l ++ footer

showEntriesBalances :: (TableFormat a) => a -> Amount -> [Ext (Balance Checked)] -> String
showEntriesBalances fmt totals list =
  let l = map (showB $ getCurrency totals) list
      footer = ["    TOTALS: " ++ show totals]
  in  unlines $
      tableGrid fmt [(ALeft,  ["DATE"]),
                     (ARight, ["CREDIT"]),
                     (ARight, ["DEBIT"]),
                     (ARight, ["BALANCE B/D"])] l ++ footer

causedByExt :: Ext (Balance Checked) -> Maybe (Ext (Entry Decimal Checked))
causedByExt (Ext date pos attrs p) =
  Ext date pos attrs <$> causedBy p

getEntries :: (Throws InternalError l,
               HasBalances a)
           => a
           -> Ledger l [Ext (Entry Decimal Checked)]
getEntries acc = do
  balances <- readIOList (accountBalances acc)
  return $ mapMaybe causedByExt balances

