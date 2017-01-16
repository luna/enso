{-# LANGUAGE OverloadedStrings #-}

module Luna.IR.Repr.Styles where

import Luna.Prelude


-- === Definitions === --

data Simple         = Simple     deriving (Show)
data HeaderOnly     = HeaderOnly deriving (Show)
data StaticNameOnly = StaticNameOnly deriving (Show)


-- === Default instances === --

instance {-# OVERLAPPABLE #-} Repr StaticNameOnly a where repr = const ""
