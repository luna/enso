{-# LANGUAGE CPP                       #-}

module Luna.Compilation.Pass.Interpreter.Interpreter where

import           Prologue                                        hiding (Getter, Setter, pre, read, succ, ( # ))

import           Control.Monad                                   (forM_)
import           Control.Monad.Event                             (Dispatcher)
import           Control.Monad.Trans.Identity
import           Control.Monad.Trans.State
import           Data.Maybe                                      (isNothing)

import           Data.Construction
import           Data.Graph
import           Data.Graph.Backend.VectorGraph                  hiding (source, target)
import           Data.Graph.Builder                              hiding (get)
import qualified Data.IntSet                                     as IntSet
import           Data.Prop
import           Data.Record                                     hiding (cons)
import           Development.Placeholders

import           Luna.Compilation.Pass.Interpreter.Class         (InterpreterMonad, InterpreterT, runInterpreterT)
import           Luna.Compilation.Pass.Interpreter.Env           (Env)
import qualified Luna.Compilation.Pass.Interpreter.Env           as Env
import           Luna.Compilation.Pass.Interpreter.Layer         (InterpreterData (..), InterpreterLayer)
import qualified Luna.Compilation.Pass.Interpreter.Layer         as Layer

import           Luna.Evaluation.Runtime                         (Dynamic, Static)
import           Luna.Syntax.AST.Term                            (Lam (..), Acc (..), App (..), Native (..), Blank (..), Unify (..), Var (..), Cons (..))
import           Luna.Syntax.Model.Network.Builder               (redirect)
import           Luna.Syntax.Builder
import           Luna.Syntax.Model.Layer
import           Luna.Syntax.Model.Network.Builder.Node          (NodeInferable, TermNode)
import           Luna.Syntax.Model.Network.Builder.Node.Inferred
import           Luna.Syntax.Model.Network.Term
import qualified Luna.Syntax.AST.Lit                             as Lit

import           Type.Inference

-- import qualified Luna.Library.StdLib                             as StdLib

import           Luna.Syntax.AST.Arg                             (Arg)
import qualified Luna.Syntax.AST.Arg                             as Arg

import qualified Luna.Evaluation.Session                         as Session

import           GHC.Prim                                        (Any)

import           Control.Monad.Catch                             (MonadCatch, MonadMask, catchAll)
import           Control.Monad.Ghc                               (GhcT)
import           Language.Haskell.Session                        (GhcMonad)
import qualified Language.Haskell.Session                        as HS

import           Data.Digits                                     (unDigits, digits)
import           Data.Ratio




convertBase :: Integral a => a -> a -> a
convertBase radix = unDigits radix . digits 10



convertRationalBase :: Integer -> Rational -> Rational
convertRationalBase radix rational = nom % den where
    nom = convertBase radix (numerator   rational)
    den = convertBase radix (denominator rational)

numberToAny :: Lit.Number -> Any
numberToAny (Lit.Number radix (Lit.Rational r)) = Session.toAny $ convertRationalBase (toInteger radix) r
numberToAny (Lit.Number radix (Lit.Integer  i)) = Session.toAny $ convertBase         (toInteger radix) i

#define InterpreterCtx(m, ls, term) ( ls   ~ NetLayers                                         \
                                    , term ~ Draft Static                                      \
                                    , ne   ~ Link (ls :<: term)                                \
                                    , BiCastable e ne                                          \
                                    , BiCastable n (ls :<: term)                               \
                                    , MonadIO (m)                                              \
                                    , MonadBuilder (Hetero (VectorGraph n e c)) (m)            \
                                    , NodeInferable (m) (ls :<: term)                          \
                                    , TermNode Lam  (m) (ls :<: term)                          \
                                    , HasProp InterpreterData (ls :<: term)                    \
                                    , Prop    InterpreterData (ls :<: term) ~ InterpreterLayer \
                                    , InterpreterMonad (Env (Ref Node (ls :<: term))) (m)      \
                                    , MonadMask (m)                                            \
                                    )



pre :: InterpreterCtx(m, ls, term) => Ref Node (ls :<: term) -> m [Ref Node (ls :<: term)]
pre ref = do
    node <- read ref
    mapM (follow source) $ node # Inputs

succ :: InterpreterCtx(m, ls, term) => Ref Node (ls :<: term) -> m [Ref Node (ls :<: term)]
succ ref = do
    node <- read ref
    mapM (follow target) $ node # Succs

isDirty :: (Prop InterpreterData n ~ InterpreterLayer, HasProp InterpreterData n) => n -> Bool
isDirty node = (node # InterpreterData) ^. Layer.dirty

isRequired :: (Prop InterpreterData n ~ InterpreterLayer, HasProp InterpreterData n) => n -> Bool
isRequired node = (node # InterpreterData) ^. Layer.required

markDirty :: InterpreterCtx(m, ls, term) => Ref Node (ls :<: term) -> m ()
markDirty ref = do
    node <- read ref
    write ref (node & prop InterpreterData . Layer.dirty .~ True)

setValue :: InterpreterCtx(m, ls, term) => Maybe Any -> Ref Node (ls :<: term) -> m ()
setValue val ref = do
    node <- read ref
    write ref (node & prop InterpreterData . Layer.value .~ val
                    & prop InterpreterData . Layer.dirty .~ isNothing val
              )
    valueString <- getValueString ref
    displayValue ref
    updNode <- read ref
    write ref $ updNode & prop InterpreterData . Layer.debug .~ valueString

getValue :: InterpreterCtx(m, ls, term) => Ref Node (ls :<: term) -> m (Maybe Any)
getValue ref = do
    node <- read ref
    return $ (node # InterpreterData) ^. Layer.value

--- sandbox


markSuccessors :: InterpreterCtx(m, ls, term) => Ref Node (ls :<: term) -> m ()
markSuccessors ref = do
    node <- read ref
    -- putStrLn $         "markSuccessors " <> show ref
    unless (isDirty node) $ do
        -- putStrLn $     "marking dirty  " <> show ref
        markDirty ref
        when (isRequired node) $ do
            -- putStrLn $ "addReqNode     " <> show ref
            Env.addNodeToEval ref
            mapM_ markSuccessors =<< succ ref

-- handler

nodesToExecute :: InterpreterCtx(m, ls, term) =>  m [Ref Node (ls :<: term)]
nodesToExecute = do
    mapM_ collectNodesToEval =<< Env.getNodesToEval
    Env.getNodesToEval

reset :: InterpreterMonad (Env node) m => m ()
reset = Env.clearNodesToEval

connect :: InterpreterCtx(m, ls, term) => Ref Node (ls :<: term) -> Ref Node (ls :<: term) -> m ()
connect prev next = do
    nd <- read prev
    isPrevDirty <- isDirty <$> read prev
    markSuccessors $ if isPrevDirty
        then prev
        else next

markModified :: InterpreterCtx(m, ls, term) => Ref Node (ls :<: term) -> m ()
markModified = markSuccessors


-- interpreter


unpackArguments :: InterpreterCtx(m, ls, term) => [Arg (Ref Edge (Link (ls :<: term)))] -> m [Ref Node (ls :<: term)]
unpackArguments args = mapM (follow source . Arg.__val_) args


argumentValue :: InterpreterCtx(m, ls, term) => Ref Node (ls :<: term) -> m Any
argumentValue ref = do
    node <- read ref
    return $ fromJust $ (node # InterpreterData) ^. Layer.value

argumentsValues :: InterpreterCtx(m, ls, term) => [Ref Node (ls :<: term)] -> m [Any]
argumentsValues refs = mapM argumentValue refs

collectNodesToEval :: InterpreterCtx(m, ls, term) => Ref Node (ls :<: term) -> m ()
collectNodesToEval ref = do
    Env.addNodeToEval ref
    prevs <- pre ref
    forM_ prevs $ \p -> do
        whenM (isDirty <$> read p) $
            collectNodesToEval p


-- ref

-- node

-- node # Tc


getValueString :: InterpreterCtx(m, ls, term) => Ref Node (ls :<: term) -> m String
getValueString ref = do
    typeName <- getTypeName ref
    value <- getValue ref
    return $ case value of
                Nothing  -> ""
                Just val -> if typeName == "String"
                               then show ((Session.unsafeCast val) :: String)
                               else (if typeName == "Int"
                                   then show ((Session.unsafeCast val) :: Integer)
                                   else "unknown type")

displayValue :: InterpreterCtx(m, ls, term) => Ref Node (ls :<: term) -> m ()
displayValue ref = do
    typeName <- getTypeName ref
    valueString <- getValueString ref
    putStrLn $ "Type " <> typeName <> " value " <> valueString


getTypeName :: InterpreterCtx(m, ls, term) => Ref Node (ls :<: term) -> m String
getTypeName ref = do
    node  <- read ref
    tpRef <- follow source $ node # Type
    tp    <- read tpRef
    caseTest (uncover tp) $ do
        of' $ \(Cons (Lit.String s)) -> return s
        of' $ \ANY                   -> error "Ambiguous node type"


-- run :: (MonadIO m, MonadMask m, Functor m) => GhcT m a -> m a

evaluateNode :: (InterpreterCtx(m, ls, term), HS.SessionMonad (GhcT m)) => Ref Node (ls :<: term) -> m ()
evaluateNode ref = do
    node <- read ref
    putStrLn $ "evaluating " <> show ref
    case (node # TCData) ^. redirect of
        Just redirect -> do
            redirRef <- (follow source) redirect
            putStrLn $ "redirecting to " <> show redirRef
            evaluateNode redirRef
            value <- getValue redirRef
            setValue value ref
            return ()
        Nothing -> do
            caseTest (uncover node) $ do
                of' $ \(Unify l r)  -> return ()
                of' $ \(Acc n t)    -> return ()
                of' $ \(Var n)      -> return ()
                of' $ \(App f args) -> do
                    funRep       <- follow source f
                    unpackedArgs <- unpackArguments args
                    funNode      <- read funRep
                    name         <- caseTest (uncover funNode) $ do
                        of' $ \(Lit.String name) -> return name
                        of' $ \ANY               -> return "function name not a string"
                    putStrLn $ "App " <> show funRep <> " (" <> name <> ") " <> show unpackedArgs
                    -- values <- argumentsValues unpackedArgs
                    return ()
                of' $ \(Native nameStr argsEdges) -> do
                    -- let tpString = (intercalate " -> " $ snd <$> values) <> " -> " <> outType
                    let tpString = "Int -> Int -> Int"
                    let name = unwrap' nameStr
                    args   <- mapM (follow source) argsEdges
                    values <- argumentsValues args
                    -- putStrLn $ "Native " <> name <> " " <> show values
                    res <- flip catchAll (\e -> do putStrLn $ show e; return $ Session.toAny False) $ HS.run $ do
                        HS.setImports Session.defaultImports
                        fun <- Session.findSymbol name tpString
                        let res = foldl Session.appArg fun $ Session.toAny <$> values
                        -- let res = Session.toAny 0
                        return res
                    let value = ((Session.unsafeCast res) :: Int)
                    putStrLn $ "res " <> show value
                    setValue (Just res) ref
                    return ()
                of' $ \(Lit.String str)                 -> do
                    setValue (Just $ Session.toAny str) ref
                of' $ \number@(Lit.Number radix system) -> do
                    putStrLn $ "Setting number value with radix " <> show radix <> " system " <> show system
                    let Lit.Integer i = system
                    let res = convertBase         (toInteger radix) i
                    putStrLn $ "Converted " <> show res
                    let anyy = (numberToAny number)
                    let unannyy = ((Session.unsafeCast anyy) :: Integer)
                    putStrLn $ "Unannyy " <> show unannyy

                    setValue (Just $ numberToAny number) ref
                of' $ \Blank -> return ()
                of' $ \ANY   -> return ()
    return ()

evaluateNodes :: InterpreterCtx(m, ls, term) => [Ref Node (ls :<: term)] -> m ()
evaluateNodes reqRefs = do
    mapM_ collectNodesToEval reqRefs
    mapM_ evaluateNode =<< Env.getNodesToEval


#define PassCtx(m, ls, term) ( ls   ~ NetLayers                                         \
                             , term ~ Draft Static                                      \
                             , ne   ~ Link (ls :<: term)                                \
                             , BiCastable e ne                                          \
                             , BiCastable n (ls :<: term)                               \
                             , MonadIO (m)                                              \
                             , MonadBuilder ((Hetero (VectorGraph n e c))) (m)          \
                             , NodeInferable (m) (ls :<: term)                          \
                             , TermNode Lam  (m) (ls :<: term)                          \
                             , MonadFix (m)                                             \
                             , HasProp InterpreterData (ls :<: term)                    \
                             , Prop    InterpreterData (ls :<: term) ~ InterpreterLayer \
                             , MonadMask (m)                                            \
                             )

run :: forall env m ls term ne n e c. (PassCtx(InterpreterT env m, ls, term), MonadIO m, MonadFix m, env ~ Env (Ref Node (ls :<: term)))
    => [Ref Node (ls :<: term)] -> m ()
run reqRefs = do
    -- putStrLn $ "g " <> show g
    putStrLn $ "reqRefs " <> show reqRefs
    -- ((), env) <- flip runInterpreterT (def :: env) $ collectNodesToEval (head reqRefs) runStateT
    ((), env) <- flip runInterpreterT (def :: env) $ evaluateNodes reqRefs
    putStrLn $ "env " <> show env

    -- putStrLn $ show StdLib.symbols

    return ()
