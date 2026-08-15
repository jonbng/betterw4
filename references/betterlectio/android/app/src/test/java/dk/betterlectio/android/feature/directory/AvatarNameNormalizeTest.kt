package dk.betterlectio.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Test

class AvatarNameNormalizeTest {
    @Test
    fun strips_parenthetical_codes_like_message_titles() {
        assertEquals(
            "mikkel peter sandholdt schultz",
            AvatarRepository.normalizeName("Mikkel Peter Sandholdt Schultz (MPS)"),
        )
        assertEquals(
            "eskil rønnov due",
            AvatarRepository.normalizeName("Eskil Rønnov Due (ED)"),
        )
        assertEquals(
            "jonathan arthur hojer bangert",
            AvatarRepository.normalizeName("Jonathan Arthur Hojer Bangert(k) (1x)"),
        )
    }

    @Test
    fun directory_plain_name_matches_message_title() {
        val fromDirectory = AvatarRepository.normalizeName("Mikkel Peter Sandholdt Schultz")
        val fromMessage = AvatarRepository.normalizeName("Mikkel Peter Sandholdt Schultz (MPS)")
        assertEquals(fromDirectory, fromMessage)
    }
}
