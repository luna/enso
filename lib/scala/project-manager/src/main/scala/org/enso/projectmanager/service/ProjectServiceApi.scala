package org.enso.projectmanager.service

import java.util.UUID

import org.enso.pkg.EnsoVersion
import org.enso.projectmanager.data.{
  LanguageServerSockets,
  MissingComponentAction,
  ProjectMetadata
}

/** A contract for the Project Service.
  *
  * @tparam F a monadic context
  */
trait ProjectServiceApi[F[+_, +_]] {

  /** Creates a user project.
    *
    * @param name the name of th project
    * @param version Enso version to use for the new project
    * @param missingComponentAction specifies how to handle missing components
    * @return projectId
    */
  def createUserProject(
    name: String,
    version: EnsoVersion,
    missingComponentAction: MissingComponentAction
  ): F[ProjectServiceFailure, UUID]

  /** Deletes a user project.
    *
    * @param projectId the project id
    * @return either failure or unit representing success
    */
  def deleteUserProject(projectId: UUID): F[ProjectServiceFailure, Unit]

  /** Renames a project.
    *
    * @param projectId the project id
    * @param name the new name
    * @return either failure or unit representing success
    */
  def renameProject(
    projectId: UUID,
    name: String
  ): F[ProjectServiceFailure, Unit]

  /** Opens a project. It starts up a Language Server if needed.
    *
    * @param clientId the requester id
    * @param projectId the project id
    * @return either failure or a socket of the Language Server
    */
  def openProject(
    clientId: UUID,
    projectId: UUID,
    missingComponentAction: MissingComponentAction
  ): F[ProjectServiceFailure, LanguageServerSockets]

  /** Closes a project. Tries to shut down the Language Server.
    *
    * @param clientId the requester id
    * @param projectId the project id
    * @return either failure or [[Unit]] representing void success
    */
  def closeProject(
    clientId: UUID,
    projectId: UUID
  ): F[ProjectServiceFailure, Unit]

  /** Lists the user's most recently opened projects..
    *
    * @param maybeSize the size of result set
    * @return list of recent projects
    */
  def listProjects(
    maybeSize: Option[Int]
  ): F[ProjectServiceFailure, List[ProjectMetadata]]

}
