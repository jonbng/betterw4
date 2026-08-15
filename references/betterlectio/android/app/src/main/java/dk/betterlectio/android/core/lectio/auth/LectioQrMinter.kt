package dk.betterlectio.android.core.lectio.auth

import android.graphics.BitmapFactory
import android.util.Base64
import com.google.zxing.BinaryBitmap
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.common.HybridBinarizer
import dk.betterlectio.android.core.lectio.LectioClient
import dk.betterlectio.android.core.lectio.model.FetchPriority
import dk.betterlectio.android.core.lectio.model.LectioCredentials
import dk.betterlectio.android.core.lectio.scrape.LectioUrls
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import org.jsoup.Jsoup
import timber.log.Timber
import java.net.URI
import javax.inject.Inject
import javax.inject.Singleton

data class LectioQrCredentials(
    val qrId: String,
    val userId: String,
)

/**
 * Mints a Lectio login QR from studentIndstillinger (extension parity) so
 * [dk.betterlectio.android.feature.supabase.SupabaseAuthService] can call lectio-auth
 * without transferring Lectio session cookies.
 */
@Singleton
class LectioQrMinter @Inject constructor(
    private val lectioClient: LectioClient,
) {
    suspend fun mint(
        credentials: LectioCredentials,
        studentId: String,
        gymId: Int,
    ): AppResult<LectioQrCredentials> {
        val path = "indstillinger/studentIndstillinger.aspx"
        val postback = lectioClient.postback(
            pathOrUrl = path,
            eventTarget = EVENT_TARGET,
            priority = FetchPriority.Important,
            credentials = credentials,
            studentId = studentId,
            gymId = gymId,
        )
        if (postback is AppResult.Failure) return postback
        val html = (postback as AppResult.Success).data.body
        val imageRef = extractQrImageRef(html)
            ?: return AppResult.Failure(AppError.Parsing("Lectio QR image not found in settings response"))

        val imageBytes = when {
            imageRef.startsWith("data:") -> decodeDataUri(imageRef)
                ?: return AppResult.Failure(AppError.Parsing("Invalid Lectio QR data URI"))
            looksLikeBase64(imageRef) -> {
                runCatching { Base64.decode(imageRef, Base64.DEFAULT) }.getOrNull()
                    ?: return AppResult.Failure(AppError.Parsing("Invalid Lectio QR base64 payload"))
            }
            else -> {
                val absolute = absolutize(imageRef, gymId)
                when (val bytes = lectioClient.getBytes(
                    pathOrUrl = absolute,
                    priority = FetchPriority.Important,
                    credentials = credentials,
                    studentId = studentId,
                    gymId = gymId,
                )) {
                    is AppResult.Success -> bytes.data
                    is AppResult.Failure -> return bytes
                }
            }
        }

        val payload = decodeQrPayload(imageBytes)
            ?: return AppResult.Failure(AppError.Parsing("Failed to decode Lectio login QR"))
        return parseCredentials(payload)
    }

    private fun extractQrImageRef(html: String): String? {
        val initialize = INITIALIZE_RE.find(html)
        if (initialize != null) {
            val first = initialize.groupValues.getOrNull(1).orEmpty()
            val second = initialize.groupValues.getOrNull(2).orEmpty()
            if (first.isNotBlank()) return first
            if (second.isNotBlank()) return second
        }
        val doc = Jsoup.parse(html)
        val src = doc.selectFirst(".qrKode-container img")?.attr("src")
        return src?.takeIf { it.isNotBlank() && it != "about:blank" }
    }

    private fun decodeDataUri(value: String): ByteArray? {
        val comma = value.indexOf(',')
        if (comma <= 0) return null
        val meta = value.substring(0, comma)
        val payload = value.substring(comma + 1)
        return if (meta.contains(";base64", ignoreCase = true)) {
            runCatching { Base64.decode(payload, Base64.DEFAULT) }.getOrNull()
        } else {
            payload.toByteArray(Charsets.UTF_8)
        }
    }

    private fun looksLikeBase64(value: String): Boolean {
        if (value.length < 32) return false
        if (value.contains("://") || value.startsWith("/")) return false
        return value.all { it.isLetterOrDigit() || it == '+' || it == '/' || it == '=' || it.isWhitespace() }
    }

    private fun absolutize(raw: String, gymId: Int): String {
        if (raw.startsWith("http://") || raw.startsWith("https://")) return raw
        if (raw.startsWith("/")) return "${LectioUrls.ORIGIN}$raw"
        return LectioUrls.buildUrl(gymId, raw).toString()
    }

    private fun decodeQrPayload(bytes: ByteArray): String? {
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
        val source = RGBLuminanceSource(width, height, pixels)
        val binary = BinaryBitmap(HybridBinarizer(source))
        return runCatching {
            MultiFormatReader().decode(binary).text
        }.onFailure {
            Timber.w(it, "LectioQrMinter: ZXing decode failed")
        }.getOrNull()
    }

    private fun parseCredentials(payload: String): AppResult<LectioQrCredentials> {
        val uri = runCatching { URI(payload) }.getOrNull()
            ?: return AppResult.Failure(AppError.Parsing("Lectio QR payload is not a URL"))
        val query = uri.rawQuery.orEmpty()
        val params = query.split('&')
            .mapNotNull { part ->
                val eq = part.indexOf('=')
                if (eq <= 0) null
                else {
                    val key = part.substring(0, eq).lowercase()
                    val value = runCatching {
                        java.net.URLDecoder.decode(part.substring(eq + 1), Charsets.UTF_8.name())
                    }.getOrDefault(part.substring(eq + 1))
                    key to value
                }
            }
            .toMap()
        val qrId = params["qrid"].orEmpty()
        val userId = params["userid"].orEmpty()
        if (qrId.isBlank() || userId.isBlank()) {
            return AppResult.Failure(AppError.Parsing("Lectio QR payload missing userId/QrId"))
        }
        return AppResult.Success(LectioQrCredentials(qrId = qrId, userId = userId))
    }

    companion object {
        private const val EVENT_TARGET = "s\$m\$Content\$Content\$getQRcodeBtn"
        private val INITIALIZE_RE =
            Regex("""LectioQRCode\.Initialize\(\s*'[^']*'\s*,\s*'([^']*)'\s*,\s*'([^']*)'""")
    }
}
