package dk.betterw4.android.core.i18n

import dk.betterw4.android.feature.settings.AppLanguage
import org.junit.Assert.assertEquals
import org.junit.Test

class AppLocaleTest {
    @Test
    fun languageTags_mapsPreferences() {
        assertEquals("", AppLocale.languageTags(AppLanguage.SYSTEM))
        assertEquals("da", AppLocale.languageTags(AppLanguage.DANISH))
        assertEquals("en", AppLocale.languageTags(AppLanguage.ENGLISH))
    }
}
