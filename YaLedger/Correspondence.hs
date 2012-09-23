{-# LANGUAGE RecordWildCards #-}

module YaLedger.Correspondence where

import Control.Monad
import Data.Maybe
import Data.List
import qualified Data.Map as M
import Text.Printf

import YaLedger.Types

nonsignificantAttributes :: [String]
nonsignificantAttributes =
  ["description", "source"]

matchT :: PostingType -> AccountGroupType -> Bool
matchT _       AGFree   = True
matchT ECredit AGCredit = True
matchT EDebit  AGDebit  = True
matchT _       _        = False

match :: Attributes -> Attributes -> Bool
match attrs qry =
  let check (name, value) = case M.lookup name attrs of
                              Nothing -> name `elem` nonsignificantAttributes
                              Just av  -> matchAV value av
  in  all check $ M.assocs qry

matchAll :: Attributes -> Attributes -> Bool
matchAll attrs qry =
  let check (name, value) = case M.lookup name qry of
                              Nothing -> name `elem` ["source", "rule"]
                              Just av  -> matchAV value av
  in  all check (M.assocs attrs) && all (`elem` M.keys attrs) (M.keys qry)

additionalAttributes :: Attributes -> AnyAccount -> Int
additionalAttributes as a = 
    go (filter (\(name,_) -> name `elem` nonsignificantAttributes) $ M.assocs as) a
  where
    go []     _   = 1
    go ((k,v):as) acc =
      case M.lookup k (accountAttributes acc) of
        Nothing -> go as acc
        Just av -> if matchAV v av
                     then 1 + go as acc
                     else     go as acc

filterByAddAttributes :: Attributes -> [AnyAccount] -> [AnyAccount]
filterByAddAttributes as accs =
  let scores = [(acc, additionalAttributes as acc) | acc <- accs]
      m      = maximum (map snd scores)
  in  [acc | (acc, score) <- scores, score == m]

first :: (a -> Maybe b) -> [a] -> Maybe b
first _ [] = Nothing
first fn (x:xs) =
    case fn x of
      Just y  -> Just y
      Nothing -> first fn xs

filterPlan :: CQuery -> AccountPlan -> [AnyAccount]
filterPlan qry@(CQuery {..}) (Branch {..}) =
    if (cqType `matchT` agType branchData) || (agType branchData == AGFree)
      then concatMap (filterPlan qry) branchChildren
      else []

filterPlan (CQuery {..}) (Leaf {..}) =
    if (getID leafData `notElem` cqExcept) &&
       ((cqType `matchT` accountType leafData) ||
        (accountType leafData == AGFree))
      then if (getCurrency leafData `elem` cqCurrency) &&
              (accountAttributes leafData `match` cqAttributes)
             then [leafData]
             else []
      else []

runCQuery :: CQuery -> AccountPlan -> Maybe AnyAccount
runCQuery qry plan =
  case filterPlan qry plan of
    []  -> Nothing
    [x] -> Just x
    list -> Just $ head $ filterByAddAttributes (cqAttributes qry) list

inRange :: Integer -> (Integer, Integer) -> Bool
inRange i (m, n) = (m < i) && (i <= n)

-- | List of groups IDs of all account's parent groups
groupIDs :: AccountID         -- ^ Account ID
         -> AccountPlan
         -> Maybe [GroupID] -- ^ Groups IDs
groupIDs i tree = go [] i tree
  where
    go :: [GroupID] -> AccountID -> AccountPlan -> Maybe [GroupID]
    go xs i (Branch _ ag children)
      | i `inRange` agRange ag = do
        let accs = [acc | Leaf _ acc <- children]
        case filter (\a -> getID a == i) accs of
          [_] -> return (agID ag: xs)
          _   -> let grps = [map (go (agID ag: agID ag': xs) i) grp | Branch _ ag' grp <- children]
                 in  msum $ concat grps
      | otherwise = Nothing
    go xs i (Leaf _ acc)
      | getID acc == i = Just xs
      | otherwise      = Nothing

-- | Lookup for corresponding account by account map
lookupAMap :: AccountPlan
           -> AccountMap
           -> CQuery
           -> [AccountID]       -- ^ Account IDs
           -> Maybe AnyAccount
lookupAMap plan amap qry is = listToMaybe $ catMaybes $ concat [map (good i) amap | i <- is]
  where
    good :: AccountID -> AMEntry -> Maybe AnyAccount
    good i (AMAccount j :=> ToAccountPlan r)
      | i == j    = runCQuery qry r
      | otherwise = Nothing
    good i (AMAccount j :=> ToAttributes as)
      | i == j    = runCQuery (qry {cqAttributes = as `M.union` cqAttributes qry}) plan
      | otherwise = Nothing
    good i (AMGroup g :=> ToAccountPlan r) =
      let gids = fromMaybe [] $ groupIDs i plan
      in  if g `elem` gids
            then runCQuery qry r
            else Nothing
    good i (AMGroup g :=> ToAttributes as) =
      let gids = fromMaybe [] $ groupIDs i plan
          qry' = qry {cqAttributes = as `M.union` cqAttributes qry}
      in  if g `elem` gids
            then runCQuery qry' plan
            else Nothing
    good _ (AMAttributes as :=> ToAccountPlan r)
      | cqAttributes qry `matchAll` as = runCQuery qry r
      | otherwise = Nothing
    good _ (AMAttributes as :=> ToAttributes as')
      | cqAttributes qry `matchAll` as =
            let attrs = as' `M.union` cqAttributes qry
            in  runCQuery (qry {cqAttributes = attrs}) plan
      | otherwise = Nothing

