{-# LANGUAGE UndecidableInstances #-}

module Luna.IR.Layer.Class where

import Luna.Prelude


--------------------
-- === Layers === --
--------------------

-- === Definition === --

type family LayerData l t

newtype     Layer  t l = Layer (LayerData l t)
type family Layers q a :: [*]

makeWrapped ''Layer

type family Definition a


-- === Classes === --

class Monad m => LayerCons l m where
    consLayer :: forall t. Definition t -> m (Layer t l)


-- === Isntances === --

deriving instance Show (Unwrapped (Layer t l))
      => Show (Layer t l)

instance Default (Unwrapped (Layer t l))
      => Default (Layer t l) where def = wrap' def ; {-# INLINE def #-}
