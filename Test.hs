{-# LANGUAGE ScopedTypeVariables, FlexibleContexts #-}
{-# OPTIONS_GHC -F -pgmF MonadLoc #-}

module Test where

import Prelude hiding (catch)
import Control.Monad
import Control.Monad.State
import Control.Monad.Exception
import Control.Monad.Exception.Base
import Control.Monad.Loc
import Data.Dates
import Text.Parsec

import YaLedger.Types
import YaLedger.Tree
import YaLedger.Kernel
import YaLedger.Correspondence
import YaLedger.Processor
import YaLedger.Exceptions
import YaLedger.Monad
import YaLedger.Parser
import YaLedger.Pretty
import YaLedger.Reports.Balance

process :: [Ext Record] -> LedgerMonad ()
process trans =
  runEMT $ do
           forM_ trans processTransaction
           b <- balance
           wrapIO $ print b
        `catchWithSrcLoc`
           (\loc (e :: InvalidAccountType) -> wrapIO $ putStrLn (showExceptionWithTrace loc e))
        `catchWithSrcLoc`
           (\loc (e :: NoSuchRate) -> wrapIO $ putStrLn (showExceptionWithTrace loc e))
        `catchWithSrcLoc`
           (\loc (e :: NoCorrespondingAccountFound) -> wrapIO $ putStrLn (showExceptionWithTrace loc e))
        `catchWithSrcLoc`
           (\loc (e :: NoSuchTemplate) -> wrapIO $ putStrLn (showExceptionWithTrace loc e))

test :: IO ()
test = do
  plan <- readPlan "test.accounts"
  print plan
  amap <- readAMap plan "test.map"
  forM amap print
  trans <- readTrans plan "test.yaledger"
  forM trans $ \t ->
    putStrLn (prettyPrint t)
  runLedger plan amap $ process trans
  return ()
