package dk.betterw4.android.feature.notifications

/**
 * Pure snapshot diff so WorkManager only fires on *new* changes, not re-fires.
 */
object NotificationSnapshotDiff {
    fun newIds(previous: Set<String>, current: Set<String>): Set<String> =
        current - previous

    fun eventKey(id: String, status: String): String = "event:$id:$status"
    fun messageKey(id: String): String = "msg:$id"
    fun assignmentKey(id: String, status: String): String = "asg:$id:$status"
    fun w4Key(id: String): String = "w4:$id"
}
