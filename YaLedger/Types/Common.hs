{-# LANGUAGE EmptyDataDecls, GADTs, FlexibleContexts, FlexibleInstances, UndecidableInstances, TypeSynonymInstances, DeriveDataTypeable, RecordWildCards, ScopedTypeVariables, MultiParamTypeClasses #-}

module YaLedger.Types.Common
  (Checked, Unchecked,
   Credit, Debit, Free,
   IOList,
   Currency, Rates,
   AccountID, GroupID,
   FreeOr,
   Ext (..),
   HasAmount (..), Named (..),
   HasCurrency (..), HasID (..),
   Amount (..), Param (..),
   AccountGroupType (..),
   AccountGroupData (..),
   SourcePos,
   sourceLine, sourceColumn, sourceName,
   newPos
  ) where

import Data.Decimal
import Data.IORef
import qualified Data.Map as M
import Data.Dates
import Text.Printf
import Text.Parsec.Pos

import YaLedger.Tree
import YaLedger.Attributes

data Checked
data Unchecked

data Credit
data Debit
data Free

type IOList a = IORef [a]

type Currency = String

type Rates = M.Map (Currency, Currency) Double

type AccountID = Integer

type GroupID = Integer

type FreeOr t f = Either (f Free) (f t)

data Ext a = Ext {
    getDate :: DateTime,
    getLocation :: SourcePos,
    getAttributes :: Attributes,
    getContent :: a }
  deriving (Eq, Show)

class HasAmount a where
  getAmount :: a -> Amount

class Named a where
  getName :: a -> String

class HasID a where
  getID :: a -> Integer

class HasCurrency a where
  getCurrency :: a -> Currency

data Amount = Decimal :# Currency
  deriving (Eq)

instance Show Amount where
  show (n :# c) = show n ++ c

instance HasCurrency Amount where
  getCurrency (_ :# c) = c

data Param =
    Fixed Amount
  | Param Int Double Amount
  | Plus Param Param
  deriving (Eq)

instance Show Param where
  show (Fixed x) = show x
  show (Param n x d) = "#" ++ show n ++ " * " ++ show x
                    ++ " (default " ++ show d ++ ")"
  show (Plus x y) = show x ++ " + " ++ show y

instance Eq a => Ord (Ext a) where
  compare x y = compare (getDate x) (getDate y)

instance HasID a => HasID (Ext a) where
  getID x = getID (getContent x)

instance Named a => Named (Ext a) where
  getName x = getName (getContent x)

instance (HasID (f Free), HasID (f t)) => HasID (FreeOr t f) where
  getID (Left x)  = getID x
  getID (Right x) = getID x

instance HasAmount a => HasAmount (Ext a) where
  getAmount x = getAmount (getContent x)

data AccountGroupType =
    AGCredit
  | AGDebit
  | AGFree
  deriving (Eq)

instance Show AccountGroupType where
  show AGCredit = "credit"
  show AGDebit  = "debit"
  show AGFree   = "free"

data AccountGroupData = AccountGroupData {
    agName :: String,
    agID :: Integer,
    agRange :: (Integer, Integer),
    agCurrency :: Currency,
    agType :: AccountGroupType,
    agAttributes :: Attributes }
  deriving (Eq)

instance Show AccountGroupData where
  show ag =
    printf "#%d: %s: %s (%s) (%d--%d] %s"
      (agID ag)
      (show $ agType ag)
      (agName ag)
      (agCurrency ag)
      (fst $ agRange ag)
      (snd $ agRange ag)
      (showA $ agAttributes ag)

instance HasID AccountGroupData where
  getID ag = agID ag
