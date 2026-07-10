allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// tflite_flutter defaults to Java 11 compile + Kotlin 21, which fails
// the JVM target compatibility check. Bump Java to 17 to match Kotlin.
project(":tflite_flutter") {
    afterEvaluate {
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
    }
}

// AGP 9 makes `compileSdk` and `namespace` mandatory on every Android module.
// Several pinned third-party plugins (e.g. google_sign_in_android,
// screenshot_callback) predate that requirement and fail configuration under
// AGP 9. After each library subproject's own script runs, fill in sane
// defaults where still missing: compileSdk = :app's, and namespace derived
// from the plugin's AndroidManifest `package` attribute.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.LibraryExtension) {
            // AGP 9 makes `checkAarMetadata` a hard failure: a library compiled
            // against an older SDK than its own androidx deps require (e.g.
            // screenshot_callback at 33 vs androidx.fragment 1.7.1 needing 34)
            // no longer warns — it fails the build. Raise any library's
            // compileSdk to at least :app's level (36) when it's missing OR too low.
            if (androidExt.compileSdk == null || androidExt.compileSdk!! < 36) {
                androidExt.compileSdk = 36
            }
            if (androidExt.namespace.isNullOrEmpty()) {
                val manifest = file("src/main/AndroidManifest.xml")
                if (manifest.exists()) {
                    val pkg = javax.xml.parsers.DocumentBuilderFactory.newInstance()
                        .newDocumentBuilder()
                        .parse(manifest)
                        .documentElement
                        .getAttribute("package")
                    if (!pkg.isNullOrEmpty()) {
                        androidExt.namespace = pkg
                    }
                }
            }
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
