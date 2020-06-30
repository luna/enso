package org.enso.languageserver.requesthandler.search

import akka.actor.{Actor, ActorLogging, ActorRef, Cancellable, Props, Status}
import org.enso.jsonrpc.Errors.ServiceError
import org.enso.jsonrpc._
import org.enso.languageserver.requesthandler.RequestTimeout
import org.enso.languageserver.runtime.SearchApi.{
  Completion,
  SuggestionsDatabaseError
}
import org.enso.languageserver.runtime.SearchProtocol
import org.enso.languageserver.util.UnhandledLogging

import scala.concurrent.duration.FiniteDuration

/**
  * A request handler for `search/getSuggestionsDatabaseVersion` command.
  *
  * @param timeout request timeout
  * @param suggestionsHandler a reference to the suggestions handler
  */
class CompleteHandler(
  timeout: FiniteDuration,
  suggestionsHandler: ActorRef
) extends Actor
    with ActorLogging
    with UnhandledLogging {

  import context.dispatcher

  override def receive: Receive = requestStage

  private def requestStage: Receive = {
    case Request(
          Completion,
          id,
          Completion.Params(module, pos, selfType, returnType, tags)
        ) =>
      suggestionsHandler ! SearchProtocol.Completion(
        module,
        pos,
        selfType,
        returnType,
        tags
      )
      val cancellable =
        context.system.scheduler.scheduleOnce(timeout, self, RequestTimeout)
      context.become(responseStage(id, sender(), cancellable))
  }

  private def responseStage(
    id: Id,
    replyTo: ActorRef,
    cancellable: Cancellable
  ): Receive = {
    case Status.Failure(ex) =>
      log.error(ex, "Complete error")
      replyTo ! ResponseError(Some(id), SuggestionsDatabaseError)
      cancellable.cancel()
      context.stop(self)

    case RequestTimeout =>
      log.error(s"Request $id timed out")
      replyTo ! ResponseError(Some(id), ServiceError)
      context.stop(self)

    case SearchProtocol.CompletionResult(results, version) =>
      replyTo ! ResponseResult(
        Completion,
        id,
        Completion.Result(results, version)
      )
      cancellable.cancel()
      context.stop(self)
  }
}

object CompleteHandler {

  /**
    * Creates configuration object used to create a [[CompleteHandler]].
    *
    * @param timeout request timeout
    * @param suggestionsHandler a reference to the suggestions handler
    */
  def props(
    timeout: FiniteDuration,
    suggestionsHandler: ActorRef
  ): Props =
    Props(new CompleteHandler(timeout, suggestionsHandler))

}
