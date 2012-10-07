{-# LANGUAGE CPP, FlexibleContexts #-}

module YaLedger.Logger
  (Priority (..),
   setupLogger,
   debug,
   info, warning, errorMessage,
   handler,
   trace, traceS
  ) where

import Control.Monad.Exception
import Control.Monad.Loc
import System.Log.Logger
import System.IO.Unsafe

import YaLedger.Monad
import YaLedger.Exceptions

setupLogger :: Priority -> IO ()
setupLogger p = do
  updateGlobalLogger rootLoggerName (setLevel p)

debug :: Throws InternalError l => String -> Ledger l ()
debug str =
#ifdef DEBUG
  wrapIO $ debugM rootLoggerName $ "DEBUG: " ++ str
#else
  return ()
#endif

errorMessage :: Throws InternalError l => String -> Ledger l ()
errorMessage str =
  wrapIO $ errorM rootLoggerName $ "ERROR: " ++ str

info :: Throws InternalError l => String -> Ledger l ()
info str =
  wrapIO $ infoM rootLoggerName $ "INFO: " ++ str

warning :: Throws InternalError l => String -> Ledger l ()
warning str =
  wrapIO $ warningM rootLoggerName $ "WARNING: " ++ str

handler loc e =
  wrapIO (emergencyM rootLoggerName $ showExceptionWithTrace loc e)

trace :: String -> a -> a
#ifdef DEBUG
trace str x = unsafePerformIO $ do
  debugM rootLoggerName $ "TRACE: " ++ str
  return x
{-# NOINLINE trace #-}
#else
trace _ x = x
#endif

traceS :: Show b => String -> b -> b
#ifdef DEBUG
traceS prefix x = unsafePerformIO $ do
  debugM rootLoggerName $ "TRACE: " ++ prefix ++ ": " ++ show x
  return x
{-# NOINLINE traceS #-}
#else
traceS _ x = x
#endif
