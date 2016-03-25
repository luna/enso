{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE RankNTypes #-}

module Data.Graph.Backend.NEC where

import Prologue                 hiding (Getter, Setter)
import Prologue.Unsafe

import qualified Data.Container as Cont
import           Data.Container (Store, HasStore, HasStores, store, unchecked, inplace, ixed)
import           Data.AutoVector

import Data.Prop
import Data.Container.Auto      (Auto)
import Data.Container.Resizable (Exponential)
import Data.Index
import Data.Vector              (Vector)
import Data.Vector.Mutable      (MVector)

import Data.Graph
import Data.Graph.Backend.SubGraph ()


-----------------
-- === NEC === --
-----------------

-- === Definition === --

type NEC' cont v e c = NEC (cont v) (cont e) (cont c)
data NEC nodes edges clusters = NEC { __nodeStore_    :: !nodes
                                    , __edgeStore_    :: !edges
                                    , __clusterStore_ :: !clusters
                                    } deriving (Generic, Show)
makeLenses  ''NEC


-- === Utils === --

nec :: HasStores '[Node, Edge, Cluster] a => Lens' a (NEC (Store Node a) (Store Edge a) (Store Cluster a))
nec = lens (\a -> NEC (a ^. nodeStore) (a ^. edgeStore) (a ^. clusterStore)) (\a (NEC n e c) -> a & nodeStore .~ n & edgeStore .~ e & clusterStore .~ c)


-- === Instances === --

-- Primitive

instance Defaults '[n,e,c] => Default (NEC n e c) where def                                = NEC def def def                   ; {-# INLINE def     #-}
instance Monoids  '[n,e,c] => Monoid  (NEC n e c) where mempty                             = NEC mempty mempty mempty          ; {-# INLINE mempty  #-}
                                                        mappend (NEC n e c) (NEC n' e' c') = NEC (n <> n') (e <> e') (c <> c') ; {-# INLINE mappend #-}

-- Store

type instance Store Node    (NEC n e c) = n
type instance Store Edge    (NEC n e c) = e
type instance Store Cluster (NEC n e c) = c

instance HasStore Node    (NEC n e c) where store _ = _nodeStore_
instance HasStore Edge    (NEC n e c) where store _ = _edgeStore_
instance HasStore Cluster (NEC n e c) where store _ = _clusterStore_

-- Normal Form

instance NFDatas '[v,e,c] => NFData (NEC v e c)



-------------------
-- === Graph === --
-------------------

newtype Graph    n e c =  Graph (NEC' ( AutoVector  ) n e c) deriving (Generic, Show)
newtype MGraph s n e c = MGraph (NEC' (MAutoVector s) n e c) deriving (Generic)
makeWrapped ''Graph
makeWrapped ''MGraph


-- === Instances === --

instance Default (Graph n e c) where def = Graph $ NEC (Cont.alloc 100) (Cont.alloc 100) (Cont.alloc 100)

-- Normal Form

instance (NFData (Unwrapped (Graph n e c))) => NFData (Graph n e c)

-- Store

type instance Store t (Graph n e c) = AutoVector (Graph n e c # t)
instance (HasStore t cont, Store t cont ~ Store t (Graph n e c), cont ~ Unwrapped (Graph n e c))
      => HasStore t (Graph n e c) where store p = wrapped' ∘ store p ; {-# INLINE store #-}

-- Construction

type instance Prop Node    (Graph n e c) = n
type instance Prop Edge    (Graph n e c) = e
type instance Prop Cluster (Graph n e c) = c

-- Dynamic implementation

instance (g ~ Graph n e c, HasStore t g, a ~ (g # t)) => Dynamic  t (Graph n e c) a
instance (g ~ Graph n e c, HasStore t g)              => Dynamic' t (Graph n e c) where
    add'    el  = store (p :: P t) $ swap ∘ fmap Ref ∘ ixed Cont.add el ; {-# INLINE add'    #-}
    remove' ref = store (p :: P t) %~ Cont.free (ref ^. idx)            ; {-# INLINE remove' #-}

-- References handling

instance (g ~ (Graph n e c), r ~ (g # t), HasStore t g) => Referred t (Graph n e c) r where
    focus r = lens getter setter where
        getter g     = Cont.index_ (r ^. idx) $ g ^. store (p :: P t)                          ; {-# INLINE getter #-}
        setter g val = g & (store (p :: P t)) %~ unchecked inplace Cont.insert_ (r ^. idx) val ; {-# INLINE setter #-}
    {-# INLINE focus #-}
