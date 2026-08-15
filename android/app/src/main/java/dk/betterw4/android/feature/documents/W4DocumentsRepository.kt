package dk.betterw4.android.feature.documents

import dk.betterw4.android.core.cache.SimpleCache
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Client
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.core.w4.session.SessionController
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class W4DocumentsRepository @Inject constructor(
    private val client: W4Client,
    private val cache: SimpleCache,
    private val session: SessionController,
) {
    suspend fun load(
        folderId: String? = null,
        pageId: String? = null,
        force: Boolean = false,
    ): AppResult<W4DocumentListing> {
        val student = session.currentStudent ?: return AppResult.Failure(AppError.Unauthorized)
        if (student.isDemo) {
            return AppResult.Success(
                W4DocumentListing(
                    title = "Documents",
                    items = listOf(
                        W4DocumentNode("27", "Internal Information", W4DocumentKind.FOLDER, ""),
                        W4DocumentNode("34", "Outdoor Department", W4DocumentKind.FOLDER, ""),
                    ),
                ),
            )
        }
        val query = buildMap {
            folderId?.let { put("folder_id", it) }
            pageId?.let { put("page_id", it) }
        }
        val key = "docs_${student.studentId}_${folderId.orEmpty()}_${pageId.orEmpty()}"
        if (!force) {
            cache.get(key)?.let { return AppResult.Success(W4DocumentsParser.parse(it)) }
        }
        return when (val res = client.get(W4Urls.Routes.DOCUMENTS, query = query)) {
            is AppResult.Success -> {
                cache.put(key, res.data.body)
                AppResult.Success(W4DocumentsParser.parse(res.data.body))
            }
            is AppResult.Failure -> res
        }
    }
}
