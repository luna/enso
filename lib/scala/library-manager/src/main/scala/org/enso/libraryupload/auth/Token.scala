package org.enso.libraryupload.auth

import org.enso.downloader.http.HTTPRequestBuilder

trait Token {
  def alterRequest(request: HTTPRequestBuilder): HTTPRequestBuilder
}

case class SimpleHeaderToken(value: String) extends Token {
  override def alterRequest(request: HTTPRequestBuilder): HTTPRequestBuilder =
    request.addHeader("Auth-Token", value)
}

case object NoAuthorization extends Token {
  override def alterRequest(request: HTTPRequestBuilder): HTTPRequestBuilder =
    request
}
