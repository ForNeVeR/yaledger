{-# LANGUAGE EmptyDataDecls, GADTs, FlexibleContexts, FlexibleInstances, UndecidableInstances, TypeSynonymInstances, DeriveDataTypeable, RecordWildCards, ScopedTypeVariables, MultiParamTypeClasses #-}

module YaLedger.Types
  (module YaLedger.Tree,
   module YaLedger.Attributes,
   module YaLedger.Types.Common,
   module YaLedger.Types.Ledger,
   module YaLedger.Types.Map,
   module YaLedger.Types.Transactions,
   module YaLedger.Types.Rules,
   module YaLedger.Types.Config,
   Rule (..)
  ) where

import YaLedger.Tree
import YaLedger.Attributes
import YaLedger.Types.Common
import YaLedger.Types.Ledger
import YaLedger.Types.Map
import YaLedger.Types.Transactions
import YaLedger.Types.Rules
import YaLedger.Types.Config

data Rule = When Condition (Transaction Param)
  deriving (Eq, Show)

