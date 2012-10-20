{-# LANGUAGE OverloadedStrings #-}
module YaLedger.Parser.CSV where

import Control.Applicative
import Control.Monad
import Data.Yaml

import YaLedger.Types
import YaLedger.Parser.Common (loadParserConfig)
import YaLedger.Parser.Tables

data ParserConfig = ParserConfig {
    pcSeparator  :: Char,
    pcGeneric    :: GenericParserConfig
    }
  deriving (Eq, Show)

instance FromJSON ParserConfig where
  parseJSON (Object v) =
    ParserConfig
      <$> v .:? "separator" .!= ','
      <*> parseGenericConfig [] v

csvCells :: Char -> String -> [[String]]
csvCells sep str = map parseRow $ lines str
  where
    parseRow = split sep

parseCSV :: ParserConfig
         -> FilePath
         -> Currencies
         -> ChartOfAccounts
         -> String
         -> IO [Ext Record]
parseCSV pc path currs coa str =
  let rows = csvCells (pcSeparator pc) str
      goodRows = filterRows (pcRowsFilter $ pcGeneric pc) rows
  in  zipWithM (convertRow (pcGeneric pc) currs coa path) [1..] goodRows

loadCSV :: FilePath -> Currencies -> ChartOfAccounts -> FilePath -> IO [Ext Record]
loadCSV configPath currs coa csvPath = do
  config <- loadParserConfig configPath 
  csv <- readFile csvPath
  parseCSV config csvPath currs coa csv

