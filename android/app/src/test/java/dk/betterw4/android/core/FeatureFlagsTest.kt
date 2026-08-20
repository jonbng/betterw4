package dk.betterw4.android.core

import dk.betterw4.android.feature.notifications.W4NotificationGroup
import dk.betterw4.android.feature.notifications.W4NotificationItem
import dk.betterw4.android.feature.notifications.W4NotificationSection
import dk.betterw4.android.feature.notifications.W4NotificationSeverity
import dk.betterw4.android.feature.notifications.W4NotificationSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FeatureFlagsTest {
    @Test
    fun mail_is_hidden() {
        assertFalse(FeatureFlags.MAIL_ENABLED)
    }

    @Test
    fun notification_display_strips_mailer_items_when_mail_is_hidden() {
        val snap = W4NotificationSnapshot(
            count = 3,
            taskGroups = listOf(
                W4NotificationGroup(
                    type = "assessment",
                    title = "Assessments",
                    severity = W4NotificationSeverity.OVERDUE,
                    items = listOf(
                        W4NotificationItem(
                            id = "1",
                            title = "Lab",
                            section = W4NotificationSection.TASK,
                        ),
                    ),
                ),
            ),
            emailGroups = listOf(
                W4NotificationGroup(
                    type = "email",
                    title = "Inbox",
                    severity = W4NotificationSeverity.NEW,
                    items = listOf(
                        W4NotificationItem(
                            id = "2",
                            title = "Hello",
                            href = "index.php?r=mailer/view&id=1",
                            section = W4NotificationSection.EMAIL,
                        ),
                    ),
                ),
            ),
        )
        val shown = snap.forDisplay()
        assertTrue(shown.emailGroups.isEmpty())
        assertEquals(1, shown.items.size)
        assertEquals("1", shown.items.single().id)
        assertEquals(2, shown.count)
    }
}
