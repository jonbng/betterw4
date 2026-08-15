# BetterLectio ProGuard / R8 rules

# Timber
-dontwarn org.jetbrains.annotations.**

# --- Supabase Kotlin SDK (io.github.jan-tennert.supabase) ---
-keep class io.github.jan.supabase.** { *; }
-keep interface io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**

# Ktor (used by supabase-kt)
-keep class io.ktor.** { *; }
-dontwarn io.ktor.**
-dontwarn kotlinx.coroutines.**
-keepclassmembers class io.ktor.** { volatile <fields>; }

# kotlinx.serialization — keep serializers for our models + generated companions
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keep,includedescriptorclasses class dk.betterlectio.android.**$$serializer { *; }
-keepclassmembers class dk.betterlectio.android.** {
    *** Companion;
}
-keepclasseswithmembers class dk.betterlectio.android.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Generic kotlinx.serialization runtime
-keep class kotlinx.serialization.** { *; }
-keepclassmembers class kotlinx.serialization.** { *; }
-dontwarn kotlinx.serialization.**

# OkHttp / Jsoup
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class org.jsoup.** { *; }
