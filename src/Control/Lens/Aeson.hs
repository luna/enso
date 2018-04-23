module Control.Lens.Aeson where

import qualified Data.Aeson          as JSON
import qualified Data.Aeson.Encoding as JSON
import qualified Data.Aeson.Types    as JSON
import qualified Data.Char           as Char
import qualified Data.List           as List
import qualified Data.List.Split     as List

import GHC.Generics (Generic, Rep)

------------------------------------------
-- === JSON / Yaml conversion utils === --
------------------------------------------

-- === API === --

options :: JSON.Options
options = JSON.defaultOptions
    { JSON.fieldLabelModifier = List.dropWhile (== '_')}

optionsDropUnary :: JSON.Options
optionsDropUnary = options { JSON.unwrapUnaryRecords = True }

optionsYamlStyle :: JSON.Options
optionsYamlStyle = JSON.defaultOptions { JSON.fieldLabelModifier = yaml } where
    yaml str = List.intercalate "-"
            $ (\xs -> Char.toLower <$> xs) <$> splitUpperKeep noUnderscores
        where noUnderscores  = List.dropWhile (== '_') str
              splitUpperKeep = List.split
                (List.keepDelimsL $ List.oneOf ['A'..'Z'])

parse :: (Generic a, JSON.GFromJSON JSON.Zero (Rep a)) => JSON.Value
      -> JSON.Parser a
parse = JSON.genericParseJSON  options

toEncoding :: (Generic a, JSON.GToEncoding JSON.Zero (Rep a)) => a
           -> JSON.Encoding
toEncoding = JSON.genericToEncoding options

toJSON :: (Generic a, JSON.GToJSON JSON.Zero (Rep a)) => a -> JSON.Value
toJSON = JSON.genericToJSON     options

parseDropUnary :: (Generic a, JSON.GFromJSON JSON.Zero (Rep a)) => JSON.Value
               -> JSON.Parser a
parseDropUnary = JSON.genericParseJSON  optionsDropUnary

toEncodingDropUnary :: (Generic a, JSON.GToEncoding JSON.Zero (Rep a)) => a
                    -> JSON.Encoding
toEncodingDropUnary = JSON.genericToEncoding optionsDropUnary

toJSONDropUnary :: (Generic a, JSON.GToJSON JSON.Zero (Rep a)) => a
                -> JSON.Value
toJSONDropUnary = JSON.genericToJSON optionsDropUnary

parseYamlStyle :: (Generic a, JSON.GFromJSON JSON.Zero (Rep a)) => JSON.Value
               -> JSON.Parser a
parseYamlStyle = JSON.genericParseJSON  optionsYamlStyle

toEncodingYamlStyle :: (Generic a, JSON.GToEncoding JSON.Zero (Rep a)) => a
                    -> JSON.Encoding
toEncodingYamlStyle = JSON.genericToEncoding optionsYamlStyle

toJSONYamlStyle :: (Generic a, JSON.GToJSON JSON.Zero (Rep a)) => a
                -> JSON.Value
toJSONYamlStyle = JSON.genericToJSON     optionsYamlStyle


