{-# LANGUAGE UndecidableInstances #-}

module Luna.Pass.Class where

import Luna.Prelude hiding (head, tail, elem)

import           Data.RTuple (List)
import qualified Data.RTuple as List

import qualified Control.Monad.Catch      as Catch
import           Control.Monad.Fix
import qualified Control.Monad.State      as State
import           Control.Monad.State      (StateT)
import           Control.Monad.Primitive

import           Luna.IR.Internal.IR   (Key, IRMonad, IsIdx, Readable, Writable, getKey, putKey, KeyReadError, KeyMissingError)
import qualified Luna.IR.Internal.IR   as IR
import           Luna.IR.Term.Layout.Class (Abstract)
import           Type.Maybe                (FromJust)

import Luna.IR.Layer
import Type.List (In)




---------------------
-- === KeyList === --
---------------------

newtype KeyList  s lst = KeyList (List (Key s <$> lst))
type    KeyListM m     = KeyList (PrimState m)
makeWrapped ''KeyList


prepend :: Key s k -> KeyList s ks -> KeyList s (k ': ks)
prepend k = wrapped %~ List.prepend k ; {-# INLINE prepend #-}

-- | FIXME[WD]: tail cannot be constructed as wrapped . List.tail . Why?
tail :: Lens' (KeyList s (k ': ks)) (KeyList s ks)
tail = lens (wrapped %~ (view List.tail)) $ flip (\lst -> wrapped %~ (List.tail .~ unwrap' lst)) ; {-# INLINE tail #-}

head :: Lens' (KeyList s (k ': ks)) (Key s k)
head = wrapped . List.head ; {-# INLINE head #-}



-------------------------------


-- === Properties === --

type family Inputs    pass :: [*]
type family Outputs   pass :: [*]
type family Preserves pass :: [*]


-- === Data declarations ===

type    Pass    pass m   = SubPass pass m ()
newtype SubPass pass m a = SubPass (StateT (StateM m pass) m a)
        deriving ( Functor, Monad, Applicative, MonadIO, MonadPlus, Alternative
                 , MonadFix, Catch.MonadMask
                 , Catch.MonadCatch, Catch.MonadThrow)

type KeyTypes   pass = Inputs pass <> Outputs pass -- FIXME (there are duplicates in the list)
type Keys       pass = KeyTypes pass
type State    s pass = KeyList s (KeyTypes pass)
type StateM   m pass = State (PrimState m) pass

type        GetState m = StateM m (GetPass m)
type family GetPass  m where
    GetPass (SubPass pass m) = pass
    GetPass (t m)          = GetPass m

makeWrapped ''SubPass


-- === Utils ===

initPass :: (LookupKeys n (Keys pass), Monad m, PrimState m ~ PrimState n) => SubPass pass m a -> n (Either Err (m a))
initPass p = return . fmap (State.evalStateT (unwrap' p)) =<< lookupKeys ; {-# INLINE initPass #-}

eval :: LookupKeys m (Keys pass) => SubPass pass m a -> m (Either Err a)
eval = join . fmap sequence . initPass ; {-# INLINE eval #-}


-- === Keys lookup === --


data Err = Err TypeRep deriving (Show)

type ReLookupKeys k m ks = (IR.KeyMonad k m, LookupKeys m ks, Typeable k)
class    Monad m             => LookupKeys m keys      where lookupKeys :: m (Either Err (KeyListM m keys))
instance Monad m             => LookupKeys m '[]       where lookupKeys = return $ return (wrap' List.empty)
instance ReLookupKeys k m ks => LookupKeys m (k ': ks) where lookupKeys = prepend <<$>> (justErr (Err $ typeRep (Proxy :: Proxy k)) <$> IR.uncheckedLookupKey)
                                                                                  <<*>> lookupKeys


infixl 4 <<*>>
(<<*>>) :: (Applicative f, Applicative g) => f (g (a -> b)) -> f (g a) -> f (g b)
(<<*>>) = (<*>) . fmap (<*>) ; {-# INLINE (<<*>>) #-}



-- === MonadPass === --

class Monad m => MonadPass m where
    get :: m (GetState m)
    put :: GetState m -> m ()

instance Monad m => MonadPass (SubPass pass m) where
    get = wrap'   State.get ; {-# INLINE get #-}
    put = wrap' . State.put ; {-# INLINE put #-}

instance {-# OVERLAPPABLE #-} (MonadPass m, MonadTrans t, Monad (t m),GetState m ~ GetState (t m)) => MonadPass (t m) where
    get = lift   get ; {-# INLINE get #-}
    put = lift . put ; {-# INLINE put #-}

modifyM :: MonadPass m => (GetState m -> m (a, GetState m)) -> m a
modifyM f = do
    s       <- get
    (a, s') <- f s
    put s'
    return a
{-# INLINE modifyM #-}

modifyM_ :: MonadPass m => (GetState m -> m (GetState m)) -> m ()
modifyM_ = modifyM . fmap (fmap ((),)) ; {-# INLINE modifyM_ #-}

modify :: MonadPass m => (GetState m -> (a, GetState m)) -> m a
modify = modifyM . fmap return ; {-# INLINE modify #-}

modify_ :: MonadPass m => (GetState m -> GetState m) -> m ()
modify_ = modifyM_ . fmap return ; {-# INLINE modify_ #-}

with :: MonadPass m => (GetState m -> GetState m) -> m a -> m a
with f m = do
    s <- get
    put $ f s
    out <- m
    put s
    return out
{-# INLINE with #-}



-- === Instances === --

-- MonadTrans
instance MonadTrans (SubPass pass) where
    lift = SubPass . lift ; {-# INLINE lift #-}

-- Transformats
instance State.MonadState s m => State.MonadState s (SubPass pass m) where
    get = wrap' $ lift   State.get ; {-# INLINE get #-}
    put = wrap' . lift . State.put ; {-# INLINE put #-}

-- Primitive
instance PrimMonad m => PrimMonad (SubPass pass m) where
    type PrimState (SubPass pass m) = PrimState m
    primitive = lift . primitive
    {-# INLINE primitive #-}


-- <-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<-<


-- Readable
instance ( Monad m
         , ContainsKey k (Keys pass)
         , Assert (k `In` (Inputs pass)) (KeyReadError k))
      => Readable k (SubPass pass m) where getKey = view findKey <$> get ; {-# INLINE getKey #-}

-- Writable
instance ( Monad m
         , ContainsKey k (Keys pass)
         , Assert (k `In` (Inputs pass)) (KeyReadError k))
      => Writable k (SubPass pass m) where putKey k = modify_ (findKey .~ k) ; {-# INLINE putKey #-}


-- === ContainsKey === --

class                                     ContainsKey k ls        where findKey :: Lens' (KeyList s ls) (Key s k)
instance {-# OVERLAPPING #-}              ContainsKey k (k ': ls) where findKey = head           ; {-# INLINE findKey #-}
instance ContainsKey k ls              => ContainsKey k (l ': ls) where findKey = tail . findKey ; {-# INLINE findKey #-}
instance TypeError (KeyMissingError k) => ContainsKey k '[]       where findKey = impossible     ; {-# INLINE findKey #-}
