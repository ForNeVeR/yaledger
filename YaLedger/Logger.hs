{-# LANGUAGE FlexibleContexts, TemplateHaskell #-}

module YaLedger.Logger
  (Priority (..),
   setupLogger,
   debug, info, warning, errorMessage,
   debugP, infoP, warningP,
   debugSTM, infoSTM, warningSTM,
   infoSTMP, warningSTMP,
   debugIO, infoIO,
   handler,
   trace, traceS,
   L.traceEventIO, L.traceEventM
  ) where

import Control.Monad
import Control.Monad.Exception
import System.Log.Logger

import YaLedger.Kernel.STM
import YaLedger.Logger.TH
import qualified YaLedger.Logger.Loggers as L

setupLogger :: Priority -> [(String, Priority)] -> IO ()
setupLogger def pairs = do
  updateGlobalLogger rootLoggerName (setLevel def)
  forM_ $(allLoggers) $ \name ->
      case lookup name pairs of
        Nothing -> return ()
        Just p  -> updateGlobalLogger name (setLevel p)

handler loc e =
  wrapIO (emergencyM rootLoggerName $ showExceptionWithTrace loc e)


