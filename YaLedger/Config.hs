{-# LANGUAGE OverloadedStrings #-}
module YaLedger.Config where

import Control.Applicative
import Control.Monad
import Data.Monoid
import qualified Data.Text as T
import qualified Data.HashMap.Strict as H
import qualified Data.ByteString as B
import qualified Data.Map as M
import Data.Yaml
import Data.Dates
import System.FilePath
import System.Directory
import System.Environment.XDG.BaseDir
import System.Environment.XDG.UserDir
import Text.Parsec

import YaLedger.Types.Transactions
import YaLedger.Attributes
import YaLedger.Logger
import YaLedger.Parser.Common (pAttributeValue)

data Options =
    Options {
      chartOfAccounts :: Maybe FilePath,
      accountMap :: Maybe FilePath,
      files :: [FilePath],
      query :: Query,
      logSeverity :: Priority,
      parserConfigs :: [(String, FilePath)],
      reportParams :: [String] }
  | Help
  deriving (Eq, Show)

instance Monoid Options where
  mempty = Help
  mappend Help o = o
  mappend o Help = o
  mappend o1 o2 =
    Options {
      chartOfAccounts = chartOfAccounts o1 `mappend` chartOfAccounts o2,
      accountMap  = accountMap  o1 `mappend` accountMap o2,
      files = if null (files o2) then files o1 else files o2,
      query = query o1 `mappend` query o2,
      logSeverity = min (logSeverity o1) (logSeverity o2),
      parserConfigs = parserConfigs o1 ++ parserConfigs o2,
      reportParams = if null (reportParams o2) then reportParams o1 else reportParams o2 }

instance Monoid Query where
  mempty = Query Nothing Nothing M.empty
  mappend q1 q2 =
    Query {
      qStart = qStart q1 `mappend` qStart q2,
      qEnd   = qEnd   q1 `mappend` qEnd   q2,
      qAttributes = qAttributes q1 `M.union` qAttributes q2 }

instance FromJSON Options where
  parseJSON (Object v) =
    Options
      <$> v .:? "chart-of-accounts"
      <*> v .:? "accounts-map"
      <*> v .:?  "files" .!= []
      <*> v .:? "query" .!= Query Nothing Nothing M.empty
      <*> v .:? "debug" .!= WARNING
      <*> (parseConfigs =<< (v .:? "parsers"))
      <*> return []
  parseJSON _ = fail "Invalid object"

instance FromJSON Priority where
  parseJSON (String text) =
    case text of
      "debug"     -> return DEBUG
      "info"      -> return INFO
      "notice"    -> return NOTICE
      "warning"   -> return WARNING
      "error"     -> return ERROR
      "critical"  -> return CRITICAL
      "alert"     -> return ALERT
      "emergency" -> return EMERGENCY
      _ -> fail $ "Unknown debug level: " ++ T.unpack text

instance FromJSON Query where
  parseJSON (Object v) =
    Query
      <$> v .:? "start"
      <*> v .:? "end"
      <*> parseAttrs v
  parseJSON _ = fail "Invalid object"

instance FromJSON DateTime where
  parseJSON (String text) =
    case parseDate (DateTime 2012 1 1 0 0 0) (T.unpack text) of
      Left err -> fail $ show err
      Right date -> return date

parseAttrs :: Object -> Parser Attributes
parseAttrs obj = do
  let pairs = H.toList obj
      pairs' = filter (\(name,_) -> name `notElem` ["start","end"]) pairs

      parseValue (String text) = do
        let str = T.unpack text
        case runParser pAttributeValue () str str of
          Left err -> fail $ show err
          Right val -> return val
      parseValue _ = fail "Invalid object type in attribute value"

  attrs <- forM pairs' $ \(name,value) -> do
               value' <- parseValue value
               return (T.unpack name, value')
  return $ M.fromList attrs

parseConfigs :: Maybe Object -> Parser [(String, FilePath)]
parseConfigs Nothing = return []
parseConfigs (Just obj) = do
  let pairs = H.toList obj
  return [(T.unpack name, T.unpack value) | (name, String value) <- pairs]

getDefaultOptions :: IO Options
getDefaultOptions = do
  now <-  getCurrentDateTime
  configDir <- getUserConfigDir "yaledger"
  documents <- getUserDir "DOCUMENTS"
  let inputFile = documents </> "yaledger" </> "default.yaledger"
  return $ Options {
        chartOfAccounts = Just (configDir </> "default.accounts"),
        accountMap  = Just (configDir </> "default.map"),
        files = [inputFile],
        query = Query {
                  qStart = Nothing,
                  qEnd   = Just now,
                  qAttributes = M.empty },
        logSeverity = WARNING,
        parserConfigs = [],
        reportParams = ["balance"] }

loadConfig :: IO Options
loadConfig = do
  defaultOptions <- getDefaultOptions
  configFile <- getUserConfigFile "yaledger" "yaledger.yaml"
  exist <- doesFileExist configFile
  if not exist
    then return defaultOptions
    else do
        str <- B.readFile configFile
        case decode str of
          Nothing -> fail $ "Cannot parse config file: " ++ configFile
          Just options -> return (defaultOptions `mappend` options)

