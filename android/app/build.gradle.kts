import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")

    // Plugin do Google Services para Firebase
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.jflivre"
    compileSdk = 36 // ✅ atualizado para compatibilidade com geolocator e google_maps_flutter
    ndkVersion = "27.0.12077973" // continua compatível

    defaultConfig {
        applicationId = "com.example.jflivre"
        minSdk = 23
        targetSdk = 36 // ✅ atualizado
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    // 🔑 Configuração da keystore com verificação
    val keystorePropertiesFile = file("../key.properties")
    val keystoreProperties = Properties()

    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
        println("✅ key.properties encontrado e carregado")
    } else {
        println("⚠️ key.properties NÃO encontrado em ${keystorePropertiesFile.absolutePath}")
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                val storePath = keystoreProperties["storeFile"] as String
                val storeFileObj = file(storePath)
                if (storeFileObj.exists()) {
                    storeFile = storeFileObj
                    storePassword = keystoreProperties["storePassword"] as String
                    keyAlias = keystoreProperties["keyAlias"] as String
                    keyPassword = keystoreProperties["keyPassword"] as String
                    println("✅ Keystore encontrada em $storePath")
                } else {
                    println("⚠️ Keystore NÃO encontrada em $storePath")
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // 🔹 Firebase com versões explícitas (FlutLab e Codemagic compatíveis)
    implementation("com.google.firebase:firebase-auth-ktx:22.3.0")
    implementation("com.google.firebase:firebase-firestore-ktx:24.9.3")
    implementation("com.google.firebase:firebase-analytics-ktx:21.5.0")
}

flutter {
    source = "../.."
}
