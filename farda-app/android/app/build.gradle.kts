plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
val releaseApplicationId = System.getenv("FARDA_ANDROID_APPLICATION_ID")
val releaseStorePath = System.getenv("FARDA_ANDROID_KEYSTORE_PATH")
val releaseStorePassword = System.getenv("FARDA_ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("FARDA_ANDROID_KEY_ALIAS")
val releaseKeyPassword = System.getenv("FARDA_ANDROID_KEY_PASSWORD")
val releaseSigningConfigured = listOf(
    releaseStorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

if (releaseRequested) {
    if (releaseApplicationId.isNullOrBlank() || releaseApplicationId == "com.example.farda") {
        throw GradleException("Set FARDA_ANDROID_APPLICATION_ID to the approved production application ID before building a release.")
    }
    if (!releaseSigningConfigured || !file(releaseStorePath!!).isFile) {
        throw GradleException("Set a readable FARDA_ANDROID_KEYSTORE_PATH and all FARDA_ANDROID_KEY_* signing variables before building a release.")
    }
}

android {
    namespace = "com.example.farda"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = releaseApplicationId?.takeIf { it.isNotBlank() } ?: "com.example.farda"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (releaseSigningConfigured) {
        signingConfigs.create("release") {
            storeFile = file(releaseStorePath!!)
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}
