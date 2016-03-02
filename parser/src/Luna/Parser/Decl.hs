{-# LANGUAGE NoMonomorphismRestriction #-}

module Luna.Parser.Decl where

import Prelude.Luna hiding (cons, maybe, noneOf)

import           Text.Parser.Combinators
import qualified Luna.Parser.Token        as Tok
--import qualified Luna.Syntax.Decl         as Decl
import qualified Luna.Parser.Indent       as Indent
import           Luna.Parser.Combinators  (many1, maybe, applyAll)
import qualified Luna.Parser.Type         as Type
import Luna.Syntax.AST.Decl.Function
--import           Luna.Syntax.Foreign      (Foreign(Foreign))
--import qualified Luna.Syntax.Foreign      as Foreign
--import           Luna.Syntax.Name.Pattern (NamePat(NamePat), Segment(Segment))
--import qualified Luna.Syntax.Name.Pattern as NamePat
--import           Luna.Syntax.Arg          (Arg(Arg))
--import           Luna.Parser.Builder      (qualifiedPath)
--import           Luna.Syntax.Name         (tvname)
--import           Luna.Parser.Pattern      (argPattern)
--import qualified Luna.Syntax.Pragma       as Pragma
--import qualified Luna.System.Pragma.Store as Pragma

--import Luna.Parser.Struct (blockBeginFields, blockBodyOpt, blockBody', blockEnd, blockStart, blockBegin)


--import           Text.Parser.Char (char, alphaNum, spaces, noneOf)


------- Imports -----

--imp = Decl.Imp <$> impDecl

--impDecl = Tok.kwImport *> choice [try declImp, modImp] <?> "import declaration"

--impPath = qualifiedPath Tok.typeIdent <?> "import path"

--modImp = Decl.ModImp <$> impPath
--                     <*> ((Just <$ Tok.kwAs <*> Tok.typeIdent) <|> pure Nothing <?> "module renaming")
--                     <?> "module import"

--declImp = Decl.DeclImp <$> impPath
--                       <*> blockBegin importTarget
--                       <?> "declaration import"

--importTarget =   Tok.importAll *> (pure $ Decl.Wildcard [])
--             <|> body Decl.ImpVar Tok.varOp
--             <|> body Decl.ImpType Tok.typeIdent
--             <?> "import declaration"
--             where body c p = c <$> p <*> ((Just <$ Tok.kwAs <*> p) <|> pure Nothing)


------- pragmas ------

--pragma = do
--    Tok.pragma
--    pType <- pragmaTypes
--    name  <- pragmaName
--    Pragma.parseByName name
--    pure $ Decl.Pragma (pType name)

--pragmaEnable  = Pragma.Enable  <$ Tok.pragmaEnable
--pragmaDisable = Pragma.Disable <$ Tok.pragmaDisable
--pragmaPush    = Pragma.Push    <$ Tok.pragmaPush
--pragmaPop     = Pragma.Pop     <$ Tok.pragmaPop

--pragmaTypes = choice [ pragmaEnable, pragmaDisable, pragmaPush, pragmaPop ]

--pragmaName = do
--    names <- Pragma.pragmaNames
--    foldl (<|>) (fail "Undefined pragma name") $ fmap Tok.symbol names

----switchPragma

------- type aliases ------

--typeAlias = Decl.TpAls <$  Tok.kwAlias
--                       <*> (typic <?> "new type")
--                       <*  Tok.assignment
--                       <*> (typic <?> "base type")
--                       <?> "type alias"


------- type wrappers ------

--typeWrapper = Decl.TpWrp <$  Tok.kwType
--                         <*> (typic <?> "new type")
--                         <*  Tok.assignment
--                         <*> (typic <?> "base type")
--                         <?> "type wrapper"



-- === Functions === --

--data Pattern a = Pattern [ArgDef a] [Segment a] deriving (Generic, Show, Read, Eq, Ord, Functor, Foldable, Traversable)
--data Segment a = Segment Name [ArgDef a]        deriving (Generic, Show, Read, Eq, Ord, Functor, Foldable, Traversable)





--namePattern = Signature2 Nothing


--data Signature2 a = Signature2 { __self_ :: Maybe a
--                               , __pat_  :: Pattern a
--                               , __out_  :: a
--                               } deriving (Show, Functor, Foldable, Traversable)

--data Function2 a b = Function2 { __sig_  :: Signature2 a
--                               , __body_ :: b
--                               } deriving (Show, Functor, Foldable, Traversable)



--sigVarOp = Tok.explicitName Tok.varIdent <|> Tok.operator

--funcSig = try multiSig <|> singleSig

--singleSig = NamePat Nothing <$> singleSigSegment <*> pure []
--multiSig  = NamePat <$> maybe argS1 <*> multiSigSegment <*> many multiSigSegment

--singleSigSegment = Segment <$> Tok.varIdent <*> many argS1
--multiSigSegment  = Segment <$> sigVarOp <*> many argS1

--arg e = Arg <$> argPattern
--            <*> ((Just <$ Tok.assignment <*> e) <|> pure Nothing)

--argS1 = arg stage1DefArg

--foreign p = Decl.Foreign <$> (Foreign <$ Tok.kwForeign <*> foreignTarget <*> p)

--foreignTarget =   Foreign.Haskell <$ Tok.kwFHaskell
--              <|> Foreign.CPP     <$ Tok.kwFCPP

--func = Decl.Func    <$> funcDecl (stage1Block stage1Body2)

--stage1Block p = (char ':' *> p) <|> pure []

--funcDecl body = Decl.FuncDecl <$  Tok.kwDef
--                              <*> extPath
--                              <*> funcSig
--                              <*> outType
--                              <*> body
--    where extPath = ((qualifiedPath Tok.typeIdent <?> "extension path") <* Tok.accessor) <|> pure []
--          outType = (Just <$> try (Tok.arrow *> typic)) <|> pure Nothing


------- foreigns -----


--foreigns =  foreign $  (Decl.FFunc <$> funcDecl (fromString . concat <$> stage1Block stage1Body2))
--                   <|> (Decl.FData <$> dataDecl False)
--                   <|> (Decl.FImp . fromString <$> (many (noneOf "\r\n")))

------- classes -----

--cls = Decl.Data <$> dataDecl True

--withBlock p = blockStart *> p <* blockEnd

--rapp1 a f = f a
--rapp2 a b f = f a b

----dataDecl genDefaultCons = do
----    name <- Tok.kwClass *> (Tok.typeIdent <?> "class name")
----    Decl.DataDecl <$> pure name
----                  <*> params
----                  <*  blockBegin (Decl.addDecl <$> labeled (choice [ func, cls, typeAlias, typeWrapper, foreigns ]) <?> "class body")
----                  <*> pure []
----                  <*> pure []
----            <?> "class definition"
----      where params           = many (tvname <$> Tok.typeVarIdent <?> "class parameter")
----      --      defCons        n = Decl.Cons n <$> (concat <$> many fields)
----      --      defConsList    n = ((:[]) <$> labeled (defCons $ convert n))
----      --      constructors   n =   blockBody' (labeled cons) <|> defConsList n
----      --      bodyBlock        = blockBodyOpt $ labeled clsBody
----      --      clsBody          = choice [ func, cls, typeAlias, typeWrapper, foreigns ] <?> "class body"
----      --      defConsBuilder n = if genDefaultCons then (rapp2) <$> defConsList n <*> pure []
----      --                                           else pure $ (rapp2 [] [])

--dataDecl genDefCons = do
--    name <- Tok.kwClass *> (Tok.typeIdent <?> "class name")
--    bldr <- Decl.dataBuilder <$>  pure name
--                             <*>  params
--                             <**> bodyBuilder (convert name)
--                             <?>  "class definition"
--    build genDefCons (convert name) bldr
--      where params           = many (tvname <$> Tok.typeVarIdent <?> "class parameter")
--            dataDecls        = choice [ func, cls, typeAlias, typeWrapper, foreigns ]
--            bodyDecls        =   (Decl.addDecl   <$> labeled dataDecls <?> "class body")
--                             <|> (Decl.addCons   <$> labeled cons)
--                             <|> (Decl.addFields <$> fields)
--            bodyBuilder    n = (flip applyAll <$> blockBegin bodyDecls) <|> defConsBuilder n
--            defConsBuilder n = if genDefCons
--                                   then Decl.addCons <$> labeled (pure $ Decl.Cons n [])
--                                   else pure id




--build genDefCons name (Decl.DataBuilder decl fields) =
--    if not (null fields) && genDefCons
--        then do
--            defcons <- labeled . pure $ Decl.Cons name fields
--            return $ decl & Decl.dataDeclCons %~ (++ [defcons])
--        else return decl


--cons         = Decl.Cons <$> Tok.conIdent
--                         <*> ((concat <$> blockBeginFields fields) <|> pure [])
--                         <?> "data constructor definition"


--fields = do
--         (names, cls) <- {- try -} ((,) <$> fieldList      <*> typed)
--                         -- <|> ((,) <$> pure [Nothing] <*> Type.term)

--         sequence $ fmap (labeled.pure)
--                  $ zipWith3 Decl.Field (repeat cls) names (repeat Nothing)

--         where fieldList = sepBy1 (Just <$> Tok.varIdent) Tok.separator




--typed = Tok.typeDecl *> Type.typic



--stage1DefArg = Tok.tokenBlock (many (noneOf " \t\r\n:"))

--stage1BodyInner = (many1 $ noneOf "\n\r")
--stage1Body = (:) <$> stage1BodyInner <*> (try (spaces *> Indent.checkIndented *> stage1Body) <|> pure [[]])

--stage1Body2 = ((:) <$> (try ((<>) <$> Tok.spaces <* Indent.checkIndented <*> stage1BodyInner)) <*> stage1Body2) <|> pure [[]]

----stage1Block = (++) <$> Tok.spaces <* Ident.checkIndented <*> Indent.withPos (indBlockBody p)
----stage1Body2 = (:) <$> (try (Tok.spaces <* Indent.checkIndented <* stage1BodyInner) <|> pure []) <*> stage1Body2
