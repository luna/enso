{-# LANGUAGE NoMonomorphismRestriction #-}

module Luna.Syntax.Model.Network.Builder.Node (module Luna.Syntax.Model.Network.Builder.Node, module X) where

import Luna.Syntax.Model.Network.Builder.Node.Class as X
import qualified Luna.Syntax.Model.Network.Builder.Node.Inferred as Inf


star'   = Inf.star
str'    = Inf.str
int'    = Inf.int
double' = Inf.double
cons'   = Inf.cons
lam'    = Inf.lam
acc'    = Inf.acc
app'    = Inf.app
var'    = Inf.var
unify'  = Inf.unify
match'  = Inf.match
blank'  = Inf.blank

