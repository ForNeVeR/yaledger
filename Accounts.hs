{-# LANGUAGE TypeOperators, TypeSynonymInstances, PatternGuards, DeriveDataTypeable, FlexibleInstances, MultiParamTypeClasses #-}

module Accounts where

import Control.Monad.State.Class
import Data.List.Utils (split)

import Types
import Dates
import Lists
import qualified Tree as T
import Currencies

sumAccountsTree :: Rates -> AccountsTree -> T.Tree Amount Account
sumAccountsTree rs tree = T.partFold foldA plus foldS tree
  where
    foldA :: Currency -> [Account] -> Amount
    foldA c accs = convertAmount rs c $ sumAmounts rs $ map sumAccount accs

    plus :: Amount -> Amount -> Amount
    plus a1 a2 = amountPlus rs a1 a2

    foldS :: [Amount] -> Amount
    foldS = sumAmounts rs

sumAccountsTree' :: Rates -> DateTime -> DateTime -> AccountsTree -> T.Tree Amount Account
sumAccountsTree' rs start end tree = T.partFold foldA plus foldS tree
  where
    foldA :: Currency -> [Account] -> Amount
    foldA c accs = convertAmount rs c $ sumAmounts rs $ map (sumAccount' start end) accs

    plus :: Amount -> Amount -> Amount
    plus a1 a2 = amountPlus rs a1 a2

    foldS :: [Amount] -> Amount
    foldS = sumAmounts rs

saldo :: Account -> DateTime -> DateTime -> Double
saldo acc start end = sum $ map snd $ filter pred $ history acc
  where
    pred (dt, _) = (dt >= start) && (dt <= end)

calcBalances :: Rates -> AccountsTree -> T.Tree Amount ABalance
calcBalances rs tree = convert (sumAccountsTree rs tree)
  where
    convert (T.Node name a children) = T.Node name a (map convert children)
    convert (T.Leaf name acc) = T.Leaf name (pair acc)

    pair acc = let s = sumAccount acc
               in  ABalance s (amountPlus rs s (negateAmount $ hold acc))

accountFromTree :: (Monad m) => AccountsTree -> String -> m Account
accountFromTree accs path = 
  case T.lookupPath path accs of
    []    -> fail $ "Unknown account: " ++ path
    [acc] -> return acc
    _     -> fail $ "Ambigous account spec: " ++ path

groupFromTree :: (Monad m) => AccountsTree -> String -> m [AccountsTree]
groupFromTree accs path = 
  case T.lookupNode path accs of
    []  -> fail $ "Unknown accounts group: " ++ path
    lst -> return lst

getAccount :: String -> LState Account
getAccount name = do
  accs <- gets accounts
  accountFromTree accs name

getIncFrom :: String -> LState String
getIncFrom name = do
  acc <- getAccount name
  case incFrom acc of
    NoLink -> fail $ "income account for " ++ name ++ " is not set"
    LinkTo acc' -> return $ accName acc'
    ByName name -> return name

getDecTo :: String -> LState String
getDecTo name = do
  acc <- getAccount name
  case decTo acc of
    NoLink -> fail $ "outcome account for " ++ name ++ " is not set"
    LinkTo acc' -> return $ accName acc'
    ByName name -> return name

