# BetterW4 ProGuard / R8 rules

# Timber
-dontwarn org.jetbrains.annotations.**

# kotlinx.serialization — keep serializers for our models + generated companions
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keep,includedescriptorclasses class dk.betterw4.android.**$$serializer { *; }
-keepclassmembers class dk.betterw4.android.** {
    *** Companion;
}
-keepclasseswithmembers class dk.betterw4.android.** {
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
