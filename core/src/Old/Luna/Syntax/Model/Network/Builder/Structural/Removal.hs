module Old.Luna.Syntax.Model.Network.Builder.Structural.Removal where

import           Luna.Prelude

import           Data.Layer_OLD.Cover_OLD
import           Data.Container (add)
import           Old.Data.Prop
import           Old.Data.Graph.Builder
import           Old.Luna.Syntax.Model.Network.Term
import           Old.Luna.Syntax.Model.Layer
import           Old.Luna.Syntax.Model.Network.Builder.Layer (HasSuccs, readSuccs)
import           Old.Luna.Runtime.Dynamics (Static)
import           Old.Data.Graph             hiding (add, remove)
import qualified Old.Data.Graph.Backend.NEC as NEC

replaceNode :: ( term  ~ Draft Static
               , node  ~ (ls :<: term)
               , edge  ~ Link node
               , graph ~ Hetero (NEC.Graph n e c)
               , Covered node
               , HasSuccs node
               , IsoCastable e edge
               , IsoCastable n node
               , MonadBuilder graph m
               , Destructor m (Ref Node node)
               , Destructor m (Ref Edge edge)
               , ReferencedM Node graph m node
               , ReferencedM Edge graph m edge
               ) => Ref Node node -> Ref Node node -> m ()
replaceNode oldRef newRef = do
    oldNode <- read oldRef
    forM_ (readSuccs oldNode) $ \e -> do
        withRef e $ source .~ newRef
        withRef newRef $ prop Succs %~ add (unwrap e)
    destruct oldRef

replaceNodeNonDestructive :: ( term  ~ Draft Static
                             , node  ~ (ls :<: term)
                             , edge  ~ Link node
                             , graph ~ Hetero (NEC.Graph n e c)
                             , Covered node
                             , HasSuccs node
                             , IsoCastable e edge
                             , IsoCastable n node
                             , MonadBuilder graph m
                             , Destructor m (Ref Node node)
                             , Destructor m (Ref Edge edge)
                             , ReferencedM Node graph m node
                             , ReferencedM Edge graph m edge
                             ) => Ref Node node -> Ref Node node -> m ()
replaceNodeNonDestructive oldRef newRef = do
    oldNode <- read oldRef
    forM_ (readSuccs oldNode) $ \e -> do
        withRef e      $ source .~ newRef
        withRef newRef $ prop Succs %~ add (unwrap e)
    withRef oldRef $ prop Succs .~ fromList []
