package org.enso.languageserver.libraries

import akka.actor.{Actor, Props}
import org.enso.editions.{DefaultEdition, EditionResolver, Editions}
import org.enso.pkg.PackageManager

import java.io.File
import scala.util.Try

class ProjectSettingsManager(
  projectRoot: File,
  editionResolver: EditionResolver
) extends Actor {
  import ProjectSettingsManager._

  override def receive: Receive = { case request: Request =>
    request match {
      case GetSettings =>
        sender() ! loadSettings()
      case SetParentEdition(editionName) =>
        sender() ! setParentEdition(editionName)
      case SetPreferLocalLibraries(preferLocalLibraries) =>
        sender() ! setPreferLocalLibraries(preferLocalLibraries)
    }
  }

  private def loadSettings(): Try[SettingsResponse] = for {
    pkg <- PackageManager.Default.loadPackage(projectRoot)
    edition = pkg.config.edition.getOrElse(DefaultEdition.getDefaultEdition)
  } yield SettingsResponse(edition.parent, pkg.config.preferLocalLibraries)

  private def setParentEdition(editionName: String): Try[Unit] = for {
    pkg <- PackageManager.Default.loadPackage(projectRoot)
    newEdition = pkg.config.edition match {
      case Some(edition) => edition.copy(parent = Some(editionName))
      case None          => Editions.Raw.Edition(parent = Some(editionName))
    }
    _ <- editionResolver.resolve(newEdition).toTry
    updated = pkg.updateConfig { config =>
      config.copy(edition = Some(newEdition))
    }
  } yield updated.save()

  private def setPreferLocalLibraries(
    preferLocalLibraries: Boolean
  ): Try[Unit] = for {
    pkg <- PackageManager.Default.loadPackage(projectRoot)
    updated = pkg.updateConfig { config =>
      config.copy(preferLocalLibraries = preferLocalLibraries)
    }
  } yield updated.save()
}

object ProjectSettingsManager {
  def props(projectRoot: File, editionResolver: EditionResolver): Props = Props(
    new ProjectSettingsManager(projectRoot, editionResolver)
  )

  sealed trait Request

  case object GetSettings extends Request
  case class SettingsResponse(
    parentEdition: Option[String],
    preferLocalLibraries: Boolean
  )

  case class SetParentEdition(editionName: String) extends Request

  case class SetPreferLocalLibraries(preferLocalLibraries: Boolean)
      extends Request
}
