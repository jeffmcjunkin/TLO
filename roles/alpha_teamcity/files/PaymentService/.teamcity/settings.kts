// TeamCity Kotlin DSL — build configuration for payment-service.
// Shipped as an artifact so the build config can be versioned when a VCS root is
// attached. The command-line step invokes build.cmd, which locates MSBuild via
// vswhere and builds PaymentService.csproj.
import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildSteps.script

version = "2024.12"

project {
    buildType(Build)
}

object Build : BuildType({
    id("PaymentService_Build")
    name = "Build"

    vcs { }

    steps {
        script {
            name = "MSBuild payment-service"
            // Locates MSBuild via vswhere then builds the project on disk.
            scriptContent = "C:\\Projects\\payment-service\\build.cmd"
        }
    }

    // A commit trigger would rebuild on every push.
    // triggers { vcs { } }
})
