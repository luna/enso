package org.enso.languageserver.libraries.handler

import akka.actor.{Actor, Props}
import com.typesafe.scalalogging.LazyLogging
import org.enso.jsonrpc.{Request, ResponseError}
import org.enso.languageserver.filemanager.FileManagerApi.FileSystemError
import org.enso.languageserver.libraries.LibraryApi._
import org.enso.languageserver.util.UnhandledLogging

class LibraryPublishHandler
    extends Actor
    with LazyLogging
    with UnhandledLogging {
  override def receive: Receive = {
    case Request(LibraryPublish, id, _: LibraryPublish.Params) =>
      // TODO [RW] actual implementation
      sender() ! ResponseError(
        Some(id),
        FileSystemError("Feature not implemented")
      )
  }
}

object LibraryPublishHandler {
  def props(): Props = Props(new LibraryPublishHandler)
}