package dk.betterlectio.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.temporal.ChronoUnit

class StudentProfileTest {
    @Test
    fun hasBetterLectio_whenAppInstalled() {
        val profile = StudentProfile(
            id = "1",
            appInstalledAt = "2026-01-01T00:00:00Z",
        )
        assertTrue(profile.hasBetterLectio)
    }

    @Test
    fun hasBetterLectio_whenRecentlySeen() {
        val recent = Instant.now().minus(2, ChronoUnit.DAYS).toString()
        val profile = StudentProfile(
            id = "1",
            lastSeenAt = recent,
        )
        assertTrue(profile.hasBetterLectio)
    }

    @Test
    fun hasBetterLectio_falseWhenUninstalled() {
        val recent = Instant.now().minus(1, ChronoUnit.DAYS).toString()
        val profile = StudentProfile(
            id = "1",
            lastSeenAt = recent,
            extensionUninstalledAt = "2026-01-01T00:00:00Z",
        )
        assertFalse(profile.hasBetterLectio)
    }

    @Test
    fun displayName_prefersPreferredName() {
        val profile = StudentProfile(id = "1", name = "Alex")
        assertEquals("Alex", profile.displayName("Alexander Hansen"))
    }

    @Test
    fun pictureUrl_prefersCustom() {
        val profile = StudentProfile(
            id = "1",
            customPfpUrl = "https://cdn/custom.jpg",
            lectioPfpUrl = "https://cdn/lectio.jpg",
        )
        assertEquals("https://cdn/custom.jpg", profile.pictureUrl("https://fallback.jpg"))
    }

    @Test
    fun formattedBirthday_respectsToggle() {
        val hidden = StudentProfile(
            id = "1",
            birthdate = "2008-05-12",
            showBirthday = false,
        )
        assertNull(hidden.formattedBirthday())

        val shown = hidden.copy(showBirthday = true)
        assertEquals("12. maj 2008", shown.formattedBirthday())
    }
}

class InstagramHandlesTest {
    @Test
    fun normalize_stripsAtAndUrl() {
        assertEquals("betterlectio", InstagramHandles.normalize("@betterlectio"))
        assertEquals(
            "betterlectio",
            InstagramHandles.normalize("https://www.instagram.com/betterlectio/"),
        )
    }

    @Test
    fun format_and_url() {
        assertEquals("@betterlectio", InstagramHandles.format("betterlectio"))
        assertEquals(
            "https://instagram.com/betterlectio",
            InstagramHandles.profileUrl("@betterlectio"),
        )
    }
}
