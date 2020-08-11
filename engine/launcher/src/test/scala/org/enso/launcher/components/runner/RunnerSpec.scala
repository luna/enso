package org.enso.launcher.components.runner

import java.nio.file.{Files, Path}
import java.util.UUID

import nl.gn0s1s.bump.SemVer
import org.enso.launcher.FileSystem.PathSyntax
import org.enso.launcher.{GlobalConfigurationManager, Logger}
import org.enso.launcher.components.ComponentsManagerTest
import org.enso.launcher.project.ProjectManager
import org.scalatest.TryValues

class RunnerSpec extends ComponentsManagerTest with TryValues {
  private val defaultEngineVersion = SemVer(0, 0, 0, Some("default"))
  case class TestSetup(runner: Runner, projectManager: ProjectManager)
  def makeFakeRunner(cwdOverride: Option[Path] = None): TestSetup = {
    val (_, componentsManager) = makeManagers()
    val configurationManager =
      new GlobalConfigurationManager(componentsManager) {
        override def defaultVersion: SemVer = defaultEngineVersion
      }
    val projectManager = new ProjectManager(configurationManager)
    val cwd            = cwdOverride.getOrElse(getTestDirectory)
    val runner =
      new Runner(projectManager, configurationManager, componentsManager, cwd)
    TestSetup(runner, projectManager)
  }

  "Runner" should {
    "create a command from settings" in {
      Logger.suppressWarnings {
        val TestSetup(runner, _) = makeFakeRunner()

        val runSettings = RunSettings(SemVer(0, 0, 0), Seq("arg1", "--flag2"))
        val jvmOptions  = Seq(("locally-added-options", "value1"))
        val systemCommand = runner.createCommand(
          runSettings,
          JVMSettings(useSystemJVM = true, jvmOptions = jvmOptions)
        )

        systemCommand.command.head shouldEqual "java"

        val managedCommand = runner.createCommand(
          runSettings,
          JVMSettings(useSystemJVM = false, jvmOptions = jvmOptions)
        )

        managedCommand.command.head should include("java")
        managedCommand.extraEnv.find(_._1 == "JAVA_HOME").value._2 should
        include("graalvm-ce")

        for (command <- Seq(systemCommand, managedCommand)) {
          val commandLine = command.command.mkString(" ")
          commandLine should include("-Dlocally-added-options=value1")
          commandLine should include("-Doptions-added-from-manifest=42")
          commandLine should include("-Danother-one=true")
          commandLine should endWith("arg1 --flag2")

          commandLine should include
          regex("-Dtruffle.append.classpath=.*runtime.jar")

          commandLine should include
          regex("-jar .*runner.jar")
        }
      }
    }

    "run repl with default version and additional arguments" in {
      val TestSetup(runner, _) = makeFakeRunner()
      val runSettings = runner
        .repl(
          projectPath         = None,
          versionOverride     = None,
          additionalArguments = Seq("arg", "--flag")
        )
        .success
        .value

      runSettings.version shouldEqual defaultEngineVersion
      runSettings.runnerArguments should (contain("arg") and contain("--flag"))
      runSettings.runnerArguments.mkString(" ") should
      (include("--repl") and not include (s"--in-project"))
    }

    "run repl in project context" in {
      val TestSetup(runnerOutside, projectManager) = makeFakeRunner()

      val version        = SemVer(0, 0, 0, Some("repl-test"))
      version should not equal defaultEngineVersion // sanity check

      val projectPath    = getTestDirectory / "project"
      val normalizedPath = projectPath.toAbsolutePath.normalize.toString
      projectManager.newProject(
        "test",
        projectPath,
        Some(version.toString)
      )

      val outsideProject = runnerOutside
        .repl(
          projectPath         = Some(projectPath),
          versionOverride     = None,
          additionalArguments = Seq()
        )
        .success
        .value

      outsideProject.version shouldEqual version
      outsideProject.runnerArguments.mkString(" ") should
      (include(s"--in-project $normalizedPath") and include("--repl"))

      val TestSetup(runnerInside, _) = makeFakeRunner(Some(projectPath))
      val insideProject = runnerInside
        .repl(
          projectPath         = None,
          versionOverride     = None,
          additionalArguments = Seq()
        )
        .success
        .value

      insideProject.version shouldEqual version
      insideProject.runnerArguments.mkString(" ") should
      (include(s"--in-project $normalizedPath") and include("--repl"))

      val overridden = SemVer(0, 0, 0, Some("overridden"))
      val overriddenRun = runnerInside
        .repl(
          projectPath         = Some(projectPath),
          versionOverride     = Some(overridden),
          additionalArguments = Seq()
        )
        .success
        .value

      overriddenRun.version shouldEqual overridden
      overriddenRun.runnerArguments.mkString(" ") should
      (include(s"--in-project $normalizedPath") and include("--repl"))
    }

    "run language server" in {
      val TestSetup(runner, projectManager) = makeFakeRunner()

      val version     = SemVer(0, 0, 0, Some("language-server-test"))
      val projectPath = getTestDirectory / "project"
      projectManager.newProject(
        "test",
        projectPath,
        Some(version.toString)
      )

      val options = LanguageServerOptions(
        rootId    = UUID.randomUUID(),
        path      = projectPath,
        interface = "127.0.0.2",
        rpcPort   = 1234,
        dataPort  = 4321
      )
      val runSettings = runner
        .languageServer(
          options,
          versionOverride     = None,
          additionalArguments = Seq("additional")
        )
        .success
        .value

      runSettings.version shouldEqual version
      val commandLine = runSettings.runnerArguments.mkString(" ")
      commandLine should include(s"--interface ${options.interface}")
      commandLine should include(s"--rpc-port ${options.rpcPort}")
      commandLine should include(s"--data-port ${options.dataPort}")
      commandLine should include(s"--root-id ${options.rootId}")
      val normalizedPath = options.path.toAbsolutePath.normalize.toString
      commandLine should include(s"--path $normalizedPath")
      runSettings.runnerArguments.lastOption.value shouldEqual "additional"

      val overridden = SemVer(0, 0, 0, Some("overridden"))
      runner
        .languageServer(
          options,
          versionOverride     = Some(overridden),
          additionalArguments = Seq()
        )
        .success
        .value
        .version shouldEqual overridden
    }

    "run a project" in {
      val TestSetup(runnerOutside, projectManager) = makeFakeRunner()

      val version        = SemVer(0, 0, 0, Some("run-test"))
      val projectPath    = getTestDirectory / "project"
      val normalizedPath = projectPath.toAbsolutePath.normalize.toString
      projectManager.newProject(
        "test",
        projectPath,
        Some(version.toString)
      )

      val outsideProject = runnerOutside
        .run(
          path                = Some(projectPath),
          versionOverride     = None,
          additionalArguments = Seq()
        )
        .success
        .value

      outsideProject.version shouldEqual version
      outsideProject.runnerArguments.mkString(" ") should
      include(s"--run $normalizedPath")

      val TestSetup(runnerInside, _) = makeFakeRunner(Some(projectPath))
      val insideProject = runnerInside
        .run(
          path                = None,
          versionOverride     = None,
          additionalArguments = Seq()
        )
        .success
        .value

      insideProject.version shouldEqual version
      insideProject.runnerArguments.mkString(" ") should
      include(s"--run $normalizedPath")

      val overridden = SemVer(0, 0, 0, Some("overridden"))
      val overriddenRun = runnerInside
        .run(
          path                = Some(projectPath),
          versionOverride     = Some(overridden),
          additionalArguments = Seq()
        )
        .success
        .value

      overriddenRun.version shouldEqual overridden
      overriddenRun.runnerArguments.mkString(" ") should
      include(s"--run $normalizedPath")

      assert(
        runnerOutside
          .run(
            path                = None,
            versionOverride     = None,
            additionalArguments = Seq()
          )
          .isFailure,
        "Running outside project without providing any paths should be an error"
      )
    }

    "run a script outside of a project even if cwd is inside project" in {
      val version     = SemVer(0, 0, 0, Some("run-test"))
      val projectPath = getTestDirectory / "project"
      val TestSetup(runnerInside, projectManager) =
        makeFakeRunner(cwdOverride = Some(projectPath))
      projectManager.newProject(
        "test",
        projectPath,
        Some(version.toString)
      )

      val outsideFile = getTestDirectory / "Main.enso"
      val normalizedPath = outsideFile.toAbsolutePath.normalize.toString
      Files.copy(
        projectPath / "src" / "Main.enso",
        outsideFile
      )

      val runSettings = runnerInside
        .run(
          path                = Some(outsideFile),
          versionOverride     = None,
          additionalArguments = Seq()
        )
        .success
        .value

      runSettings.version shouldEqual defaultEngineVersion
      runSettings.runnerArguments.mkString(" ") should
        (include(s"--run $normalizedPath") and not include("--in-project"))
    }

    "run a script inside of a project" in {
      val version     = SemVer(0, 0, 0, Some("run-test"))
      val projectPath = getTestDirectory / "project"
      val normalizedProjectPath = projectPath.toAbsolutePath.normalize.toString
      val TestSetup(runnerOutside, projectManager) = makeFakeRunner()
      projectManager.newProject(
        "test",
        projectPath,
        Some(version.toString)
      )

      val insideFile = projectPath / "src" / "Main.enso"
      val normalizedFilePath = insideFile.toAbsolutePath.normalize.toString

      val runSettings = runnerOutside
        .run(
          path                = Some(insideFile),
          versionOverride     = None,
          additionalArguments = Seq()
        )
        .success
        .value

      runSettings.version shouldEqual version
      runSettings.runnerArguments.mkString(" ") should
        (include(s"--run $normalizedFilePath") and
          include(s"--in-project $normalizedProjectPath"))
    }
  }
}
