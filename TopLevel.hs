
module TopLevel where

import Text.ParserCombinators.Parsec (runParser)
import qualified Data.Map as M
import Data.Maybe (isJust)

import Types
import Dates
import Parser
import Currencies
import Accounts
import Transactions
import qualified Tree as T

-- import Debug.Trace

trace :: String -> a -> a
trace x y = y

tryParse parser st src str = 
  case runParser parser st src str of
    Right x -> x
    Left e -> error $ "Cannot parse:\n" ++ show e ++ "\n [ERROR]\n"

readLedger :: DateTime -> FilePath -> IO (AccountsTree, [Dated Record])
readLedger dt path = do
  str <- readFile path
  let y = year dt
      (accs, recs) = tryParse ledgerSource (emptyPState dt) path str
  return (accs, recs)

runQuery :: DateTime -> Conditions -> AccountsTree -> [Dated Record] -> LedgerState 
runQuery dt pred accs recs = 
  let st = LS dt accs undefined [] M.empty M.empty [] []
  in  case runState (doRecords (trace ("C: "++show pred) pred) recs) st of
        Right ((), y) -> y
        Left e        -> error $ show e

balance :: LedgerState -> T.Tree Amount Amount
balance st = calcBalances (rates st) (accounts st)

printBalance :: LedgerState -> IO ()
printBalance st =
  putStrLn $ T.showTree 0 (balance st)

printRegister :: LedgerState -> String -> IO ()
printRegister st path = do
    putStr "Date "
    putStrLn $ unwords $ accs
    putStrLn $ unlines $ map showRec $ filter nonEmpty $ map (\r -> (getDate r, amountsList' r accs)) (records st)
  where
    tree = balance st
    accs = T.lookupNode path tree

    showRec :: (DateTime, [Maybe Amount]) -> String
    showRec (dt, lst) = showDate dt ++ " " ++ (unwords $ map showMaybe lst)

    showMaybe :: Maybe Amount -> String
    showMaybe (Just x) = show $ getValue x
    showMaybe Nothing = "NA"

    nonEmpty :: (DateTime, [Maybe Amount]) -> Bool
    nonEmpty (_,lst) = any isJust lst

accountFromTree :: AccountsTree -> String -> Account
accountFromTree accs path = 
  case T.lookupPath path accs of
    []    -> error $ "Unknown account: " ++ path
    [acc] -> acc
    _     -> error $ "Ambigous account spec: " ++ path

getSaldo :: LedgerState -> DateTime -> String -> String -> String -> Double
getSaldo st now path startS endS =
  let start = tryParse pDateOnly (emptyPState now) "<start date>" startS
      end   = tryParse pDateOnly (emptyPState now) "<end date>" endS
      acc   = accountFromTree (accounts st) path
  in  saldo acc start end

