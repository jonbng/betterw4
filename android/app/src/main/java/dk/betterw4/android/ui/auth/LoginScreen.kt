package dk.betterw4.android.ui.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dk.betterw4.android.R
import dk.betterw4.android.core.i18n.asString
import dk.betterw4.android.core.i18n.toUiText
import dk.betterw4.android.core.w4.session.LastSchoolReason
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoginScreen(
    viewModel: LoginViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var autoPrompted by rememberSaveable { mutableStateOf(false) }

    fun hideKeyboard() {
        focusManager.clearFocus()
        keyboardController?.hide()
    }

    fun launchUnlock() {
        val activity = context.findFragmentActivity()
        if (activity == null) {
            viewModel.preferPasswordForm()
            return
        }
        hideKeyboard()
        scope.launch {
            when (
                activity.promptDeviceCredential(
                    title = context.getString(R.string.login_biometric_title),
                    subtitle = context.getString(R.string.login_biometric_subtitle),
                )
            ) {
                DeviceAuthResult.Success -> viewModel.submitSavedLogin()
                DeviceAuthResult.Unavailable -> viewModel.preferPasswordForm()
                DeviceAuthResult.Canceled -> Unit
            }
        }
    }

    LaunchedEffect(Unit) {
        viewModel.refreshUnlockAvailability()
    }

    LaunchedEffect(state.showUnlock) {
        if (state.showUnlock && !autoPrompted && !state.loggingIn) {
            autoPrompted = true
            launchUnlock()
        }
    }

    Scaffold(
        topBar = {
            if (state.needsOtp) {
                TopAppBar(
                    title = { Text(stringResource(R.string.login_otp_title)) },
                    navigationIcon = {
                        IconButton(
                            onClick = viewModel::cancelOtp,
                            enabled = !state.loggingIn,
                        ) {
                            Icon(
                                Icons.AutoMirrored.Filled.ArrowBack,
                                contentDescription = stringResource(R.string.action_cancel),
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                    ),
                )
            }
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (!state.needsOtp) {
                Spacer(Modifier.height(20.dp))
                Text(
                    stringResource(R.string.app_name),
                    style = MaterialTheme.typography.displaySmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(
                    text = when {
                        state.showUnlock && state.sessionExpired ->
                            stringResource(R.string.login_resume_session_expired_unlock_subtitle)
                        state.showUnlock -> stringResource(R.string.login_unlock_subtitle)
                        state.lastSchool?.reason == LastSchoolReason.SESSION_EXPIRED ->
                            stringResource(R.string.login_resume_session_expired_subtitle)
                        else -> stringResource(R.string.login_subtitle)
                    },
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (state.sessionExpired) {
                    Text(
                        stringResource(R.string.login_resume_session_expired_title),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                if (state.showUnlock && state.username.isNotBlank()) {
                    Text(
                        stringResource(R.string.login_unlock_as, state.username),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            } else {
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.login_otp_subtitle),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            if (state.needsOtp) {
                OutlinedTextField(
                    value = state.otp,
                    onValueChange = viewModel::onOtp,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.login_otp)) },
                    singleLine = true,
                    enabled = !state.loggingIn,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        autoCorrectEnabled = false,
                        keyboardType = KeyboardType.Number,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(
                        onDone = {
                            hideKeyboard()
                            viewModel.submitOtp()
                        },
                    ),
                )
            } else if (!state.showUnlock) {
                OutlinedTextField(
                    value = state.username,
                    onValueChange = viewModel::onUsername,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.login_username)) },
                    placeholder = { Text(stringResource(R.string.login_username_hint)) },
                    singleLine = true,
                    enabled = !state.loggingIn,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        autoCorrectEnabled = false,
                        keyboardType = KeyboardType.Ascii,
                        imeAction = ImeAction.Next,
                    ),
                )

                var passwordVisible by rememberSaveable { mutableStateOf(false) }
                OutlinedTextField(
                    value = state.password,
                    onValueChange = viewModel::onPassword,
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.login_password)) },
                    singleLine = true,
                    enabled = !state.loggingIn,
                    visualTransformation = if (passwordVisible) {
                        VisualTransformation.None
                    } else {
                        PasswordVisualTransformation()
                    },
                    trailingIcon = {
                        IconButton(onClick = { passwordVisible = !passwordVisible }) {
                            Icon(
                                if (passwordVisible) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                contentDescription = stringResource(
                                    if (passwordVisible) {
                                        R.string.login_password_hide
                                    } else {
                                        R.string.login_password_show
                                    },
                                ),
                            )
                        }
                    },
                    keyboardOptions = KeyboardOptions(
                        autoCorrectEnabled = false,
                        keyboardType = KeyboardType.Password,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(
                        onDone = {
                            hideKeyboard()
                            viewModel.submitPassword()
                        },
                    ),
                )
            }

            state.error?.let {
                Text(
                    text = it.toUiText().asString(),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }

            Button(
                onClick = {
                    hideKeyboard()
                    when {
                        state.needsOtp -> viewModel.submitOtp()
                        state.showUnlock -> launchUnlock()
                        else -> viewModel.submitPassword()
                    }
                },
                enabled = when {
                    state.needsOtp -> state.canSubmitOtp
                    state.showUnlock -> state.canSubmitUnlock
                    else -> state.canSubmitPassword
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (state.loggingIn) {
                    CircularProgressIndicator(
                        Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                    Spacer(Modifier.width(10.dp))
                } else if (state.showUnlock) {
                    Icon(
                        Icons.Default.Fingerprint,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                    )
                    Spacer(Modifier.width(10.dp))
                }
                Text(
                    stringResource(
                        when {
                            state.needsOtp -> R.string.login_otp_submit
                            state.showUnlock -> R.string.login_unlock
                            else -> R.string.login_submit
                        },
                    ),
                )
            }

            if (state.showUnlock) {
                TextButton(
                    onClick = viewModel::preferPasswordForm,
                    enabled = !state.loggingIn,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(stringResource(R.string.login_use_password))
                }
            }

            if (!state.needsOtp) {
                TextButton(
                    onClick = viewModel::enterDemo,
                    enabled = !state.loggingIn,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(stringResource(R.string.login_demo))
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}
