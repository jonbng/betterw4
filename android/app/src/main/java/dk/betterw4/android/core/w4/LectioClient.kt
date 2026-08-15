package dk.betterw4.android.core.w4

import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.model.FetchPriority
import dk.betterw4.android.core.w4.model.W4Credentials
import dk.betterw4.android.core.w4.model.W4Response
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Lectio-shaped HTTP façade kept so leftover compose/attachment code still compiles.
 * New W4 features should depend on [W4Client] directly.
 */
interface LectioClient {
    suspend fun get(
        pathOrUrl: String,
        priority: FetchPriority = FetchPriority.Important,
        credentials: W4Credentials? = null,
        studentId: String? = null,
        gymId: Int? = null,
    ): AppResult<W4Response>

    suspend fun postForm(
        pathOrUrl: String,
        fields: Map<String, String>,
        priority: FetchPriority = FetchPriority.Important,
        credentials: W4Credentials? = null,
        studentId: String? = null,
        gymId: Int? = null,
    ): AppResult<W4Response>

    suspend fun postback(
        pathOrUrl: String,
        eventTarget: String,
        extra: Map<String, String> = emptyMap(),
        priority: FetchPriority = FetchPriority.Important,
        credentials: W4Credentials? = null,
        studentId: String? = null,
        gymId: Int? = null,
    ): AppResult<W4Response>
}

@Singleton
class DefaultLectioClient @Inject constructor(
    private val w4: W4Client,
) : LectioClient {
    override suspend fun get(
        pathOrUrl: String,
        priority: FetchPriority,
        credentials: W4Credentials?,
        studentId: String?,
        gymId: Int?,
    ): AppResult<W4Response> = w4.get(
        routeOrUrl = pathOrUrl,
        priority = priority,
        credentials = credentials,
        studentId = studentId,
    )

    override suspend fun postForm(
        pathOrUrl: String,
        fields: Map<String, String>,
        priority: FetchPriority,
        credentials: W4Credentials?,
        studentId: String?,
        gymId: Int?,
    ): AppResult<W4Response> = w4.postForm(
        routeOrUrl = pathOrUrl,
        fields = fields,
        priority = priority,
        credentials = credentials,
        studentId = studentId,
    )

    override suspend fun postback(
        pathOrUrl: String,
        eventTarget: String,
        extra: Map<String, String>,
        priority: FetchPriority,
        credentials: W4Credentials?,
        studentId: String?,
        gymId: Int?,
    ): AppResult<W4Response> = w4.postForm(
        routeOrUrl = pathOrUrl,
        fields = extra + ("__EVENTTARGET" to eventTarget),
        priority = priority,
        credentials = credentials,
        studentId = studentId,
    )
}
