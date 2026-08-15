package dk.betterw4.android

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dagger.hilt.android.AndroidEntryPoint
import dk.betterw4.android.core.w4.auth.AuthSessionInstaller
import dk.betterw4.android.core.w4.session.AuthState
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.live.LiveLessonNotifier
import dk.betterw4.android.feature.live.LiveLessonScheduler
import dk.betterw4.android.feature.notifications.NotificationDiffWorker
import dk.betterw4.android.feature.settings.AppearanceMode
import dk.betterw4.android.feature.settings.SettingsStore
import dk.betterw4.android.ui.navigation.BetterW4Root
import dk.betterw4.android.ui.theme.BetterW4Theme
import javax.inject.Inject

/**
 * [AppCompatActivity] (not ComponentActivity) so per-app language works on API 29–32
 * via AppCompatDelegate, and so AppCompat has an active delegate when needed.
 * On API 33+ [dk.betterw4.android.core.i18n.AppLocale] uses LocaleManager directly.
 */
@AndroidEntryPoint
class MainActivity : AppCompatActivity() {
    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { /* A denied permission leaves notifications disabled; the app continues normally. */ }

    @Inject
    lateinit var sessionController: SessionController

    @Inject
    lateinit var settingsStore: SettingsStore

    @Inject
    lateinit var authSessionInstaller: AuthSessionInstaller

    @Inject
    lateinit var liveLessonNotifier: LiveLessonNotifier

    @Inject
    lateinit var liveLessonScheduler: LiveLessonScheduler

    override fun onCreate(savedInstanceState: Bundle?) {
        // Must run before super.onCreate — keeps system splash until first Compose frame.
        val splashScreen = installSplashScreen()
        var keepSplash = true
        splashScreen.setKeepOnScreenCondition { keepSplash }

        super.onCreate(savedInstanceState)
        settingsStore.applyStoredLanguage()
        sessionController.restore()
        when (val state = sessionController.authState.value) {
            is AuthState.Authenticated -> {
                authSessionInstaller.onColdStart(state.student)
            }
            AuthState.Unauthenticated -> {
                // iOS: wipe residual WK/UniLogin state before LoginView.
                authSessionInstaller.wipeResidualAuthState()
            }
            AuthState.Loading -> Unit
        }
        NotificationDiffWorker.enqueue(applicationContext)
        enableEdgeToEdge()
        setContent {
            val appearance by settingsStore.appearance.collectAsStateWithLifecycle()
            val authState by sessionController.authState.collectAsStateWithLifecycle()
            LaunchedEffect(authState) {
                when {
                    authState is AuthState.Authenticated &&
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        ContextCompat.checkSelfPermission(
                            this@MainActivity,
                            Manifest.permission.POST_NOTIFICATIONS,
                        ) != PackageManager.PERMISSION_GRANTED -> {
                        notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    }
                    authState is AuthState.Unauthenticated -> {
                        liveLessonNotifier.clear()
                        liveLessonScheduler.cancel()
                    }
                }
            }
            val dark = when (appearance) {
                AppearanceMode.SYSTEM -> isSystemInDarkTheme()
                AppearanceMode.LIGHT -> false
                AppearanceMode.DARK -> true
            }
            // Keep system-bar icon contrast in sync with the in-app appearance setting.
            // This matters when the app is forced light/dark independently of the device.
            SideEffect {
                val transparent = Color.TRANSPARENT
                val systemBarStyle = if (dark) {
                    SystemBarStyle.dark(scrim = transparent)
                } else {
                    SystemBarStyle.light(
                        scrim = transparent,
                        darkScrim = transparent,
                    )
                }
                enableEdgeToEdge(
                    statusBarStyle = systemBarStyle,
                    navigationBarStyle = systemBarStyle,
                )
            }
            // Dismiss splash after the first successful composition/apply.
            SideEffect { keepSplash = false }
            BetterW4Theme(darkTheme = dark) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    BetterW4Root(sessionController = sessionController)
                }
            }
        }
    }
}
