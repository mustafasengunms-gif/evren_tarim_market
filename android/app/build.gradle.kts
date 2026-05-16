plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // Burası böyle kalacak, doğru.
}

android {
    namespace = "com.evrentarim.evren_tarim_market"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.evrentarim.evren_tarim_market"

        // PDF ve ImagePicker gibi paketlerin daha kararlı çalışması için:
        minSdk = flutter.minSdkVersion

        targetSdk = flutter.targetSdkVersion
        // BURAYI DEĞİŞTİR ABİ:
        versionCode = 1          // 1'di, 2 yaptık
        versionName = "1.0.1"    // "1.0.0" dı, "1.0.1" yaptık
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
