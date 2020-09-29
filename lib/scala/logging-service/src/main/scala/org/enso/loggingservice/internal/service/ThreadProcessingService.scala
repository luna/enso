package org.enso.loggingservice.internal.service

import org.enso.loggingservice.LogLevel
import org.enso.loggingservice.internal.{
  BlockingConsumerMessageQueue,
  InternalLogger
}
import org.enso.loggingservice.internal.protocol.WSLogMessage

import scala.util.control.NonFatal

trait ThreadProcessingService extends Service {
  protected def queue:    BlockingConsumerMessageQueue
  protected def logLevel: LogLevel

  protected def processMessage(message: WSLogMessage): Unit
  protected def shutdownProcessors():                  Unit

  private var queueThread: Option[Thread] = None
  protected def startQueueProcessor(): Unit = {
    val thread = new Thread(() => runQueue())
    queueThread = Some(thread)
    thread.start()
  }

  /**
    * The runner filters out internal messages that have disabled log levels,
    * but passes through all external messages (as their log level is set
    * independently and can be lower).
    */
  private def runQueue(): Unit = {
    try {
      while (!Thread.currentThread().isInterrupted) {
        val message = queue.nextMessage(logLevel)
        try {
          processMessage(message)
        } catch {
          case NonFatal(e) =>
            InternalLogger.error(
              s"One of the printers failed to write a message: $e"
            )
        }
      }
    } catch {
      case _: InterruptedException =>
    }
  }

  abstract override def terminate(): Unit = {
    super.terminate()
    queueThread match {
      case Some(thread) =>
        thread.interrupt()
        thread.join(100)
        shutdownProcessors()
      case None =>
    }
  }
}
