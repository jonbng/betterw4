package dk.betterlectio.android.core.result

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AppResultTest {

    @Test
    fun map_transforms_success() {
        val result = AppResult.Success(2).map { it * 3 }
        assertEquals(6, result.getOrNull())
    }

    @Test
    fun map_preserves_failure() {
        val result: AppResult<Int> = AppResult.Failure(AppError.Offline)
        assertTrue(result.map { it + 1 }.isFailure)
        assertEquals(AppError.Offline, result.errorOrNull())
    }

    @Test
    fun appRunCatching_wraps_exceptions() {
        val result = appRunCatching { error("boom") }
        assertTrue(result.isFailure)
        assertTrue(result.errorOrNull() is AppError.Unknown)
    }
}
