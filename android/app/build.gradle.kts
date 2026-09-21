plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.findora"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 22+ requires this — without it, the
        // build fails with "Dependency ':flutter_local_notifications'
        // requires core library desugaring to be enabled". See the
        // matching `coreLibraryDesugaring` line in dependencies {} below.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.example.findora"
        // flutter_local_notifications 22+ also requires minSdk 24+ — Flutter's
        // own default (flutter.minSdkVersion) is currently lower than that,
        // so this is a hard override, not just a preference.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Required by flutter_local_notifications 22+ (see isCoreLibraryDesugaringEnabled
    // above). If Gradle complains this version is stale, check
    // https://mvnrepository.com/artifact/com.android.tools/desugar_jdk_libs
    // for the current one — this dependency doesn't come from pub.dev, so
    // `flutter pub outdated` won't ever flag it for you.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
