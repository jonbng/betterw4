package dk.betterlectio.android.feature.referral

import android.content.Context
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.suspendCancellableCoroutine
import timber.log.Timber
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

/**
 * Reads Play Install Referrer and extracts `bl_ref=<uuid>` set by referral-click.
 */
@Singleton
class InstallReferrerReader @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    suspend fun readReferralCookieId(): String? = suspendCancellableCoroutine { cont ->
        val client = InstallReferrerClient.newBuilder(context).build()
        val finished = AtomicBoolean(false)

        fun complete(value: String?) {
            if (!finished.compareAndSet(false, true)) return
            runCatching { client.endConnection() }
            if (cont.isActive) cont.resume(value)
        }

        cont.invokeOnCancellation {
            runCatching { client.endConnection() }
        }

        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    if (responseCode != InstallReferrerClient.InstallReferrerResponse.OK) {
                        Timber.d("InstallReferrer: responseCode=%d", responseCode)
                        complete(null)
                        return
                    }
                    val referrer = runCatching {
                        client.installReferrer.installReferrer
                    }.getOrNull()
                    complete(parseCookieId(referrer))
                }

                override fun onInstallReferrerServiceDisconnected() {
                    // Will retry on next call if needed; don't hang the coroutine.
                    complete(null)
                }
            })
        } catch (e: Exception) {
            Timber.w(e, "InstallReferrer: startConnection failed")
            complete(null)
        }
    }

    companion object {
        private val uuidRe =
            Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", RegexOption.IGNORE_CASE)

        fun parseCookieId(referrer: String?): String? {
            if (referrer.isNullOrBlank()) return null
            // referrer is a query-string style payload, e.g. "bl_ref=uuid&utm_source=…"
            for (part in referrer.split('&')) {
                val idx = part.indexOf('=')
                if (idx <= 0) continue
                val key = part.substring(0, idx)
                val value = part.substring(idx + 1)
                if (key == "bl_ref" && uuidRe.matches(value)) return value
            }
            return null
        }
    }
}
