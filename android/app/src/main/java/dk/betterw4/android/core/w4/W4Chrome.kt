package dk.betterw4.android.core.w4

import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.w4.model.W4Response

/**
 * Chrome AJAX helpers (README §5.3). Campus status + notification bell.
 */
suspend fun W4Client.setCampusStatus(
    onCampus: Boolean,
    location: String? = null,
    priority: FetchPriority = FetchPriority.Important,
    credentials: W4Credentials? = null,
    studentId: String? = null,
): AppResult<W4Response> {
    val fields = linkedMapOf("status" to if (onCampus) "on" else "off")
    if (!onCampus && !location.isNullOrBlank()) {
        fields["location"] = location
    }
    return postAjax(
        routeOrUrl = W4Urls.Routes.SET_STATUS,
        fields = fields,
        priority = priority,
        credentials = credentials,
        studentId = studentId,
    )
}

suspend fun W4Client.refreshNotifications(
    priority: FetchPriority = FetchPriority.Opportunistic,
    credentials: W4Credentials? = null,
    studentId: String? = null,
): AppResult<W4Response> = postAjax(
    routeOrUrl = W4Urls.Routes.NOTIFICATIONS_REFRESH,
    fields = emptyMap(),
    priority = priority,
    credentials = credentials,
    studentId = studentId,
)

suspend fun W4Client.markNotificationRead(
    notificationId: String,
    priority: FetchPriority = FetchPriority.Important,
): AppResult<W4Response> = postAjax(
    routeOrUrl = W4Urls.Routes.NOTIFICATIONS_READ,
    fields = mapOf("notification_id" to notificationId),
    priority = priority,
)

suspend fun W4Client.markNotificationGroupRead(
    notificationType: String,
    priority: FetchPriority = FetchPriority.Important,
): AppResult<W4Response> = postAjax(
    routeOrUrl = W4Urls.Routes.NOTIFICATIONS_READ_GROUP,
    fields = mapOf("notification_type" to notificationType),
    priority = priority,
)

suspend fun W4Client.markAllNotificationsRead(
    priority: FetchPriority = FetchPriority.Important,
): AppResult<W4Response> = postAjax(
    routeOrUrl = W4Urls.Routes.NOTIFICATIONS_READ_ALL,
    fields = emptyMap(),
    priority = priority,
)

suspend fun W4Client.markAllNotificationEmailsRead(
    priority: FetchPriority = FetchPriority.Important,
): AppResult<W4Response> = postAjax(
    routeOrUrl = W4Urls.Routes.NOTIFICATIONS_READ_ALL_EMAILS,
    fields = emptyMap(),
    priority = priority,
)
