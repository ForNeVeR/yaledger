
module CmdLine where

import System.Console.GetOpt
import System.Environment
import System.FilePath ((</>))
import Codec.Binary.UTF8.String
import Data.List

import Types
import Dates

emptyCmdLine :: DateTime -> IO CmdLine
emptyCmdLine dt = do
  home <- getEnv "HOME"
  return $ CmdLine [EndDate dt] (home </> ".yaledger") Balance

defaultQuery :: DateTime -> Query
defaultQuery dt = Q {
    startDate = Nothing,
    endDate   = Just dt,
    statusIs  = Nothing }

parseOptions :: DateTime -> [Option] -> IO CmdLine
parseOptions dt opts = do
    ecl <- emptyCmdLine dt
    return $ foldl plus ecl opts
  where
    plus cl (QF f)         = cl {qFlags = f: qFlags cl}
    plus cl (SourceFile f) = cl {srcFile = f}
    plus cl (MF m)         = cl {mode = m}

parseQFlags :: DateTime -> [QFlag] -> Query
parseQFlags dt qflags = foldl plus (defaultQuery dt) qflags
  where
    plus q (StartDate dt) = q {startDate = Just dt}
    plus q (EndDate dt)   = q {endDate = Just dt}
    plus q (Status c)     = q {statusIs = Just c}

options :: DateTime -> [OptDescr Option]
options dt = [
    Option "b" ["start-date"] (ReqArg (qf dt StartDate) "DATE")   "select only records after given DATE",
    Option "e" ["end-date"]   (ReqArg (qf dt EndDate)   "DATE")   "select only records before given DATE",
    Option "s" ["status"]     (ReqArg mkStatusQ         "CHAR")   "select only records with given status",
    Option "f" ["file"]       (ReqArg SourceFile        "PATH")   "use given file instead of ~/.yaledger"
  ]

usage :: String
usage = usageInfo header (options undefined)
  where 
    header = "Usage: yaledger [OPTIONS] [MODE]"

qf :: DateTime -> (DateTime -> QFlag) -> String -> Option
qf dt constr str = QF $ constr $ parseAbsDate dt str

mkStatusQ :: String -> Option
mkStatusQ str = QF $ Status (head str)

parseCmdLine :: DateTime -> [String] -> IO CmdLine
parseCmdLine dt args = 
      case getOpt RequireOrder (options dt) (map decodeString args) of
        (flags, [],      [])     -> parseOptions dt flags
        (flags, nonOpts, [])     -> parseOptions dt (parseMode nonOpts:flags)
        (_,     _,       msgs)   -> error $ concat msgs ++ usage
    where
      parseMode :: [String] -> Option
      parseMode [mode]      | mode `isPrefixOf` "balance"  = MF Balance
      parseMode [mode,path] | mode `isPrefixOf` "register" = MF $ Register path
      parseMode lst                                        = error $ "Unknown mode: " ++ show lst



