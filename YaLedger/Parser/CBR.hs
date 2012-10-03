{-# LANGUAGE OverloadedStrings #-}
module YaLedger.Parser.CBR
  (loadCBR
  ) where

import Control.Applicative
import Control.Monad
import Data.List
import qualified Data.Map as M
import qualified Data.Text.Lazy as T
import qualified Data.Text.Lazy.Encoding as E
import qualified Data.ByteString.Lazy as L
import qualified Codec.Text.IConv as IConv
import Data.Tree.NTree.TypeDefs
import Text.XML.HXT.Core
import Data.Yaml
import Data.Dates
import Network.HTTP
import Network.Browser
import Text.Printf

import YaLedger.Types hiding (getChildren)
import YaLedger.Config
import YaLedger.Parser.Tables (loadParserConfig)

type ParserConfig = [GetRate]

data GetRate = GetRate {
  currencyName :: Currency,
  currencyCode :: Int,
  readAsReversible :: Bool,
  startDate :: DateTime,
  checkInterval :: DateInterval }
  deriving (Eq, Show)

instance Ord GetRate where
  compare gr1 gr2 = compare (currencyName gr1) (currencyName gr2)

instance FromJSON GetRate where
  parseJSON (Object v) =
    GetRate
      <$> v .: "currency"
      <*> v .: "code"
      <*> v .:? "reversible" .!= False
      <*> v .:  "start-date"
      <*> v .:? "check-interval" .!= Weeks 1
  parseJSON _ = fail "CBR rate descriptor: invalid object"

checks :: DateTime -> GetRate -> [(DateTime, GetRate)]
checks till gr = go (startDate gr)
  where
    go date
      | date < till = (date, gr): go (date `addInterval` checkInterval gr)
      | otherwise   = []

splitP :: (a -> Bool) -> [a] -> ([a], [a])
splitP _ [] = ([], [])
splitP p list = go [] [] list
  where
    go good bad [] = (good, bad)
    go good bad (x:xs)
      | p x = go (x:good) bad xs
      | otherwise = go good (x:bad) xs

allChecks :: DateTime -> ParserConfig -> [(DateTime, [GetRate])]
allChecks till pc = mrg $ sort $ concatMap (checks till) pc
  where
    mrg [] = []
    mrg [(d,c)] = [(d, [c])]
    mrg ((d1,c1):xs) =
      let (sameDate, other) = splitP ((== d1) . fst) xs
      in  (d1, map snd sameDate): mrg other

is ::  ArrowXml cat => String -> cat XmlTree XmlTree
is name = isElem >>> hasName name

getRateStrings :: (ArrowXml cat) => [Int] -> cat (NTree XNode) (String, String)
getRateStrings cids =
    getChildren >>> is "ValCurs" /> is "Valute" >>> check `guards` (nominal &&& rate)
  where
    check = getChildren >>> is "NumCode" /> hasText (`elem` map show cids)

    nominal = getChildren >>> is "Nominal" /> getText

    rate = getChildren >>> is "Value" /> getText

-- | HACK around <? xml encoding='windows-1251' ?>
skipXmlDecl :: String -> String
skipXmlDecl str = go 0 str
  where
    go _ [] = []
    go 0 ('<':xs) = go 1 xs
    go 1 ('?':xs) = go 2 xs
    go 2 (x:xs)
      | x == '?'  = go 3 xs
      | otherwise = go 2 xs
    go 3 ('>':xs) = xs
    go 3 (x:xs) = go 2 xs
    go _ _ = error "Impossible: skipXmlDecl"

-- | Get CBR XML exchange rates description
getCBRXML :: DateTime -> IO String
getCBRXML date = do
  let src :: String
      src = printf "http://www.cbr.ru/scripts/XML_daily.asp?date_req=%02d/%02d/%04d"
                   (day date) (month date) (year date)
  (_, rsp) <- browse $ do
               setAllowRedirects True -- handle HTTP redirects
               request $ getRequest src
  return $ skipXmlDecl (rspBody rsp)

parseRates :: String -> [Int] -> IO [(Double, Double)]
parseRates str cids = do
    pairs <- runX $ readString [] str >>> getRateStrings cids
    return $ map (double *** double) pairs
  where
    double s = read (dot s)

    dot [] = []
    dot (',':s) = '.':s
    dot (x:xs) = x: dot xs

loadCBR :: FilePath -> ChartOfAccounts -> FilePath -> IO [Ext Record]
loadCBR configPath _ _ = do
    config <- loadParserConfig configPath
    now <- getCurrentDateTime
    rs <- forM (allChecks now config) $ \(date, grs) -> do
            doc <- getCBRXML date
            pairs <- parseRates doc (map currencyCode grs)
            return $ zipWith (convert date) pairs grs
    return (concat rs)
  where
    nowhere = newPos "<nowhere>" 0 0
    convert date (aFrom, aTo) gr =
      Ext date nowhere M.empty $ Transaction $ TSetRate [
          Explicit (currencyName gr) aFrom "р" aTo (readAsReversible gr) ]

test :: IO ()
test = do
  str <- getCBRXML (DateTime 2012 10 03 0 0 0)
  rates <- parseRates str [840, 978]
  forM_ rates print

