package dk.betterw4.android.feature.homework

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class HomeworkDoneLwwTest {

    @Test
    fun donePrefsKey_is_scoped_per_student() {
        assertEquals("s1|999", HomeworkRepository.donePrefsKey("s1", "999"))
        assertEquals("s2|999", HomeworkRepository.donePrefsKey("s2", "999"))
        assertFalse(
            HomeworkRepository.donePrefsKey("s1", "999") ==
                HomeworkRepository.donePrefsKey("s2", "999"),
        )
        assertEquals("at_s1|999", HomeworkRepository.atPrefsKey("s1", "999"))
    }
}
