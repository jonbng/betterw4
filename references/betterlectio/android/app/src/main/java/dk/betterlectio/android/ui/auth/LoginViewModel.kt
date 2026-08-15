package dk.betterlectio.android.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.posthog.PostHog
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterlectio.android.core.lectio.auth.AuthSessionInstaller
import dk.betterlectio.android.core.lectio.session.LastSchoolHint
import dk.betterlectio.android.core.lectio.session.LastSchoolStore
import dk.betterlectio.android.core.model.School
import dk.betterlectio.android.core.result.AppError
import dk.betterlectio.android.core.result.AppResult
import dk.betterlectio.android.feature.auth.SchoolRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject

data class LoginUiState(
    val schools: List<School> = emptyList(),
    val filtered: List<School> = emptyList(),
    val query: String = "",
    val selected: School? = null,
    val loadingSchools: Boolean = true,
    val loggingIn: Boolean = false,
    val showWebView: Boolean = false,
    val error: AppError? = null,
    /** Non-null when appswitch Intent could not open MitID (e.g. app not installed). */
    val mitIdAppSwitchError: String? = null,
    /** Persisted last school for one-tap MitID after logout / session expiry. */
    val lastSchool: LastSchoolHint? = null,
    /**
     * When [lastSchool] is set, resume mode shows the one-tap CTA.
     * True after the user chooses “Vælg anden skole”.
     */
    val choosingOtherSchool: Boolean = false,
) {
    val showResume: Boolean
        get() = lastSchool != null && !choosingOtherSchool
}

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val schoolRepository: SchoolRepository,
    private val authSessionInstaller: AuthSessionInstaller,
    private val lastSchoolStore: LastSchoolStore,
) : ViewModel() {

    private val _state = MutableStateFlow(LoginUiState(lastSchool = lastSchoolStore.load()))
    val state: StateFlow<LoginUiState> = _state.asStateFlow()

    /** Session install in flight — separate from [LoginUiState.loggingIn] UI flag. */
    private val sessionInstallInFlight = AtomicBoolean(false)

    init {
        refreshSchools()
    }

    fun refreshSchools() {
        viewModelScope.launch {
            _state.update { it.copy(loadingSchools = true, error = null) }
            when (val res = schoolRepository.loadSchools()) {
                is AppResult.Success -> _state.update {
                    it.copy(
                        schools = res.data,
                        filtered = filter(res.data, it.query),
                        loadingSchools = false,
                    )
                }
                is AppResult.Failure -> _state.update {
                    it.copy(loadingSchools = false, error = res.error)
                }
            }
        }
    }

    fun onQuery(q: String) {
        _state.update {
            it.copy(query = q, filtered = filter(it.schools, q))
        }
    }

    /**
     * School pick is the primary CTA: real schools open MitID immediately,
     * demo enters the sandbox. Selection is kept if the user cancels the WebView
     * so [startMitId] remains available as a retry.
     */
    fun select(school: School) {
        _state.update { it.copy(selected = school, error = null) }
        if (school.isDemo) {
            enterDemo()
        } else {
            startMitId(source = "school_picker")
        }
    }

    /** One-tap MitID for the persisted last school. */
    fun resumeLastSchool() {
        val hint = _state.value.lastSchool ?: return
        _state.update {
            it.copy(
                selected = hint.toSchool(),
                choosingOtherSchool = false,
                error = null,
            )
        }
        startMitId(source = "last_school_resume")
    }

    fun chooseOtherSchool() {
        _state.update {
            it.copy(
                choosingOtherSchool = true,
                selected = null,
                query = "",
                filtered = filter(it.schools, ""),
                error = null,
            )
        }
    }

    fun backToResume() {
        if (_state.value.lastSchool == null) return
        _state.update {
            it.copy(
                choosingOtherSchool = false,
                selected = null,
                query = "",
                filtered = filter(it.schools, ""),
                error = null,
            )
        }
    }

    fun startMitId(source: String = "retry") {
        if (_state.value.selected == null) return
        if (_state.value.selected?.isDemo == true) {
            enterDemo()
            return
        }
        PostHog.capture(
            event = "login_started",
            properties = mapOf(
                "source" to source,
                "login_method" to "mitid",
            ),
        )
        sessionInstallInFlight.set(false)
        _state.update {
            it.copy(
                showWebView = true,
                loggingIn = false,
                error = null,
                mitIdAppSwitchError = null,
            )
        }
    }

    fun dismissWebView() {
        sessionInstallInFlight.set(false)
        _state.update {
            it.copy(
                showWebView = false,
                loggingIn = false,
                mitIdAppSwitchError = null,
            )
        }
    }

    fun onMitIdAppSwitchFailed(url: String) {
        PostHog.capture(
            event = "mitid_app_switch_failed",
            properties = mapOf("url_host" to (runCatching { java.net.URI(url).host }.getOrNull() ?: "unknown")),
        )
        _state.update { it.copy(mitIdAppSwitchError = url) }
    }

    fun clearMitIdAppSwitchError() {
        _state.update { it.copy(mitIdAppSwitchError = null) }
    }

    /**
     * Auth success URL hit — show overlay immediately while cookies settle / install runs.
     * Safe to call multiple times; does not start session install by itself.
     */
    fun onWebViewLoginDetected() {
        _state.update {
            it.copy(loggingIn = true, error = null, mitIdAppSwitchError = null)
        }
    }

    fun onWebViewLoginSuccess(callbackUrl: String) {
        val school = _state.value.selected ?: return
        // Guard against double-fire from onPageFinished + onResume / early nav.
        if (!sessionInstallInFlight.compareAndSet(false, true)) return
        viewModelScope.launch {
            _state.update { it.copy(loggingIn = true, error = null, mitIdAppSwitchError = null) }
            when (
                val res = authSessionInstaller.completeLoginFromWebView(
                    school = school,
                    callbackUrl = callbackUrl,
                )
            ) {
                is AppResult.Success -> {
                    LastSchoolHint.fromSchool(school)?.let { lastSchoolStore.save(it) }
                    _state.update {
                        it.copy(
                            loggingIn = false,
                            showWebView = false,
                            lastSchool = lastSchoolStore.load(),
                            choosingOtherSchool = false,
                        )
                    }
                }
                is AppResult.Failure -> {
                    sessionInstallInFlight.set(false)
                    PostHog.capture(
                        event = "login_failed",
                        properties = mapOf(
                            "login_method" to "mitid",
                            "error" to res.error.toString(),
                            "callback_host" to (
                                runCatching { java.net.URI(callbackUrl).host }.getOrNull()
                                    ?: "unknown"
                                ),
                        ),
                    )
                    _state.update {
                        it.copy(loggingIn = false, showWebView = false, error = res.error)
                    }
                }
            }
        }
    }

    fun enterDemo() {
        authSessionInstaller.enterDemo()
        // PostHog.capture("demo_entered") is called inside enterDemo()
    }

    private fun filter(schools: List<School>, q: String): List<School> {
        if (q.isBlank()) return schools
        return schools.filter { it.name.contains(q, ignoreCase = true) }
    }
}
