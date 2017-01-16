{-# LANGUAGE UndecidableInstances #-}

module Old.Data.Graph.Type.Hetero (module X) where

import Prologue hiding (Getter, Setter)

import Data.Container.Hetero as X (Hetero(..))
import Old.Data.Prop
import Old.Data.Graph.Model.Pointer
import Old.Data.Graph.Type.Dynamic


-- === Instances === --

-- Hetero reference handling

-- | When referencing the Hetero graph, we query the underlying one for its native node and edge representations
--   by using the focus' function.

--instance (Referred r a n', BiCastable n n', n' ~ (a # r))
--      =>  Referred r (Hetero a) n where focus r = wrapped' ∘ focus' (retarget r) ∘ casted ; {-# INLINE focus #-}
--instance  Referred I (Hetero a) n where focus   = impossible
--instance  Referred r (Hetero a) I where focus   = impossible
--instance  Referred r (Hetero I) n where focus   = impossible


instance (LocatedM t g m, IsoCastable a (g # t), Functor m) => ReferencedM t (Hetero g) m a where
    writeRefM ptr val = wrapped' $ writeLocM (retarget ptr) (cast val) ; {-# INLINE writeRefM #-}
    readRefM  ptr     = cast <∘> readLocM (retarget ptr) ∘ unwrap'     ; {-# INLINE readRefM  #-}


-- Dynamic

instance (Monad m, Castable (g # t) (g # t), DynamicM' t g m) => DynamicM' t (Hetero g) m
instance (Monad m, DynamicM' t g m, Castable a (g # t))       => DynamicM  t (Hetero g) m a where
    addM a (Hetero g) = Hetero <<$>> (addM' (cast a) g <&> _1 %~ retarget) ; {-# INLINE addM    #-}
    removeM           = mapM ∘ removeM' ∘ retarget                         ; {-# INLINE removeM #-}
