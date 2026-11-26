pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    // Fork 补丁：CI 上设 OPERIT_GRADLE_NO_ALIYUN=1 跳过国内镜像（aliyun 5xx 会让 Gradle 直接失败）。
    // Maven Central 直连在 GitHub runner 上会被限流（HTTP 429），所以先走 Google 的官方镜像。
    val useAliyunMirror = System.getenv("OPERIT_GRADLE_NO_ALIYUN").isNullOrEmpty()

    repositories {
        if (useAliyunMirror) {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
        } else {
            maven { url = uri("https://maven-central.storage-download.googleapis.com/maven2") }
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("com.android.library") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("dev.rikka.tools.refine") version "4.4.0" apply false
    id("dev.rikka.tools.materialthemebuilder") version "1.5.1" apply false
}

include(":app")
include(":accessibilityCompanion")
project(":accessibilityCompanion").projectDir = file("../../../../tools/android-accessibility")
include(":windowServer")
project(":windowServer").projectDir = file("../../../../tools/android-ui-server")
include(":embeddedShizuku")
project(":embeddedShizuku").projectDir = file("../../../../tools/android-shizuku")
