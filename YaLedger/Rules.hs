{-# LANGUAGE GADTs, RecordWildCards, FlexibleContexts #-}
{-# OPTIONS_GHC -F -pgmF MonadLoc #-}
module YaLedger.Rules where

import Control.Monad.State
import Control.Monad.Exception
import Control.Monad.Exception.Base
import Control.Monad.Loc
import Data.Maybe
import Data.Decimal
import qualified Data.Map as M
import Data.Dates

import YaLedger.Types
import YaLedger.Monad
import YaLedger.Exceptions
import YaLedger.Kernel
import YaLedger.Correspondence
import YaLedger.Templates

matchC :: Throws NoSuchRate l
       => Posting Decimal t
       -> Condition
       -> Ledger l Bool
matchC (CPosting acc x) cond = check ECredit acc x cond
matchC (DPosting acc x) cond = check EDebit  acc x cond

check t acc x (Condition {..}) = do
  plan <- gets lsAccountPlan
  let accID = getID acc
  let grps = fromMaybe [] $ groupIDs accID plan
      action = maybe [ECredit, EDebit] (\x -> [x]) cAction
  if (t `elem` action) &&
     ((accID `elem` cAccounts) ||
      (any (`elem` cGroups) grps))
    then do
         let accountCurrency = getCurrency acc
         if cValue == AnyValue
           then return True
           else do
                let (op, v) = case cValue of
                                MoreThan s -> ((>), s)
                                LessThan s -> ((<), s)
                                Equals s   -> ((==), s)
                                _ -> error "Impossible."
                condValue :# _ <- convert accountCurrency v
                return $ x `op` condValue
    else return False

runRules :: (Throws NoSuchRate l,
             Throws NoCorrespondingAccountFound l,
             Throws InvalidAccountType l,
             Throws NoSuchTemplate l,
             Throws InternalError l)
         => DateTime
         -> Attributes
         -> Posting Decimal t
         -> (Ext Record -> Ledger l ())
         -> Ledger l ()
runRules date pAttrs p run = do
  rules <- gets lsRules
  forM_ rules $ \(name, attrs, When cond tran) -> do
    y <- p `matchC` cond
    if y
      then do
           let attrs' = M.insert "rule" (Exactly name) attrs
               (c, x) = case p of
                            DPosting acc x -> (getCurrency acc,x)
                            CPosting acc x -> (getCurrency acc,x)
           tran' <- fillTemplate tran [x :# c]
           run (Ext date attrs' (Transaction tran'))
      else return ()

