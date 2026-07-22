plugins {

    id("com.android.application")

    id("org.jetbrains.kotlin.android")

    id("org.jetbrains.kotlin.plugin.compose")

    id("com.google.gms.google-services")

}



android {

    namespace = "com.adplay.app"

    compileSdk = 35



    defaultConfig {

        applicationId = "com.adplay.app"

        minSdk = 26

        targetSdk = 35

        versionCode = 1

        versionName = "1.0.0"

        buildConfigField("String", "ADSBITVEX_APP_ID", "\"000241\"")

    }



    buildFeatures {

        compose = true

        buildConfig = true

    }



    compileOptions {

        sourceCompatibility = JavaVersion.VERSION_17

        targetCompatibility = JavaVersion.VERSION_17

    }

    kotlinOptions {

        jvmTarget = "17"

    }



    packaging {

        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"

    }

}



dependencies {

    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")

    implementation(composeBom)

    implementation("androidx.compose.ui:ui")

    implementation("androidx.compose.ui:ui-tooling-preview")

    implementation("androidx.compose.material3:material3")

    implementation("androidx.compose.foundation:foundation")

    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")

    implementation("com.google.code.gson:gson:2.11.0")



    val firebaseBom = platform("com.google.firebase:firebase-bom:33.7.0")

    implementation(firebaseBom)

    implementation("com.google.firebase:firebase-auth-ktx")

    implementation("com.google.firebase:firebase-functions-ktx")

    implementation("com.google.firebase:firebase-firestore-ktx")



    debugImplementation("androidx.compose.ui:ui-tooling")

}


