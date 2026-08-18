package dk.betterw4.android.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.Lock
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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dk.betterw4.android.R
import dk.betterw4.android.core.i18n.asString
import dk.betterw4.android.core.i18n.toUiText
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

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
    var userDismissedUnlock by rememberSaveable { mutableStateOf(false) }
    var unlockHintRes by remember { mutableIntStateOf(0) }
    val promptInFlight = remember { AtomicBoolean(false) }

    fun hideKeyboard() {
        focusManager.clearFocus()
        keyboardController?.hide()
    }

    suspend fun launchUnlock(fromUser: Boolean) {
        if (state.loggingIn || state.needsOtp || !state.showUnlock) return
        if (!fromUser && userDismissedUnlock) return
        val activity = context.findFragmentActivity()
        if (activity == null) {
            viewModel.preferPasswordForm()
            return
        }
        if (!promptInFlight.compareAndSet(false, true)) return
        hideKeyboard()
        try {
            val maxAttempts = if (fromUser) 1 else 3
            var attempt = 0
            while (attempt < maxAttempts) {
                when (
                    activity.promptDeviceCredential(
                        title = context.getString(R.string.login_biometric_title),
                        subtitle = context.getString(R.string.login_biometric_subtitle),
                    )
                ) {
                    DeviceAuthResult.Success -> {
                        unlockHintRes = 0
                        viewModel.submitSavedLogin()
                        return
                    }
                    DeviceAuthResult.Unavailable -> {
                        viewModel.preferPasswordForm()
                        return
                    }
                    DeviceAuthResult.Lockout -> {
                        userDismissedUnlock = true
                        unlockHintRes = R.string.login_unlock_lockout
                        return
                    }
                    DeviceAuthResult.UserCanceled -> {
                        userDismissedUnlock = true
                        return
                    }
                    DeviceAuthResult.SystemCanceled -> {
                        attempt++
                        if (attempt >= maxAttempts) return
                        delay(320)
                    }
                }
            }
        } finally {
            promptInFlight.set(false)
        }
    }

    LaunchedEffect(Unit) {
        viewModel.onLoginScreenVisible()
    }

    LifecycleResumeEffect(state.showUnlock, state.loggingIn, userDismissedUnlock) {
        val job = scope.launch {
            if (!state.showUnlock || state.loggingIn || userDismissedUnlock) return@launch
            // Let the login fade-in finish so BiometricPrompt is not canceled by the
            // activity still settling (ERROR_CANCELED on first frame).
            delay(280)
            launchUnlock(fromUser = false)
        }
        onPauseOrDispose { job.cancel() }
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
        when {
            state.needsOtp -> OtpForm(
                state = state,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .imePadding(),
                onOtp = viewModel::onOtp,
                onSubmit = {
                    hideKeyboard()
                    viewModel.submitOtp()
                },
            )
            state.showUnlock -> UnlockPane(
                state = state,
                hintRes = unlockHintRes,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                onUnlock = {
                    userDismissedUnlock = false
                    scope.launch { launchUnlock(fromUser = true) }
                },
                onUsePassword = viewModel::preferPasswordForm,
            )
            else -> CredentialsForm(
                state = state,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .imePadding(),
                onUsername = viewModel::onUsername,
                onPassword = viewModel::onPassword,
                onSubmit = {
                    hideKeyboard()
                    viewModel.submitPassword()
                },
                onDemo = viewModel::enterDemo,
            )
        }
    }
}

@Composable
private fun UnlockPane(
    state: LoginUiState,
    hintRes: Int,
    modifier: Modifier = Modifier,
    onUnlock: () -> Unit,
    onUsePassword: () -> Unit,
) {
    Column(
        modifier = modifier.padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .size(96.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primaryContainer),
            contentAlignment = Alignment.Center,
        ) {
            if (state.loggingIn) {
                CircularProgressIndicator(
                    modifier = Modifier.size(36.dp),
                    strokeWidth = 3.dp,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            } else {
                Icon(
                    Icons.Default.Fingerprint,
                    contentDescription = null,
                    modifier = Modifier.size(44.dp),
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                )
            }
        }
        Spacer(Modifier.height(28.dp))
        Text(
            stringResource(
                if (state.loggingIn) R.string.login_signing_in else R.string.login_welcome_back,
            ),
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        if (state.username.isNotBlank()) {
            Spacer(Modifier.height(6.dp))
            Text(
                state.username,
                style = MaterialTheme.typography.titleMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        if (!state.loggingIn) {
            Spacer(Modifier.height(10.dp))
            Text(
                text = if (state.sessionExpired) {
                    stringResource(R.string.login_resume_session_expired_unlock_subtitle)
                } else {
                    stringResource(R.string.login_unlock_subtitle)
                },
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }

        val hint = when {
            state.error != null -> state.error.toUiText().asString()
            hintRes != 0 -> stringResource(hintRes)
            else -> null
        }
        if (!hint.isNullOrBlank() && !state.loggingIn) {
            Spacer(Modifier.height(16.dp))
            Text(
                text = hint,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                textAlign = TextAlign.Center,
            )
        }

        if (!state.loggingIn) {
            Spacer(Modifier.height(28.dp))
            Button(
                onClick = onUnlock,
                enabled = state.canSubmitUnlock,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(
                    Icons.Default.Fingerprint,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(10.dp))
                Text(stringResource(R.string.login_unlock))
            }
            TextButton(
                onClick = onUsePassword,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.login_use_password))
            }
        }
    }
}

@Composable
private fun CredentialsForm(
    state: LoginUiState,
    modifier: Modifier = Modifier,
    onUsername: (String) -> Unit,
    onPassword: (String) -> Unit,
    onSubmit: () -> Unit,
    onDemo: () -> Unit,
) {
    var passwordVisible by rememberSaveable { mutableStateOf(false) }

    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Spacer(Modifier.height(20.dp))
        Text(
            stringResource(R.string.app_name),
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.primary,
        )
        if (state.sessionExpired) {
            Text(
                stringResource(R.string.login_resume_session_expired_title),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Text(
            text = if (state.sessionExpired) {
                stringResource(R.string.login_resume_session_expired_subtitle)
            } else {
                stringResource(R.string.login_subtitle)
            },
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        OutlinedTextField(
            value = state.username,
            onValueChange = onUsername,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentType = ContentType.Username },
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

        OutlinedTextField(
            value = state.password,
            onValueChange = onPassword,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentType = ContentType.Password },
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
            keyboardActions = KeyboardActions(onDone = { onSubmit() }),
        )

        state.error?.let {
            Text(
                text = it.toUiText().asString(),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }

        Button(
            onClick = onSubmit,
            enabled = state.canSubmitPassword,
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (state.loggingIn) {
                CircularProgressIndicator(
                    Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onPrimary,
                )
                Spacer(Modifier.width(10.dp))
            }
            Text(
                stringResource(
                    if (state.loggingIn) R.string.login_signing_in else R.string.login_submit,
                ),
            )
        }

        TextButton(
            onClick = onDemo,
            enabled = !state.loggingIn,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(stringResource(R.string.login_demo))
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp, bottom = 24.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Outlined.Lock,
                contentDescription = null,
                modifier = Modifier.size(14.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.width(6.dp))
            Text(
                stringResource(R.string.login_password_destination),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun OtpForm(
    state: LoginUiState,
    modifier: Modifier = Modifier,
    onOtp: (String) -> Unit,
    onSubmit: () -> Unit,
) {
    Column(
        modifier
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Spacer(Modifier.height(8.dp))
        Text(
            stringResource(R.string.login_otp_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedTextField(
            value = state.otp,
            onValueChange = onOtp,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentType = ContentType.SmsOtpCode },
            label = { Text(stringResource(R.string.login_otp)) },
            singleLine = true,
            enabled = !state.loggingIn,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false,
                keyboardType = KeyboardType.Number,
                imeAction = ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(onDone = { onSubmit() }),
        )
        state.error?.let {
            Text(
                text = it.toUiText().asString(),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        Button(
            onClick = onSubmit,
            enabled = state.canSubmitOtp,
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (state.loggingIn) {
                CircularProgressIndicator(
                    Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onPrimary,
                )
                Spacer(Modifier.width(10.dp))
            }
            Text(
                stringResource(
                    if (state.loggingIn) R.string.login_verifying else R.string.login_otp_submit,
                ),
            )
        }
        Spacer(Modifier.height(24.dp))
    }
}
