package src.main.scala.licenses.report

import java.io.FileNotFoundException
import java.nio.file.{Files, Path}
import java.time.LocalDate

import sbt._
import src.main.scala.licenses._

import scala.util.control.NonFatal

/**
  * Reads settings from the `root` to add review statuses to discovered
  * attachments and add any additional attachments coming from the settings.
  *
  * The review settings consist of the following files or directories (all are
  * optional):
  *
  * - `notice-header` - contains the header that will start the main generated
  *   NOTICE
  * - `files-add` - directory that may contain additional files that should be
  *   added to the package
  * - `reviewed-licenses` - directory that may contain files for reviewed
  *   licenses; the files should be named with the normalized license name and
  *   they should contain a path to that license's file
  * - and for each dependency, a subdirectory named as its `packageName` with
  *   following entries:
  *    - `files-add` - directory that may contain additional files that should
  *      be added to the subdirectory for this package
  *    - `files-keep` - a file containing names of files found in the package
  *      sources that should be included in the package
  *    - `files-ignore` - a file containing names of files found in the package
  *      sources that should not be included
  *    - `custom-license` - a file that indicates that the dependency should not
  *      point to the default license, but it should contain a custom one within
  *      its files
  *    - `copyright-keep` - copyright lines that should be included in the
  *      notice summary for the package
  *    - `copyright-keep-context` - copyright lines that should be included
  *      (alongside with their context) in the notice summary for the package
  *    - `copyright-ignore` - copyright lines that should not be included in the
  *      notice summary for the package
  *    - `copyright-add` - a single file whose contents will be added to the
  *      notice summary for the package
  *
  * @param root directory that contains files which guide the review process
  * @param dependencySummary summary of discovered dependency information
  */
case class Review(root: File, dependencySummary: DependencySummary) {

  /**
    * Runs the review process, returning a [[ReviewedDependency]] which includes
    * information from the [[DependencySummary]] enriched with review statuses.
    */
  def run(): ReviewedSummary = {
    val reviews = dependencySummary.dependencies.map {
      case (information, attachments) =>
        reviewDependency(information, attachments)
    }

    val header = findHeader()
    val files  = findAdditionalFiles(root / "files-add")
    ReviewedSummary(reviews, header, files)
  }

  /**
    * Finds a header defined in the settings or
    */
  private def findHeader(): String =
    readFile(root / "notice-header").getOrElse(Review.defaultHeader)

  /**
    * Reads files from the provided directory as [[AttachedFile]].
    */
  private def findAdditionalFiles(dir: File): Seq[AttachedFile] =
    listFiles(dir).map(f => AttachedFile.read(f.toPath, Some(dir.toPath)))

  /**
    * Splits the sequence of attachments into sequences of files and copyrights.
    */
  private def splitAttachments(
    attachments: Seq[Attachment]
  ): (Seq[AttachedFile], Seq[CopyrightMention]) = {
    val notices    = attachments.collect { case n: AttachedFile => n }
    val copyrights = attachments.collect { case c: CopyrightMention => c }
    (notices, copyrights)
  }

  /**
    * Returns only such copyrights that are not included in one of the
    * discovered files.
    */
  private def removeCopyrightsIncludedInNotices(
    copyrights: Seq[CopyrightMention],
    notices: Seq[AttachedFile]
  ): Seq[CopyrightMention] = {
    def shouldKeepCopyright(copyright: CopyrightMention): Boolean = {
      val allOriginsAreFresh = copyright.origins.forall { path =>
        !notices.exists(_.path == path)
      }
      allOriginsAreFresh
    }
    copyrights.filter(shouldKeepCopyright)
  }

  /**
    * Returns the review status of the license and any attachments associated
    * with the dependency.
    */
  private def reviewDependency(
    info: DependencyInformation,
    attachments: Seq[Attachment]
  ): ReviewedDependency = {
    val packageRoot                    = root / info.packageName
    val (licenseReviewed, licensePath) = reviewLicense(packageRoot, info)
    val (files, copyrights)            = splitAttachments(attachments)
    val copyrightsDeduplicated =
      removeCopyrightsIncludedInNotices(copyrights, files)

    val processedFiles =
      reviewFiles(packageRoot, files) ++ addFiles(packageRoot)
    val processedCopyrights =
      reviewCopyrights(packageRoot, copyrightsDeduplicated) ++
      addCopyrights(packageRoot)

    ReviewedDependency(
      information     = info,
      licenseReviewed = licenseReviewed,
      licensePath     = licensePath,
      files           = processedFiles,
      copyrights      = processedCopyrights
    )
  }

  /**
    * Enriches the file attachments with their review status.
    */
  private def reviewFiles(
    packageRoot: File,
    files: Seq[AttachedFile]
  ): Seq[(AttachedFile, AttachmentStatus)] = {
    val ignore = readLines(packageRoot / "files-ignore")
    val keep   = readLines(packageRoot / "files-keep")
    def review(file: AttachedFile): AttachmentStatus = {
      val key = file.path.toString
      if (keep.contains(key)) AttachmentStatus.Keep
      else if (ignore.contains(key)) AttachmentStatus.Ignore
      else AttachmentStatus.NotReviewed
    }
    files.map(f => (f, review(f)))
  }

  /**
    * Returns any additional file attachments that are manually added in the
    * review.
    */
  private def addFiles(
    packageRoot: File
  ): Seq[(AttachedFile, AttachmentStatus)] =
    findAdditionalFiles(packageRoot / "files-add")
      .map((_, AttachmentStatus.Added))

  /**
    * Enriches the copyright attachments with their review status.
    */
  private def reviewCopyrights(
    packageRoot: File,
    copyrights: Seq[CopyrightMention]
  ): Seq[(CopyrightMention, AttachmentStatus)] = {
    val ignore      = readLines(packageRoot / "copyright-ignore")
    val keep        = readLines(packageRoot / "copyright-keep")
    val keepContext = readLines(packageRoot / "copyright-keep-context")
    def review(copyright: CopyrightMention): AttachmentStatus = {
      val key = copyright.content.strip
      if (keepContext.contains(key)) AttachmentStatus.KeepWithContext
      else if (keep.contains(key)) AttachmentStatus.Keep
      else if (ignore.contains(key)) AttachmentStatus.Ignore
      else AttachmentStatus.NotReviewed
    }
    copyrights.map(c => (c, review(c)))
  }

  /**
    * Returns any additional copyright attachments that are manually added in
    * the review.
    */
  private def addCopyrights(
    packageRoot: File
  ): Seq[(CopyrightMention, AttachmentStatus)] =
    readFile(packageRoot / "copyright-add")
      .map(text =>
        (
          CopyrightMention(
            content  = "<manually added mentions>",
            contexts = Seq(text),
            origins  = Seq()
          ),
          AttachmentStatus.Added
        )
      )
      .toSeq

  /**
    * Checks if the license has been reviewed.
    *
    * Returns a boolean value indicating if it has been reviewed and a path to
    * the license file if a default file is used.
    */
  private def reviewLicense(
    packageRoot: File,
    info: DependencyInformation
  ): (Boolean, Option[Path]) = {
    if (Files.exists((packageRoot / "custom-license").toPath)) (true, None)
    else
      readFile(
        root / "reviewed-licenses" / Review.normalizeName(info.license.name)
      )
        .map(p => (true, Some(Path.of(p.strip()))))
        .getOrElse((false, None))
  }

  /**
    * Reads the file as lines.
    *
    * Returns an empty sequence if the file cannot be read.
    */
  private def readLines(file: File): Seq[String] =
    try { IO.readLines(file).map(_.strip).filter(_.nonEmpty) }
    catch { case NonFatal(_) => Seq() }

  /**
    * Reads the file as a [[String]].
    *
    * Returns None if the file cannot be read.
    */
  private def readFile(file: File): Option[String] =
    try { Some(IO.read(file)) }
    catch { case NonFatal(_) => None }

  /**
    * Returns a sequence of files contained in a directory.
    *
    * If the directory does not exist or otherwise cannot be queried, returns an
    * empty sequence.
    */
  private def listFiles(dir: File): Seq[File] = {
    try { IO.listFiles(dir) }
    catch { case NonFatal(_) => Seq() }
  }
}

object Review {

  /**
    * Normalizes a name so that it can be used as a filename.
    */
  def normalizeName(string: String): String = {
    val charsToReplace = " /:;,"
    charsToReplace.foldLeft(string)((str, char) => str.replace(char, '_'))
  }

  /**
    * Default NOTICE header.
    */
  val defaultHeader: String = {
    val yearStart   = 2020
    val yearCurrent = LocalDate.now().getYear
    val year =
      if (yearCurrent > yearStart) s"$yearStart - $yearCurrent"
      else s"$yearStart"
    s"""Enso
       |Copyright $year New Byte Order sp. z o. o.""".stripMargin
  }
}
