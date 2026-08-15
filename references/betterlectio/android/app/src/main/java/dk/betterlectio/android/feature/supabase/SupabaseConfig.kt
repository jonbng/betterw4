package dk.betterlectio.android.feature.supabase

import dk.betterlectio.android.BuildConfig

/**
 * Optional Supabase configuration (iOS: `SupabaseConfiguration` / Info.plist).
 * When URL/key are blank or placeholders, all remote calls no-op and callers
 * use Lectio scrape / local storage.
 */
data class SupabaseConfig(
    val url: String,
    val publishableKey: String,
) {
    val isConfigured: Boolean
        get() = url.isNotBlank() &&
            publishableKey.isNotBlank() &&
            url.startsWith("http") &&
            !url.contains("YOUR_") &&
            !publishableKey.contains("YOUR_")

    companion object {
        /** Same public project as iOS Info.plist. */
        const val DEFAULT_URL = "https://uyyqxwlojqvbpukxgxem.supabase.co"

        fun fromBuildConfig(): SupabaseConfig = SupabaseConfig(
            url = BuildConfig.SUPABASE_URL.trim(),
            publishableKey = BuildConfig.SUPABASE_ANON_KEY.trim(),
        )
    }
}
