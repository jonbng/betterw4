package dk.betterlectio.android.core.i18n

import android.app.LocaleManager
import android.content.Context
import android.os.Build
import android.os.LocaleList
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import dk.betterlectio.android.feature.settings.AppLanguage

/**
 * Applies the user's language preference via Android per-app locales.
 *
 * Empty list = follow system language.
 *
 * On API 33+ we call [LocaleManager] with an application [Context] so the change
 * does not depend on an active [androidx.appcompat.app.AppCompatActivity] delegate
 * (AppCompatDelegate.setApplicationLocales is a no-op without one on API 33+).
 * Below API 33 we use AppCompat, which needs an AppCompatActivity in the task.
 */
object AppLocale {
    fun apply(language: AppLanguage, context: Context? = null) {
        val tags = languageTags(language)
        if (Build.VERSION.SDK_INT >= 33 && context != null) {
            val localeManager = context.applicationContext
                .getSystemService(LocaleManager::class.java)
            localeManager.applicationLocales =
                if (tags.isEmpty()) LocaleList.getEmptyLocaleList()
                else LocaleList.forLanguageTags(tags)
            return
        }
        val locales = if (tags.isEmpty()) {
            LocaleListCompat.getEmptyLocaleList()
        } else {
            LocaleListCompat.forLanguageTags(tags)
        }
        AppCompatDelegate.setApplicationLocales(locales)
    }

    /** BCP 47 tags for [language], or empty string for system default. */
    fun languageTags(language: AppLanguage): String = when (language) {
        AppLanguage.SYSTEM -> ""
        AppLanguage.DANISH -> "da"
        AppLanguage.ENGLISH -> "en"
    }
}
