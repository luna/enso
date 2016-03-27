{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE CPP                       #-}

{-# LANGUAGE UndecidableInstances #-} -- used for resolution monad, delete after refactoring

module Luna.Compilation.Pass.Inference.Unification where

import Prelude.Luna

import Data.Construction
import Data.Container                               hiding (impossible)
import Data.List                                    (delete, sort)
import Data.Prop
import qualified Data.Record                        as Record
import Data.Record                                  (caseTest, of', ANY (..))
import Luna.Runtime.Dynamics                      (Static, Dynamic)
import Data.Index
import Luna.Syntax.Term.Expr                         hiding (source, target)
import Data.Graph.Builder                           hiding (run)
import Luna.Syntax.Model.Layer
import Luna.Syntax.Model.Network.Builder.Node
import Luna.Syntax.Model.Network.Builder            (HasSuccs, readSuccs, TCData, TCDataPayload, requester, tcErrors, depth)
import Luna.Syntax.Model.Network.Class              ()
import Luna.Syntax.Model.Network.Term
import Luna.Syntax.Name.Ident.Pool                  (MonadIdentPool, newVarIdent')
import Type.Inference
import Data.Graph                                   as Graph hiding (add, remove)
import qualified Data.Graph.Backend.NEC               as NEC

import qualified Data.Graph.Builder                     as Graph
import           Luna.Compilation.Stage.TypeCheck       (ProgressStatus (..), TypeCheckerPass, hasJobs, runTCPass)
import           Luna.Compilation.Stage.TypeCheck.Class (MonadTypeCheck)
import qualified Luna.Compilation.Stage.TypeCheck.Class as TypeCheck
import qualified Luna.Syntax.Term.Lit               as Lit
import           Luna.Syntax.Term.Function.Argument
import           Luna.Compilation.Error


import Control.Monad.Fix
import Control.Monad (liftM, MonadPlus(..))

import Control.Monad.Trans.Either

#define PassCtx(m,ls,term) ( term  ~ Draft Static                  \
                           , node  ~ (ls :<: term)                 \
                           , edge  ~ Link node                     \
                           , graph ~ Hetero (NEC.Graph n e c)      \
                           , Covered node                          \
                           , nodeRef ~ Ref Node node               \
                           , Prop Type   node ~ Ref Edge edge      \
                           , Prop TCData node ~ TCDataPayload node \
                           , HasSuccs node                         \
                           , BiCastable     e edge                 \
                           , BiCastable     n node                 \
                           , MonadBuilder graph (m)                \
                           , HasProp Type       node               \
                           , HasProp TCData     node               \
                           , NodeInferable  (m) node               \
                           , TermNode Var   (m) node               \
                           , TermNode Lam   (m) node               \
                           , TermNode Unify (m) node               \
                           , TermNode Acc   (m) node               \
                           , TermNode Cons  (m) node               \
                           , MonadIdentPool (m)                    \
                           , Destructor     (m) (Ref Node node)    \
                           , Destructor     (m) (Ref Edge edge)    \
                           , MonadTypeCheck node (m)               \
                           , ReferencedM Node graph (m) node       \
                           , ReferencedM Edge graph (m) edge       \
                           )

-------------------------
-- === ResolutionT === --
-------------------------

class Monad m => MonadResolution r m | m -> r where
    resolve :: r -> m ()

newtype ResolutionT r m u = ResolutionT (EitherT r m u) deriving (Functor, Applicative, Monad, MonadFix, MonadIO, MonadTrans)
makeWrapped ''ResolutionT

-- === Utils === --

runResolutionT :: Monad m => ResolutionT r m u -> m (Resolution r u)
runResolutionT m = runEitherT (unwrap' m) >>= return ∘ \case
    Left  l -> Resolved   l
    Right r -> Unresolved r


---- === Instances === --

---- Show
deriving instance Show (Unwrapped (ResolutionT r m u)) => Show (ResolutionT r m u)

---- MonadResolution

instance Monad m => MonadResolution r (ResolutionT r m) where
    resolve = wrap' ∘ left
    {-# INLINE resolve #-}

data Resolution r u = Resolved   r
                    | Unresolved u
                    deriving (Show)





resolve_ = resolve []

resolveUnify :: forall m ls term node edge graph nodeRef n e c. (PassCtx(m,ls,term),
                MonadResolution [nodeRef] m)
             => nodeRef -> m ()
resolveUnify uni = do
    uni' <- read uni
    caseTest (uncover uni') $ do
        of' $ \(Unify lc rc) -> do
            l  <- follow source lc
            r  <- follow source rc

            resolveReflexivity uni l r
            symmetrical (resolveStar uni) l r
            symmetrical (resolveVar  uni) l r
            resolveCons uni l r
            resolveLams uni l r

        of' $ \ANY -> impossible

    where symmetrical f a b = f a b *> f b a

          resolveReflexivity uni a b = do
              if a == b
                  then do
                      replaceNode uni a
                      resolve_
                  else return ()

          resolveCons uni a b = do
              uni' <- read uni
              a'   <- read (a :: nodeRef)
              b'   <- read (b :: nodeRef)
              whenMatched (uncover a') $ \(Cons na argsA) ->
                  whenMatched (uncover b') $ \(Cons nb argsB) ->
                      if na == nb && length argsA == length argsB
                          then do
                              asA <- mapM (follow source . unlayer) argsA
                              asB <- mapM (follow source . unlayer) argsB
                              req <- mapM (follow source) =<< follow (prop TCData . requester) uni
                              newUnis <- zipWithM unify asA asB
                              mapM (flip (reconnect $ prop TCData . requester) req) newUnis
                              unified <- replaceAny a b
                              uniReplacement <- if null argsA
                                  then return unified
                                  else cons na (arg <$> newUnis)
                              replaceNode uni uniReplacement
                              resolve newUnis
                          else do
                              req <- mapM (follow source) =<< follow (prop TCData . requester) uni
                              case req of
                                  Just r  -> withRef r $ prop TCData . tcErrors %~ (UnificationError a b :)
                                  Nothing -> return ()

          resolveStar uni a b = do
              uni' <- read uni
              a'   <- read (a :: nodeRef)
              whenMatched (uncover a') $ \Lit.Star -> do
                  replaceNode uni b
                  resolve_

          resolveVar uni a b = do
              a'   <- read (a :: nodeRef)
              whenMatched (uncover a') $ \(Var v) -> do
                  replaceNode uni b
                  replaceNode a   b
                  resolve_

          resolveLams uni a b = do
              uni' <- read uni
              a'   <- read (a :: nodeRef)
              b'   <- read (b :: nodeRef)
              whenMatched (uncover a') $ \(Lam cargs cout) ->
                  whenMatched (uncover b') $ \(Lam cargs' cout') -> do
                    let cRawArgs  = unlayer <$> cargs
                    let cRawArgs' = unlayer <$> cargs'
                    args  <- mapM (follow source) (cout  : cRawArgs )
                    args' <- mapM (follow source) (cout' : cRawArgs')
                    if length args == length args'
                        then do
                            unis  <- zipWithM unify args args'
                            replaceNode uni a
                            replaceNode b   a
                            resolve unis
                        else return ()


replaceAny :: forall m ls term node edge graph nodeRef n e c. PassCtx(m,ls,term) => nodeRef -> nodeRef -> m nodeRef
replaceAny r1 r2 = do
    n1 <- read r1
    n2 <- read r2
    if size (n1 # Succs) > size (n2 # Succs)
        then replaceNode r2 r1 >> return r1
        else replaceNode r1 r2 >> return r2

replaceNode oldRef newRef = do
    oldNode <- read oldRef
    forM (readSuccs oldNode) $ \e -> do
        withRef e      $ source     .~ newRef
        withRef newRef $ prop Succs %~ add (unwrap e)
    destruct oldRef

whenMatched a f = caseTest a $ do
    of' f
    of' $ \ANY -> return ()


data TCStatus = TCStatus { _terms     :: Int
                         , _coercions :: Int
                         } deriving (Show)

makeLenses ''TCStatus

-- FIXME[WD]: we should not return [Graph n e] from pass - we should use ~ IterativePassRunner instead which will handle iterations by itself
run :: forall m ls term node edge graph nodeRef n e c.
       ( PassCtx(ResolutionT [nodeRef] m,ls,term)
       , MonadBuilder (Hetero (NEC.Graph n e c)) m
       ) => [nodeRef] -> m [Resolution [nodeRef] nodeRef]
run unis = forM unis $ \u -> fmap (resolveUnifyY u) $ runResolutionT $ resolveUnify u


universe = Ptr 0 -- FIXME [WD]: Implement it in safe way. Maybe "star" should always result in the top one?

---- FIXME[WD]: Change the implementation to list builder
--resolveUnifyX :: (PassCtx(ResolutionT [nodeRef] m,ls,term), nodeRef ~ Ref (Node $ (ls :<: term)), MonadIO m, Show (ls :<: term))
--              => nodeRef -> m [nodeRef]
--resolveUnifyX uni = (runResolutionT ∘ resolveUnify) uni >>= return ∘ \case
--    Resolved unis -> unis
--    Unresolved _  -> [uni]

resolveUnifyY uni = \case
    Resolved unis -> Resolved   unis
    Unresolved _  -> Unresolved uni


catUnresolved [] = []
catUnresolved (a : as) = ($ (catUnresolved as)) $ case a of
    Resolved   _ -> id
    Unresolved u -> (u :)

catResolved [] = []
catResolved (a : as) = ($ (catResolved as)) $ case a of
    Unresolved _ -> id
    Resolved   r -> (r :)


--------------------------
-- !!!!!!!!!!!!!!!!!!!! --
--------------------------

-- User - nody i inputy do funkcji bedace varami sa teraz zjadane, moze warto dac im specjalny typ?
-- pogadac z Marcinem o tym

-----------------------------
-- === TypeCheckerPass === --
-----------------------------

getRequesterDepth :: PassCtx(m, ls, term) => nodeRef -> m (Maybe Int)
getRequesterDepth ref = do
    req <- follow (prop TCData . requester) ref
    case req of
        Just e  -> follow source e >>= follow (prop TCData . depth)
        Nothing -> return Nothing

data UnificationPass = UnificationPass deriving (Show, Eq)

instance ( PassCtx(ResolutionT [nodeRef] m,ls,term)
         , MonadBuilder (Hetero (NEC.Graph n e c)) m
         , PassCtx(m, ls, term)
         , MonadTypeCheck (ls :<: term) m
         ) => TypeCheckerPass UnificationPass m where
    hasJobs _ = not . null . view TypeCheck.unresolvedUnis <$> TypeCheck.get

    runTCPass _ = do
        unis    <- view TypeCheck.unresolvedUnis <$> TypeCheck.get
        reqDeps <- mapM getRequesterDepth unis
        let sortedUnis = fmap snd $ sort $ zip reqDeps unis
        results <- run sortedUnis
        let newUnis = catUnresolved results ++ (concat $ catResolved results)
        TypeCheck.modify_ $ TypeCheck.unresolvedUnis .~ newUnis
        case catResolved results of
            [] -> return Stuck
            _  -> return Progressed



