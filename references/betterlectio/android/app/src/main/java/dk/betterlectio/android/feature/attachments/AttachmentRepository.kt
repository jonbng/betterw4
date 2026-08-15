package dk.betterlectio.android.feature.attachments

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import dagger.hilt.android.qualifiers.ApplicationContext
import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.model.FetchPriority
import dk.betterlectio.android.core.lectio.model.LectioResponse
import dk.betterlectio.android.core.lectio.scrape.LectioHtml
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

data class CachedAttachment(
    val file: File,
    val displayName: String,
    val mimeType: String,
    val contentUri: Uri,
)

/**
 * Authenticated Lectio download + FileProvider open/save/share.
 *
 * Lectio `GetFile.aspx` requires session cookies; opening the URL in the browser fails.
 */
@Singleton
class AttachmentRepository @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val lectioClient: LectioClient,
    private val cache: AttachmentCache,
) {
    private val authority: String = "${context.packageName}.fileprovider"

    suspend fun open(ref: AttachmentRef): AttachmentActionResult = withContext(Dispatchers.IO) {
        when (ref.kind) {
            AttachmentKind.WEB_LINK -> openWebLink(ref.url)
            AttachmentKind.IMAGE -> AttachmentActionResult.ImagePreview
            AttachmentKind.FILE -> openFile(ref)
        }
    }

    suspend fun save(ref: AttachmentRef): AttachmentActionResult = withContext(Dispatchers.IO) {
        when (val prepared = prepareFile(ref)) {
            is AppResult.Failure -> AttachmentActionResult.Failed(mapError(prepared.error))
            is AppResult.Success -> {
                try {
                    saveToDownloads(prepared.data)
                    AttachmentActionResult.Saved
                } catch (e: Exception) {
                    Timber.w(e, "Save to Downloads failed")
                    AttachmentActionResult.Failed(AttachmentError.GENERIC)
                }
            }
        }
    }

    suspend fun share(ref: AttachmentRef): AttachmentActionResult = withContext(Dispatchers.IO) {
        when (val prepared = prepareFile(ref)) {
            is AppResult.Failure -> AttachmentActionResult.Failed(mapError(prepared.error))
            is AppResult.Success -> {
                try {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = prepared.data.mimeType
                        putExtra(Intent.EXTRA_STREAM, prepared.data.contentUri)
                        putExtra(Intent.EXTRA_SUBJECT, prepared.data.displayName)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        clipData = ClipData.newUri(
                            context.contentResolver,
                            prepared.data.displayName,
                            prepared.data.contentUri,
                        )
                    }
                    val chooser = Intent.createChooser(send, prepared.data.displayName).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    context.startActivity(chooser)
                    AttachmentActionResult.Shared
                } catch (e: Exception) {
                    Timber.w(e, "Share failed")
                    AttachmentActionResult.Failed(AttachmentError.GENERIC)
                }
            }
        }
    }

    private suspend fun openFile(ref: AttachmentRef): AttachmentActionResult {
        return when (val prepared = prepareFile(ref)) {
            is AppResult.Failure -> AttachmentActionResult.Failed(mapError(prepared.error))
            is AppResult.Success -> openWithViewer(prepared.data)
        }
    }

    private suspend fun prepareFile(ref: AttachmentRef): AppResult<CachedAttachment> {
        val absolute = AttachmentClassifier.absolutize(ref.url)

        cache.find(absolute)?.let { cached ->
            return AppResult.Success(toCachedAttachment(cached, ref.name))
        }

        return when (val result = lectioClient.get(absolute, priority = FetchPriority.Important)) {
            is AppResult.Failure -> result
            is AppResult.Success -> materialize(result.data, ref, absolute)
        }
    }

    private fun toCachedAttachment(file: File, preferredName: String): CachedAttachment {
        val header = file.inputStream().use { stream ->
            val buf = ByteArray(64)
            val n = stream.read(buf)
            if (n <= 0) ByteArray(0) else buf.copyOf(n)
        }
        val nameFromCache = file.name.substringAfter(AttachmentCache.SEP, missingDelimiterValue = file.name)
        val displayBase = preferredName.takeIf { it.isNotBlank() } ?: nameFromCache
        val mime = AttachmentMime.resolve(displayBase, null, header)
        val displayName = AttachmentMime.ensureExtension(
            AttachmentMime.sanitizeFileName(displayBase),
            mime,
        )
        return CachedAttachment(
            file = file,
            displayName = displayName,
            mimeType = mime,
            contentUri = FileProvider.getUriForFile(context, authority, file),
        )
    }

    private fun materialize(
        response: LectioResponse,
        ref: AttachmentRef,
        absoluteUrl: String,
    ): AppResult<CachedAttachment> {
        val bytes = response.bytes
        if (bytes.isEmpty()) {
            return AppResult.Failure(AppError.Unknown("Empty file"))
        }

        val contentType = AttachmentMime.normalizeContentType(response.contentType)
        if (looksLikeHtmlFailure(bytes, contentType, response.body)) {
            return if (
                LectioHtml.isLoginPageUrl(response.finalUrl.toString()) ||
                response.body.contains("login.aspx", ignoreCase = true)
            ) {
                AppResult.Failure(AppError.SessionExpired)
            } else {
                AppResult.Failure(AppError.Parsing("HTML instead of file"))
            }
        }

        val fromDisposition = AttachmentMime.filenameFromContentDisposition(response.contentDisposition)
        val displayBase = fromDisposition
            ?: ref.name.takeIf { it.isNotBlank() }
            ?: absoluteUrl.substringAfterLast('/').substringBefore('?').ifBlank { "attachment" }

        val mime = AttachmentMime.resolve(displayBase, response.contentType, bytes)
        val displayName = AttachmentMime.ensureExtension(
            AttachmentMime.sanitizeFileName(displayBase),
            mime,
        )

        val file = cache.put(absoluteUrl, displayName, bytes)
        val uri = FileProvider.getUriForFile(context, authority, file)
        return AppResult.Success(
            CachedAttachment(
                file = file,
                displayName = displayName,
                mimeType = mime,
                contentUri = uri,
            ),
        )
    }

    private fun looksLikeHtmlFailure(
        bytes: ByteArray,
        contentType: String?,
        body: String,
    ): Boolean {
        if (contentType?.startsWith("text/html") == true) return true
        if (LectioHtml.isRobotDetectionPage(body)) return true
        val sample = body.take(512).trimStart().lowercase()
        if (sample.startsWith("<!doctype html") || sample.startsWith("<html")) return true
        if (AttachmentMime.sniff(bytes) == null &&
            (sample.contains("<form") || sample.contains("login.aspx"))
        ) {
            return true
        }
        return false
    }

    private fun openWithViewer(cached: CachedAttachment): AttachmentActionResult {
        // Prefer the user's default app for this MIME type (no createChooser).
        // Android only shows a disambiguation UI when there is no preferred default.
        fun viewIntent(mime: String) = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(cached.contentUri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(viewIntent(cached.mimeType))
            AttachmentActionResult.Opened
        } catch (_: ActivityNotFoundException) {
            try {
                context.startActivity(viewIntent("*/*"))
                AttachmentActionResult.Opened
            } catch (_: ActivityNotFoundException) {
                AttachmentActionResult.Failed(AttachmentError.NO_APP)
            } catch (e: Exception) {
                Timber.w(e, "Open viewer failed")
                AttachmentActionResult.Failed(AttachmentError.GENERIC)
            }
        } catch (e: Exception) {
            Timber.w(e, "Open viewer failed")
            AttachmentActionResult.Failed(AttachmentError.GENERIC)
        }
    }

    private fun openWebLink(url: String): AttachmentActionResult {
        val absolute = AttachmentClassifier.absolutize(url)
        return try {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(absolute)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            AttachmentActionResult.WebLinkOpened
        } catch (_: ActivityNotFoundException) {
            AttachmentActionResult.Failed(AttachmentError.NO_APP)
        } catch (e: Exception) {
            Timber.w(e, "Open web link failed")
            AttachmentActionResult.Failed(AttachmentError.GENERIC)
        }
    }

    private fun saveToDownloads(cached: CachedAttachment) {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, cached.displayName)
            put(MediaStore.Downloads.MIME_TYPE, cached.mimeType)
            put(MediaStore.Downloads.IS_PENDING, 1)
            put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/BetterLectio")
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val itemUri = resolver.insert(collection, values)
            ?: error("MediaStore insert failed")
        resolver.openOutputStream(itemUri)?.use { out ->
            cached.file.inputStream().use { it.copyTo(out) }
        } ?: error("MediaStore openOutputStream failed")
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(itemUri, values, null, null)
    }

    private fun mapError(error: AppError): AttachmentError = when (error) {
        AppError.Offline -> AttachmentError.OFFLINE
        AppError.SessionExpired, AppError.Unauthorized -> AttachmentError.SESSION
        AppError.RobotDetection -> AttachmentError.ROBOT
        is AppError.Network -> AttachmentError.OFFLINE
        is AppError.Parsing -> AttachmentError.HTML_INSTEAD_OF_FILE
        is AppError.Unknown ->
            if (error.message?.contains("Empty", ignoreCase = true) == true) {
                AttachmentError.EMPTY
            } else {
                AttachmentError.GENERIC
            }
        else -> AttachmentError.GENERIC
    }

    fun clearCache() = cache.clear()
}
