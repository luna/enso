package org.enso.projectmanager.versionmanagement

import akka.http.scaladsl.model.Uri
import org.enso.runtimeversionmanager.Environment
import org.enso.runtimeversionmanager.components.{
  RuntimeVersionManagementUserInterface,
  RuntimeVersionManager
}
import org.enso.runtimeversionmanager.distribution.{
  DistributionManager,
  TemporaryDirectoryManager
}
import org.enso.runtimeversionmanager.locking.ResourceManager
import org.enso.runtimeversionmanager.releases.ReleaseProvider
import org.enso.runtimeversionmanager.releases.engine.EngineRelease
import org.enso.runtimeversionmanager.runner.JVMSettings

import scala.concurrent.Future

/** Specifies the configuration of project manager's distribution.
  *
  * By default the project manager will define the set of its managers that use
  * a distribution located in a specific place within the filesystem. It can
  * also be overridden in tests.
  */
trait DistributionConfiguration {

  /** An [[Environment]] instance. */
  def environment: Environment

  /** A [[DistributionManager]] instance. */
  def distributionManager: DistributionManager

  /** A [[ResourceManager]] instance. */
  def resourceManager: ResourceManager

  /** A [[TemporaryDirectoryManager]] instance. */
  def temporaryDirectoryManager: TemporaryDirectoryManager

  /** A provider of engine releases. */
  def engineReleaseProvider: ReleaseProvider[EngineRelease]

  /** Creates a [[RuntimeVersionManager]] from the specified
    * [[RuntimeVersionManagementUserInterface]] that will use the other managers
    * defined here.
    */
  def makeRuntimeVersionManager(
    userInterface: RuntimeVersionManagementUserInterface
  ): RuntimeVersionManager

  /** Default set of JVM settings to use when launching the runner.
    *
    * This is exposed mostly for ease of overriding the settings in tests.
    */
  def defaultJVMSettings: JVMSettings

  /** Specifies if output of the child Language Server process should be ignored
    * or piped to parent's streams.
    *
    * This option is used to easily turn off logging in tests.
    */
  def shouldDiscardChildOutput: Boolean

  /** A future that is completed once the logging service has been initialized
    * and specifies if launched component should connect to it or handle logging
    * on their own.
    */
  def loggingServiceEndpoint: Future[Option[Uri]]
}
