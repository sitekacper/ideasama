import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Wczytanie właściwości keystore z pliku android/key.properties (jeśli istnieje)
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.ideasama.ideaapp.idea_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ideasama.ideaapp.idea_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Konfiguracja podpisywania release (z pliku key.properties lub zmiennych środowiskowych)
    signingConfigs {
        create("release") {
            val storeFilePath = (keystoreProperties["storeFile"] as String?) ?: System.getenv("ANDROID_KEYSTORE_PATH")
            val storePasswordProp = (keystoreProperties["storePassword"] as String?) ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
            val keyAliasProp = (keystoreProperties["keyAlias"] as String?) ?: System.getenv("ANDROID_KEY_ALIAS")
            val keyPasswordProp = (keystoreProperties["keyPassword"] as String?) ?: System.getenv("ANDROID_KEY_PASSWORD")

            if (!storeFilePath.isNullOrBlank()) {
                storeFile = file(storeFilePath)
            }
            if (!storePasswordProp.isNullOrBlank()) {
                storePassword = storePasswordProp
            }
            if (!keyAliasProp.isNullOrBlank()) {
                keyAlias = keyAliasProp
            }
            if (!keyPasswordProp.isNullOrBlank()) {
                keyPassword = keyPasswordProp
            }
        }
    }

    buildTypes {
        release {
            // Jeśli dostępne są dane do podpisu – użyj release; w innym wypadku fallback do debug, aby build nie blokował się lokalnie/CI bez kluczy
            val hasSigning = keystoreProperties.isNotEmpty() || System.getenv("ANDROID_KEYSTORE_PATH") != null
            signingConfig = if (hasSigning) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
