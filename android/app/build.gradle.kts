import org.gradle.api.tasks.Exec

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.compose.compiler)
}

android {
    namespace = "com.bbdyno.starjunkyard"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.bbdyno.starjunkyard"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = false
        }
    }

    sourceSets["main"].assets.srcDir("../../content")

    buildFeatures {
        compose = true
    }

    lint {
        // Versions are deliberately pinned to the GDD's API 36 / AGP 8.13 compatibility line.
        disable += setOf(
            "AndroidGradlePluginVersion",
            "GradleDependency",
            "NewerVersionAvailable",
            // AAPT still requires adaptive-icon XML in a v26-qualified directory.
            "ObsoleteSdkInt",
        )
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

val validateReleasePixelAssets by tasks.registering(Exec::class) {
    group = "verification"
    description = "Rejects release builds while development pixel assets remain planned."
    workingDir(rootProject.projectDir.parentFile)
    commandLine("python3", "tools/validate_project.py", "--release")
}

tasks.matching { it.name == "packageRelease" }.configureEach {
    dependsOn(validateReleasePixelAssets)
}

dependencies {
    implementation(project(":feature:combat"))

    val composeBom = platform(libs.compose.bom)
    implementation(composeBom)
    implementation(libs.compose.ui)
    implementation(libs.activity.compose)
    debugImplementation(libs.compose.ui.tooling)
}
