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

// ---------------------------------------------------------------------------
// Android Lint "vital" analysis guard (release builds only)
//
// `flutter build apk --release` also runs AGP's vital lint over third-party
// plugin sources. On Gradle JDKs older than 21 that analysis crashes inside the
// bundled lint CommentDetector:
//     NoSuchMethodError: 'java.util.List.removeLast()'
// (removeLast() exists only from Java 21, while lint's own code already uses
// it.) It crashes on file_selector_android's FileUtils.java — plugin code that
// is not ours — and it aborts the whole build.
//
// Proper fix: run Gradle on JDK 21+. This block is the safety net: the vital
// lint tasks are skipped in every subproject so a lint-internal bug can never
// block a release APK. `flutter analyze` and `flutter test` still cover the
// Dart side completely.
// ---------------------------------------------------------------------------
subprojects {
    tasks.configureEach {
        if (name.startsWith("lintVital")) {
            enabled = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
