allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// file_picker's own module still declares compileSdk 34, but its
// flutter_plugin_android_lifecycle dependency requires compileSdk 36+.
// Force every Android library module in the build to compile against 36
// regardless of what the plugin itself declares. This needs to run after
// the subproject's own script body (which sets compileSdk 34) — but some
// plugin subprojects are already evaluated by the time this root script
// runs, and calling afterEvaluate on an already-evaluated project throws,
// so apply immediately in that case instead of registering a callback.
subprojects {
    val forceCompileSdk36 = Action<Project> {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                compileSdk = 36
            }
        }
    }
    if (state.executed) forceCompileSdk36.execute(this) else afterEvaluate(forceCompileSdk36)
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
