{-# LANGUAGE UndecidableInstances #-}

module Luna.Pass.Manager where

import Luna.Prelude

import qualified Control.Monad.State as State
import           Control.Monad.State (StateT, evalStateT, runStateT)
import qualified Data.Map            as Map
import           Data.Map            (Map)
import           Data.Event          (Event, EventHub, Emitter, IsTag, Listener(Listener), toTag, attachListener, (//))
import qualified Data.Event          as Event

import Luna.IR.Internal.IR
import Luna.Pass.Class (IsPass, DynSubPass, SubPass, PassRep, DynPassTemplate, Proto)
import qualified Luna.Pass.Class as Pass

import qualified Prologue.Prim as Prim
import Data.TypeVal


data WorkingElem = WorkingElem deriving (Show)



-- | Constructor functions ::  t        -> Definition t -> m (LayerData UID t)
-- newtype ConsFunc m = ConsFunc (Prim.Any -> Prim.Any -> PMSubPass m Prim.Any)
-- newtype ConsFunc m = ConsFunc (Prim.Any -> Prim.Any -> PMPass m)
-- makeWrapped ''ConsFunc


-- type PMArgSubPass m = DynArgSubPass (PassManager m)
-- type PMArgPass    m = PMArgSubPass m ()

type PMSubPass m = DynSubPass (PassManager m)
type PMPass    m = PMSubPass m ()


-------------------
-- === State === --
-------------------

-- TODO: refactor -> Passes
-- VVV --
newtype PassProto_old m = PassProto_old { appCons :: ElemRep -> PMPass m } -- FIXME: should not refer to PMPass
instance Show (PassProto_old m) where show _ = "PassProto_old"
-- ^^^ --

data LayerReg m = LayerReg { _prototypes_old :: Map LayerRep $ PassProto_old m
                           , _prototypes     :: Map LayerRep $ Proto (Pass.Describbed (DynPassTemplate (PassManager m)))
                           , _attached       :: Map ElemRep  $ Map LayerRep $ PassRep
                           } deriving (Show)

data State m = State { _passes :: Map PassRep $ PMPass m
                     , _layers :: LayerReg m
                     , _events :: EventHub SortedListenerRep (Pass.Describbed (DynPassTemplate (PassManager m)))
                     , _attrs  :: Map AttrRep Prim.AnyData
                     , _events_old :: EventHub SortedListenerRep PassRep
                     } deriving (Show)


data SortedListenerRep = SortedListenerRep Int Event.ListenerRep deriving (Show, Eq)
instance Ord SortedListenerRep where
    compare (SortedListenerRep i r) (SortedListenerRep i' r') = if i == i' then compare r r' else compare i i'


-- === instances === --

instance Default (LayerReg m) where
    def = LayerReg def def def ; {-# INLINE def #-}

instance Default (State m) where
    def = State def def def def def ; {-# INLINE def #-}


--------------------------
-- === Pass Manager === --
--------------------------

-- === Definition === --

newtype PassManager m a = PassManager (StateT (State m) m a) deriving (Functor, Applicative, Monad, MonadIO, MonadFix, MonadThrow)

makeLenses  ''LayerReg
makeLenses  ''State
makeWrapped ''PassManager

type GetPassManager m = PassManager (GetBaseMonad m)

type family GetBaseMonad m where
    GetBaseMonad (PassManager m) = m
    GetBaseMonad (t m)           = GetBaseMonad m

type PMPass' m = PMPass (GetBaseMonad m)
type State'  m = State  (GetBaseMonad m)

class Monad m => MonadPassManager m where
    get :: m (State' m)
    put :: State' m -> m ()
    liftPassManager :: GetPassManager m a -> m a

instance Monad m => MonadPassManager (PassManager m) where
    get = wrap'   State.get ; {-# INLINE get #-}
    put = wrap' . State.put ; {-# INLINE put #-}
    liftPassManager = id

type TransBaseMonad t m = (GetBaseMonad m ~ GetBaseMonad (t m), Monad m, Monad (t m), MonadTrans t)
instance {-# OVERLAPPABLE #-} (MonadPassManager m, TransBaseMonad t m)
      => MonadPassManager (t m) where
    get = lift   get ; {-# INLINE get #-}
    put = lift . put ; {-# INLINE put #-}
    liftPassManager = lift . liftPassManager


modifyM :: MonadPassManager m => (State' m -> m (a, State' m)) -> m a
modifyM f = do
    s <- get
    (a, s') <- f s
    put s'
    return a
{-# INLINE modifyM #-}

modifyM_ :: MonadPassManager m => (State' m -> m (State' m)) -> m ()
modifyM_ = modifyM . fmap (fmap ((),)) ; {-# INLINE modifyM_ #-}

modify_ :: MonadPassManager m => (State' m -> State' m) -> m ()
modify_ = modifyM_ . fmap return ; {-# INLINE modify_ #-}


-- === Running === --

evalPassManager :: Monad m => PassManager m a -> State m -> m a
evalPassManager = evalStateT . unwrap' ; {-# INLINE evalPassManager #-}

evalPassManager' :: Monad m => PassManager m a -> m a
evalPassManager' = flip evalPassManager def ; {-# INLINE evalPassManager' #-}


-- === Utils === --

-- FIXME[WD]: pass manager should track pass deps so priority should be obsolete in the future!
attachLayerPM :: (MonadPassManager m, Functor (GetBaseMonad m)) => Int -> LayerRep -> ElemRep -> m ()
attachLayerPM priority l e = do
    s <- get
    let Just lcons = s ^. layers . prototypes_old . at l
        lpass = appCons lcons e
        s' = s & layers . attached . at e . non Map.empty . at l ?~ (lpass ^. Pass.desc . Pass.repr)
    put s'
    addEventListener priority (NEW // (e ^. asTypeRep)) lpass -- TODO
    -- TODO: register new available pass!
{-# INLINE attachLayerPM #-}

-- FIXME[WD]: make forall t. like security check for layers registration
registerLayer :: MonadPassManager m => LayerRep -> (TypeRep -> PMPass' m) -> m ()
registerLayer l f = modify_ $ layers . prototypes_old . at l ?~ PassProto_old f ; {-# INLINE registerLayer #-}

uncheckedAddLayerProto :: MonadPassManager m => LayerRep -> Proto (Pass.Describbed (DynPassTemplate (GetPassManager m))) -> m ()
uncheckedAddLayerProto l f = modify_ $ layers . prototypes . at l ?~ f ; {-# INLINE uncheckedAddLayerProto #-}

-- FIXME[WD]: pass manager should track pass deps so priority should be obsolete in the future!
attachLayerPM2 :: (MonadPassManager m, Functor (GetBaseMonad m))
               => Int -> LayerRep -> ElemRep -> m ()
attachLayerPM2 priority l e = do
    s <- get
    let Just pproto = s ^. layers . prototypes . at l
        dpass = Pass.specialize pproto e
        s' = s & layers . attached . at e . non Map.empty . at l ?~ (dpass ^. Pass.desc2 . Pass.repr)
    put s'
    addEventListener2 priority (NEW2 // (e ^. asTypeRep)) dpass -- TODO
    -- TODO: register new available pass!
{-# INLINE attachLayerPM2 #-}

queryListeners :: MonadPassManager m => Event.Tag -> m [PMPass' m]
queryListeners t = do
    s <- get
    let pss  = s ^. passes
        evs  = Event.queryListeners t $ s ^. events_old
        lsts = map (fromJust . flip Map.lookup pss) evs
        fromJust (Just a) = a
    return lsts

--

-- FIXME[WD]: pass manager should track pass deps so priority should be obsolete in the future!
addEventListener :: (MonadPassManager m, IsTag evnt, IsPass (GetPassManager m) p) => Int -> evnt -> p (GetPassManager m) a -> m ()
addEventListener priority evnt p = modify_ $ (events_old %~ attachListener (Listener (toTag evnt) $ SortedListenerRep priority $ switchRep rep) rep)
                                           . (passes %~ Map.insert rep cp)
    where cp  = Pass.compile $ Pass.dropResult p
          rep = cp ^. Pass.desc . Pass.repr
{-# INLINE addEventListener #-}

addEventListener2 :: (MonadPassManager m, IsTag evnt)
                  => Int -> evnt -> Pass.Describbed (DynPassTemplate (GetPassManager m)) -> m ()
addEventListener2 priority evnt p =  modify_ $ (events %~ attachListener (Listener (toTag evnt) $ SortedListenerRep priority $ switchRep rep) cp)
    where cp  = p -- Pass.compile $ Pass.dropResult p
          rep = cp ^. Pass.desc2 . Pass.repr
{-# INLINE addEventListener2 #-}


-- registerGenericLayer :: l -> (t -> Definition t -> m (LayerData UID t)) -> m ()
-- registerGenericLayer _


-- === Instances === --

-- Primitive
instance PrimMonad m => PrimMonad (PassManager m) where
    type PrimState (PassManager m) = PrimState m
    primitive = lift . primitive ; {-# INLINE primitive #-}

instance MonadTrans PassManager where
    lift = wrap' . lift ; {-# INLINE lift #-}





-- FIXME FIXME FIXME FIXME FIXME FIXME FIXME FIXME FIXME
-- | Emitter
-- FIXME[WD]: Is there any more performant way to evaluate events_old than having to set @WorkingElem before each emit?
type instance KeyData m (Event e) = GetPassManager m ()
instance (MonadPassManager m, Pass.ContainsKey (Event e) (Pass.Keys pass)) => Emitter (SubPass pass m) e where
    emit _ d = unsafeWithAttr (typeVal' @WorkingElem) d $ liftPassManager . unwrap' . view (Pass.findKey @(Event e)) =<< Pass.get

-- Here is an example stup of fixing implementation:
-- type instance KeyData m (Event e) = Event.Payload e -> GetPassManager m ()
-- instance (MonadPassManager m, Pass.ContainsKey (Event e) (Pass.Keys pass)) => Emitter (SubPass pass m) e where
--     emit _ d = unsafeWithAttr (typeVal' @WorkingElem) d $ liftPassManager . ($ d) . unwrap' . view (Pass.findKey @(Event e)) =<< Pass.get
-- FIXME FIXME FIXME FIXME FIXME FIXME FIXME FIXME FIXME

-- class Monad m => Emitter2 m a where
--     emit2 :: forall e. a ~ Abstract e => Proxy e -> Payload e -> m ()
--
-- instance Emitter2 (SubPass pass m) e where
--     emit2 _ p =

instance (MonadPassManager m, Typeable a) => KeyMonad (Attr a) m n where
    uncheckedLookupKey = fmap unsafeCoerce . (^? (attrs . ix (typeRep' @a))) <$> get ; {-# INLINE uncheckedLookupKey #-}


unsafeWriteAttr :: MonadPassManager m => AttrRep -> a -> m ()
unsafeWriteAttr r a = modify_ $ attrs %~ Map.insert r (unsafeCoerce a)

unsafeReadAttr :: MonadPassManager m => AttrRep -> m (Maybe Prim.AnyData)
unsafeReadAttr r = view (attrs . at r) <$> get

unsafeSetAttr :: MonadPassManager m => AttrRep -> Maybe Prim.AnyData -> m ()
unsafeSetAttr r a = modify_ $ attrs . at r .~ a

unsafeDeleteAttr :: MonadPassManager m => AttrRep -> m ()
unsafeDeleteAttr r = modify_ $ attrs %~ Map.delete r

unsafeWithAttr :: MonadPassManager m => AttrRep -> a -> m t -> m t
unsafeWithAttr r a f = do
    oldAttr <- unsafeReadAttr r
    unsafeWriteAttr r a
    out <- f
    unsafeSetAttr r oldAttr
    return out
