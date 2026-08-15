package dk.betterlectio.android.feature.profilepicture

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProfilePictureStateTest {
    @Test
    fun pendingIncludesUploadingAndPending() {
        assertTrue(stateWith("uploading").isPending)
        assertTrue(stateWith("pending").isPending)
        assertFalse(stateWith("approved").isPending)
    }

    @Test
    fun rejectedIsRetryableState() {
        assertTrue(stateWith("rejected").wasRejected)
        assertFalse(stateWith("pending").wasRejected)
    }

    private fun stateWith(status: String) = ProfilePictureState(
        submission = ProfilePictureSubmission("id", status, "2026-08-01T00:00:00Z"),
    )
}
