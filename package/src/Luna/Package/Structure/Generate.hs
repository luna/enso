module Luna.Package.Structure.Generate
    ( module Luna.Package.Structure.Generate
    , module X ) where

import Luna.Package.Structure.Generate.Internal as X (GeneratorError(..))
import Luna.Package.Structure.Utilities         as X (isValidPkgName)

import Prologue

import qualified Control.Exception                        as Exception
import qualified Luna.Package.Configuration.Global        as Global
import qualified Luna.Package.Structure.Generate.Internal as Internal
import qualified Luna.Package.Structure.Utilities         as Utilities
import qualified Luna.Path.Path                           as Path
import qualified Path                                     as Path
import qualified Path.IO                                  as Path
import qualified System.Directory                         as Directory
import qualified System.FilePath                          as FilePath

import Luna.Package.Configuration.License       (License)
import Luna.Package.Structure.Generate.Internal (recovery)
import System.FilePath                          (FilePath)

--------------------------------
-- === Project Generation === --
--------------------------------

-- === API === --

genPackageStructure :: MonadIO m => Path.Path a Path.Dir -> Maybe License -> Global.Config
                    -> m (Either GeneratorError (Path.Path Path.Abs Path.Dir))
genPackageStructure path mLicense gblConf =
    if Path.liftPredicate (\name -> length name < 1) path then
        pure . Left . InvalidPackageName $ convert (Path.toFilePath path)
    else do
        -- This is safe as it has at least one component if `path` is nonemtpy
        -- `path` is nonempty due to the guard above.
        let pkgName = unsafeLast $ Path.splitDirectories path

        canonicalPath <- Path.canonicalizePath path
        insidePkg     <- Utilities.findParentPackageIfInside canonicalPath

        let isInsidePkg = isJust insidePkg

        if  | Utilities.isValidPkgName pkgName && not isInsidePkg ->
                liftIO $ Exception.catch create (recovery canonicalPath)
            | isInsidePkg -> pure . Left . InvalidPackageLocation
                $ fromJust "" (Path.toFilePath <$> insidePkg)
            | otherwise -> pure . Left . InvalidPackageName
                $ convert (Path.fromAbsDir canonicalPath)
        where
            create :: IO (Either GeneratorError (Path.Path Path.Abs Path.Dir))
            create = do
                canonicalPath <- Path.canonicalizePath path
                Path.createDirIfMissing True canonicalPath

                Internal.generateConfigDir       canonicalPath mLicense gblConf
                Internal.generateDistributionDir canonicalPath
                Internal.generateSourceDir       canonicalPath
                Internal.generateLicense         canonicalPath mLicense
                Internal.generateReadme          canonicalPath
                Internal.generateGitignore       canonicalPath

                pure $ Right canonicalPath

{-

genPackageStructure :: MonadIO m => FilePath -> Maybe License -> Global.Config
                    -> m (Either GeneratorError FilePath)
genPackageStructure name mLicense gblConf =
    if length name < 1 then
        pure . Left . InvalidPackageName $ convert name
    else do
        -- This is safe as it has at least one component if `name` is nonemtpy
        -- `name` is nonempty due to the guard above.
        let pkgName = unsafeLast $ Path.splitDirectories name

        canonicalName <- liftIO $ Directory.canonicalizePath name
        insidePkg     <- Utilities.findParentPackageIfInside canonicalName

        let isInsidePkg = isJust insidePkg

        if  | Utilities.isValidPkgName pkgName && not isInsidePkg ->
                liftIO $ Exception.catch create (recovery canonicalName)
            | isInsidePkg -> pure . Left . InvalidPackageLocation
                $ fromJust "" insidePkg
            | otherwise -> pure . Left . InvalidPackageName
                $ convert canonicalName
        where
            create :: IO (Either GeneratorError FilePath)
            create = do
                canonicalPath <- Directory.canonicalizePath name
                Directory.createDirectoryIfMissing True canonicalPath

                Internal.generateConfigDir       canonicalPath mLicense gblConf
                Internal.generateDistributionDir canonicalPath
                Internal.generateSourceDir       canonicalPath
                Internal.generateLicense         canonicalPath mLicense
                Internal.generateReadme          canonicalPath
                Internal.generateGitignore       canonicalPath

                pure $ Right canonicalPath

-}