package org.enso.languageserver.filemanager

import org.enso.jsonrpc.Error
import org.enso.languageserver.filemanager.FileManagerApi._
import org.enso.languageserver.protocol.json.ErrorApi

object FileSystemFailureMapper {

  /** Maps [[FileSystemFailure]] into JSON RPC error.
    *
    * @param fileSystemFailure file system specific failure
    * @return JSON RPC error
    */
  def mapFailure(fileSystemFailure: FileSystemFailure): Error =
    fileSystemFailure match {
      case ContentRootNotFound              => ContentRootNotFoundError
      case AccessDenied                     => ErrorApi.AccessDeniedError
      case FileNotFound                     => FileNotFoundError
      case FileExists                       => FileExistsError
      case OperationTimeout                 => OperationTimeoutError
      case NotDirectory                     => NotDirectoryError
      case NotFile                          => NotFileError
      case CannotOverwrite                  => CannotOverwriteError
      case ReadOutOfBounds(l)               => ReadOutOfBoundsError(l)
      case GenericFileSystemFailure(reason) => FileSystemError(reason)
    }

}
