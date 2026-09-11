allprojects {
    repositories {
        google()
        mavenCentral()
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

// Some plugins (tflite_flutter, geolocator_android, and others) ship
// their own Android build config whose Kotlin target doesn't match their
// own Java target, which Kotlin now hard-fails on instead of just
// warning ("Inconsistent JVM Target Compatibility Between Java and
// Kotlin Tasks"). Rather than patch each plugin's own build file (which
// lives in the pub cache, not this project), align Kotlin's target to
// whatever Java target that same module already uses.
//
// Two earlier attempts at this both had real problems, kept here as a
// record of what NOT to do:
//   1. `subprojects { tasks.withType<JavaCompile>().configureEach {} }`
//      only partially applied — it fixed Kotlin but not Java, because
//      AGP sets each plugin's own `compileOptions` on its JavaCompile
//      task during that plugin's own configuration, which can run
//      *after* this block's action fires.
//   2. Forcing JavaCompile's sourceCompatibility/targetCompatibility to
//      17 directly via `gradle.taskGraph.whenReady` "fixed" the target
//      mismatch but broke something worse: it interfered with AGP's own
//      classpath wiring for that task, and android.jar (Android's SDK
//      classes) silently vanished from the compile classpath entirely —
//      surfacing as "package android.app does not exist" and similar
//      errors for basic Android classes.
//
// The safe version below never touches JavaCompile at all — it only
// reads each module's own (untouched, AGP-configured) Java target and
// points that module's Kotlin target at the same value, per project.
gradle.taskGraph.whenReady {
    allTasks
        .filterIsInstance<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
        .forEach { kotlinTask ->
            val javaTarget = kotlinTask.project.tasks
                .withType(JavaCompile::class.java)
                .firstOrNull()
                ?.targetCompatibility

            val jvmTarget = when (javaTarget) {
                "1.8", "8" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
                "9" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_9
                "11" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
                "17" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                "21" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
                // No JavaCompile task in this module, or an unrecognized
                // value — 17 matches what the app module itself targets.
                else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
            }
            kotlinTask.compilerOptions.jvmTarget.set(jvmTarget)
        }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
