package dk.betterlectio.android.feature.referral

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class InstallReferrerReaderTest {
    @Test
    fun parsesBlRefFromReferrer() {
        val id = "550e8400-e29b-41d4-a716-446655440000"
        assertEquals(id, InstallReferrerReader.parseCookieId("bl_ref=$id"))
        assertEquals(
            id,
            InstallReferrerReader.parseCookieId("utm_source=google&bl_ref=$id&utm_medium=organic"),
        )
    }

    @Test
    fun rejectsMissingOrInvalid() {
        assertNull(InstallReferrerReader.parseCookieId(null))
        assertNull(InstallReferrerReader.parseCookieId(""))
        assertNull(InstallReferrerReader.parseCookieId("utm_source=google"))
        assertNull(InstallReferrerReader.parseCookieId("bl_ref=not-a-uuid"))
    }
}
