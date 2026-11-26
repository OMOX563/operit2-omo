// Fork 补丁：CI（GitHub runner）在国内镜像 maven.aliyun.com 返回 5xx 时，Gradle 会把该仓库
// 整条禁用并直接失败，后面的 google()/mavenCentral() 不会再兜底。设 OPERIT_GRADLE_NO_ALIYUN=1
// 可跳过国内镜像，只用官方仓库；本地构建不设该变量，行为不变。
val useAliyunMirror = System.getenv("OPERIT_GRADLE_NO_ALIYUN").isNullOrEmpty()

allprojects {
    buildscript {
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
        }
    }
    repositories {
        if (useAliyunMirror) {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
            maven { url = uri("https://jitpack.io") }
        } else {
            maven { url = uri("https://maven-central.storage-download.googleapis.com/maven2") }
        }
        google()
        mavenCentral()
        if (!useAliyunMirror) {
            maven { url = uri("https://jitpack.io") }
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
