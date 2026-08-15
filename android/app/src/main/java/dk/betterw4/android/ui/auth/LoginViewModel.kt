package dk.betterw4.android.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterw4.android.core.model.W4School
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.auth.AuthSessionInstaller
import dk.betterw4.android.core.w4.auth.W4OtpChallenge
import dk.betterw4.android.core.w4.session.LastSchoolHint
import dk.betterw4.android.core.w4.session.LastSchoolReason
import dk.betterw4.android.core.w4.session.LastSchoolStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject

data class LoginUiState(
    val username: String = "",
    val password: String = "",
    val otp: String = "",
    val otpChallenge: W4OtpChallenge? = null,
    val loggingIn: Boolean = false,
    val error: AppError? = null,
    val lastSchool: LastSchoolHint? = null,
) {
    val needsOtp: Boolean get() = otpChallenge != null
    val canSubmitPassword: Boolean
        get() = username.isNotBlank() && password.isNotBlank() && !loggingIn
    val canSubmitOtp: Boolean
        get() = otp.isNotBlank() && otpChallenge != null && !loggingIn
    val sessionExpired: Boolean
        get() = lastSchool?.reason == LastSchoolReason.SESSION_EXPIRED
}

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authSessionInstaller: AuthSessionInstaller,
    private val lastSchoolStore: LastSchoolStore,
) : ViewModel() {

    private val lastHint = lastSchoolStore.load()
    private val _state = MutableStateFlow(
        LoginUiState(
            lastSchool = lastHint,
            username = lastHint?.username.orEmpty(),
        ),
    )
    val state: StateFlow<LoginUiState> = _state.asStateFlow()

    private val loginInFlight = AtomicBoolean(false)

    fun onUsername(value: String) {
        _state.update { it.copy(username = value, error = null) }
    }

    fun onPassword(value: String) {
        _state.update { it.copy(password = value, error = null) }
    }

    fun onOtp(value: String) {
        _state.update { it.copy(otp = value, error = null) }
    }

    fun cancelOtp() {
        loginInFlight.set(false)
        _state.update {
            it.copy(
                otp = "",
                otpChallenge = null,
                loggingIn = false,
                error = null,
            )
        }
    }

    fun submitPassword() {
        val current = _state.value
        if (!current.canSubmitPassword) return
        if (!loginInFlight.compareAndSet(false, true)) return
        viewModelScope.launch {
            _state.update { it.copy(loggingIn = true, error = null) }
            when (
                val res = authSessionInstaller.loginWithPassword(current.username, current.password)
            ) {
                is AppResult.Success -> when (val outcome = res.data) {
                    is AuthSessionInstaller.W4AuthResult.LoggedIn -> onLoggedIn()
                    is AuthSessionInstaller.W4AuthResult.OtpRequired -> {
                        loginInFlight.set(false)
                        _state.update {
                            it.copy(
                                loggingIn = false,
                                otp = "",
                                otpChallenge = outcome.challenge,
                                password = "",
                            )
                        }
                    }
                }
                is AppResult.Failure -> {
                    loginInFlight.set(false)
                    _state.update { it.copy(loggingIn = false, error = res.error) }
                }
            }
        }
    }

    fun submitOtp() {
        val current = _state.value
        val challenge = current.otpChallenge ?: return
        if (!current.canSubmitOtp) return
        if (!loginInFlight.compareAndSet(false, true)) return
        viewModelScope.launch {
            _state.update { it.copy(loggingIn = true, error = null) }
            when (
                val res = authSessionInstaller.loginWithOtp(
                    challenge = challenge,
                    code = current.otp,
                    username = current.username,
                )
            ) {
                is AppResult.Success -> when (val outcome = res.data) {
                    is AuthSessionInstaller.W4AuthResult.LoggedIn -> onLoggedIn()
                    is AuthSessionInstaller.W4AuthResult.OtpRequired -> {
                        loginInFlight.set(false)
                        _state.update {
                            it.copy(loggingIn = false, otp = "", error = AppError.InvalidLogin)
                        }
                    }
                }
                is AppResult.Failure -> {
                    loginInFlight.set(false)
                    _state.update { it.copy(loggingIn = false, error = res.error) }
                }
            }
        }
    }

    fun enterDemo() {
        authSessionInstaller.enterDemo()
    }

    private fun onLoggedIn() {
        val username = _state.value.username.trim()
        LastSchoolHint.fromSchool(W4School.school, username = username)?.let { lastSchoolStore.save(it) }
        _state.update {
            it.copy(
                loggingIn = false,
                password = "",
                otp = "",
                otpChallenge = null,
                lastSchool = lastSchoolStore.load(),
            )
        }
    }
}
