package org.enso.componentmanager.components

import nl.gn0s1s.bump.SemVer
import org.enso.cli.TaskProgress

/** Encapsulates the communication between [[ComponentManager]] and its user.
  */
trait ComponentManagementUserInterface {

  /** Called when a long-running task is started.
    *
    * Can be used to track its progress.
    */
  def trackProgress(task: TaskProgress[_]): Unit

  /** Called when an operation requires an engine that is not available.
    *
    * Depending on the return value, the missing engine will be installed or the
    * action will fail.
    */
  def shouldInstallMissingEngine(version: SemVer): Boolean

  /** Called when a runtime required to complete an operation is missing.
    *
    * This should not happen in usual situations as the runtimes are
    * automatically installed with an engine. It may only happen if the runtime
    * has been manually removed.
    *
    * Depending on the return value, the missing runtime will be installed or
    * the action will fail.
    */
  def shouldInstallMissingRuntime(version: RuntimeVersion): Boolean

  /** Called when a broken engine is about to be installed.
    *
    * Depending on the return value, the broken version will be installed or the
    * action will fail.
    */
  def shouldInstallBrokenEngine(version: SemVer): Boolean

  /** Called to allow for special handling of info-level logs. */
  def logInfo(message: => String): Unit
}