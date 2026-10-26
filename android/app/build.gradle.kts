import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties().apply {
    val propertiesFile = rootProject.file("key.properties")
    if (propertiesFile.exists()) {
        propertiesFile.inputStream().use(::load)
    }
}

fun signingValue(propertyName: String, environmentName: String): String =
    keystoreProperties.getProperty(propertyName)
        ?: System.getenv(environmentName)
        ?: ""

android {
    namespace = "com.gryzion.passwordsaver"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.gryzion.passwordsaver"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
                ?: System.getenv("ANDROID_KEY_ALIAS")
                ?: "passwordsaver2026"
            keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
            // Resolve relative to android/ first, then android/app/.
            val storePath = keystoreProperties.getProperty("storeFile")
                ?: System.getenv("ANDROID_KEYSTORE_PATH")
                ?: "passwordsaver.jks"
            val fromAndroidRoot = rootProject.file(storePath)
            val fromAppModule = file(storePath)
            storeFile = when {
                fromAndroidRoot.isFile -> fromAndroidRoot
                fromAppModule.isFile -> fromAppModule
                else -> fromAppModule
            }
            storePassword =
                signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}
