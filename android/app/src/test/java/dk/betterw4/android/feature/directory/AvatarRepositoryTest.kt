package dk.betterw4.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AvatarRepositoryTest {
    @Test
    fun normalize_strips_parentheticals_and_folds_diacritics() {
        assertEquals(
            "istvan poor",
            AvatarRepository.normalizeName("István Poór"),
        )
        assertEquals(
            "istvan poor",
            AvatarRepository.normalizeName("Istvan Poor (IP)"),
        )
        assertEquals(
            "jonathan arthur hojer bangert",
            AvatarRepository.normalizeName("Jonathan Arthur Hojer Bangert(k) (1x)"),
        )
    }

    @Test
    fun peek_derives_w4_portrait_from_uwc_id() {
        val index = AvatarIndex()
        val url = index.peek(teacherNumericId = "nc16jmac")
        assertEquals(
            "https://w4.uwcrcn.no/files/user_photos/nc16jmac_photo.jpg",
            url,
        )
    }

    @Test
    fun peek_resolves_calendar_teacher_name_after_catalog_ingest() {
        val index = AvatarIndex()
        assertNull(index.peek(name = "István Poór"))

        index.ingest(
            listOf(
                DirectoryEntity(
                    id = "nc16ipoo",
                    name = "Istvan Poor",
                    kind = DirectoryEntityKind.TEACHER,
                    avatarUrl = "https://w4.uwcrcn.no/files/user_photos/nc16ipoo_thumb.jpg",
                ),
            ),
        )

        val url = index.peek(name = "István Poór")
        assertEquals(
            "https://w4.uwcrcn.no/files/user_photos/nc16ipoo_photo.jpg",
            url,
        )
    }

    @Test
    fun ingest_guesses_portrait_when_directory_row_has_no_photo() {
        val index = AvatarIndex()
        index.ingest(
            listOf(
                DirectoryEntity(
                    id = "nc16jmac",
                    name = "Jane MacLeod",
                    kind = DirectoryEntityKind.TEACHER,
                    avatarUrl = null,
                ),
            ),
        )
        val url = index.peek(name = "Jane MacLeod")
        assertTrue(url!!.contains("/files/user_photos/nc16jmac_photo.jpg"))
    }

    @Test
    fun remember_indexes_name_for_later_peek() {
        val index = AvatarIndex()
        index.remember(
            entityId = "nc25eros",
            url = "https://w4.uwcrcn.no/files/user_photos/nc25eros_thumb.jpg",
            name = "Elena Rossi",
        )
        assertEquals(
            "https://w4.uwcrcn.no/files/user_photos/nc25eros_photo.jpg",
            index.peek(name = "Elena Rossi"),
        )
    }
}
