{-# LANGUAGE CPP                  #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ScopedTypeVariables  #-}

module Luna.Compilation.Pass.Inference.Calling where

import Prelude.Luna

import Control.Monad.Except                         (throwError, ExceptT, runExceptT)
import Data.Container                               (add)
import Data.Construction
import Data.Either                                  (rights)
import Data.Prop
import Data.Record.Match
import Data.Layer_OLD
import Luna.Runtime.Dynamics                      (Static)
import Old.Luna.Syntax.Term.Class                         hiding (source)
import Data.Graph.Builder                           as Graph hiding (run)
import Data.Graph                                   as Graph hiding (add)
import qualified Data.Graph.Backend.NEC               as NEC
import Luna.Syntax.Model.Layer
import Luna.Syntax.Model.Network.Builder            (dupCluster, replacement, redirect, readSuccs, requester, originSign, Sign (..))
import Luna.Syntax.Model.Network.Builder.Node
import Luna.Syntax.Model.Network.Builder.Term.Class (runNetworkBuilderT, NetGraph, NetLayers, NetCluster)
import Luna.Syntax.Model.Network.Class              ()
import Luna.Syntax.Model.Network.Term
import Type.Inference

import qualified Data.Map as Map
import           Data.Map (Map)

import qualified Luna.Syntax.Term.Function as Function

import           Luna.Compilation.Stage.TypeCheck       (ProgressStatus (..), TypeCheckerPass, hasJobs, runTCPass)
import           Luna.Compilation.Stage.TypeCheck.Class (MonadTypeCheck)
import qualified Luna.Compilation.Stage.TypeCheck.Class as TypeCheck
import           Data.Layer_OLD.Cover_OLD


-- FIXME[MK]: Do not explicitly type stuff here as NetGraph, solve the problems with typing it differently

#define PassCtx(m) ( term  ~ Draft Static                         \
                   , ls    ~ NetLayers                            \
                   , edge  ~ Link (ls :<: term)                   \
                   , node  ~ (ls :<: term)                        \
                   , clus  ~ NetCluster                           \
                   , graph ~ Hetero (NEC.Graph n e c)             \
                   , BiCastable     e edge                        \
                   , BiCastable     n node                        \
                   , BiCastable     c clus                        \
                   , MonadBuilder graph (m)                       \
                   , NodeInferable  (m) (ls :<: term)             \
                   , TermNode Var   (m) (ls :<: term)             \
                   , TermNode Acc   (m) (ls :<: term)             \
                   , TermNode Cons  (m) (ls :<: term)             \
                   , TermNode Lam   (m) (ls :<: term)             \
                   , TermNode Unify (m) (ls :<: term)             \
                   , TermNode Curry (m) (ls :<: term)             \
                   , Clusterable Node node clus (m)               \
                   , Destructor (m) (Ref Edge edge)               \
                   , ReferencedM Node graph (m) node              \
                   , ReferencedM Edge graph (m) edge              \
                   , MonadIO (m) \
                   )

data CallError = NotAFuncallNode | NotACurryNode | UnresolvedFunction | MalformedFunction deriving (Show, Eq)

type CallErrorT = ExceptT CallError

{-is :: PassCtx(m) => Ref Node node -> Proxy -}

isUni :: PassCtx(m) => Ref Node node -> m Bool
isUni r = do
    n <- read r
    return $ caseTest (uncover n) $ do
        of' $ \(Unify _ _) -> True
        of' $ \ANY -> False

unifyArgTypes :: PassCtx(CallErrorT m) => Function.Signature (Ref Node node) -> Ref Node node ->  [Ref Node node] -> CallErrorT m [Ref Node node]
unifyArgTypes fptr caller args = do
    let getType = follow (prop Type) >=> follow source
    argTps  <- mapM getType args
    argFTps <- mapM getType $ (unlayer <$> fptr ^. Function.args) -- FIXME[WD->MK] handle arg names. Using unlayer for now
    argUnis <- zipWithM unify argFTps argTps
    mapM_ (flip (reconnect $ prop TCData . requester) $ Just caller) argUnis
    mapM_ (flip withRef $ prop TCData . originSign .~ Negative) argUnis
    return argUnis

unifyAppOutType :: PassCtx(CallErrorT m) => Function.Signature (Ref Node node) -> Ref Node node -> CallErrorT m (Ref Node node)
unifyAppOutType fptr app = do
    let getType = follow (prop Type) >=> follow source
    outTp   <- getType app
    outFTp  <- getType $ fptr ^. Function.out
    argTps  <- mapM getType $ unlayer <$> fptr ^. Function.args
    tp <- case argTps of
        [] -> return outFTp
        _  -> lam (arg <$> argTps) outFTp
    outUni  <- unify tp outTp
    reconnect (prop TCData . requester) outUni $ Just app
    return outUni

setupCall :: (PassCtx(CallErrorT m), Monad m) => Ref Node node -> [Ref Node node] -> Ref Cluster clus -> CallErrorT m (Ref Cluster clus, Function.Signature (Ref Node node))
setupCall caller args funClus = do
    (cls, _) <- dupCluster funClus $ show caller
    fptr <- follow (prop Lambda) cls <?!> MalformedFunction
    withRef caller $ (prop TCData . replacement ?~ cast cls)
    let argDefs = fptr ^. Function.args
    zipWithM (reconnect $ prop TCData . redirect) (unlayer <$> argDefs) (Just <$> args)
    let outstandingArgs = drop (length args) argDefs
    let appliedPtr = fptr & Function.args .~ outstandingArgs
    withRef cls $ prop Lambda ?~ appliedPtr
    return (cls, fptr)

makeFuncall :: (PassCtx(CallErrorT m), Monad m) => Ref Node node -> [Ref Node node] -> Ref Cluster clus -> CallErrorT m [Ref Node node]
makeFuncall app args funClus = do
    (cls, fptr) <- setupCall app args funClus
    argUnis     <- unifyArgTypes fptr app args
    newFptr     <- follow (prop Lambda) cls <?!> MalformedFunction
    outUni      <- unifyAppOutType newFptr app
    importUnis  <- filterM isUni =<< members cls
    when (null $ newFptr ^. Function.args) $ void $ reconnect (prop TCData . redirect) app $ Just $ fptr ^. Function.out
    return $ importUnis <> (outUni : argUnis)

processApp :: (PassCtx(CallErrorT m), Monad m) => Ref Node node -> CallErrorT m [Ref Node node]
processApp ref = do
    node <- read ref
    caseTest (uncover node) $ do
        of' $ \(App f as) -> do
            funReplacement <- (follow (prop TCData . replacement . casted) =<< follow source f) <?!> UnresolvedFunction
            args <- mapM (follow source . unlayer) as
            makeFuncall ref args funReplacement
        of' $ \ANY -> throwError NotAFuncallNode

-----------------------------
-- === TypeCheckerPass === --
-----------------------------

data FunctionCallingPass = FunctionCallingPass deriving (Show, Eq)

instance ( PassCtx(CallErrorT m)
         , PassCtx(m)
         , MonadTypeCheck (ls :<: term) m
         ) => TypeCheckerPass FunctionCallingPass m where
    hasJobs _ = do
        tc <- TypeCheck.get
        let apps  = tc ^. TypeCheck.uncalledApps
        return $ not . null $ apps

    runTCPass _ = do
        apps    <- view TypeCheck.uncalledApps <$> TypeCheck.get
        results <- mapM (runExceptT . processApp) apps
        let withRefs = zip apps results
            failures = fst <$> filter (isLeft . snd) withRefs
        TypeCheck.modify_ $ (TypeCheck.unresolvedUnis %~ (++ (concat $ rights results)))
                          . (TypeCheck.uncalledApps   .~ failures)
        return $ if length failures == length apps then Stuck else Progressed
