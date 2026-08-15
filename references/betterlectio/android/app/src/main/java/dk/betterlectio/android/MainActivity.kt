package dk.betterlectio.android

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
import com.posthog.PostHog
import dagger.hilt.android.AndroidEntryPoint
import dk.betterlectio.android.core.lectio.auth.AuthSessionInstaller
import dk.betterlectio.android.core.lectio.session.AuthState
import dk.betterlectio.android.core.lectio.session.SessionController
import dk.betterlectio.android.feature.live.LiveLessonNotifier
import dk.betterlectio.android.feature.live.LiveLessonScheduler
import dk.betterlectio.android.feature.notifications.NotificationDiffWorker
import dk.betterlectio.android.feature.settings.AppearanceMode
import dk.betterlectio.android.feature.settings.SettingsStore
import dk.betterlectio.android.ui.feedback.FeedbackHost
import dk.betterlectio.android.ui.navigation.BetterLectioRoot
import dk.betterlectio.android.ui.theme.BetterLectioTheme
import javax.inject.Inject

/**
 * [AppCompatActivity] (not ComponentActivity) so per-app language works on API 29–32
 * via AppCompatDelegate, and so AppCompat has an active delegate when needed.
 * On API 33+ [dk.betterlectio.android.core.i18n.AppLocale] uses LocaleManager directly.
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
                // Re-identify the user so all events in this session are linked to their profile.
                if (!state.student.isDemo) {
                    PostHog.identify(
                        distinctId = state.student.studentId,
                        userProperties = mapOf("gym_id" to state.student.gymId),
                    )
                }
                // iOS cold-start order: validate Lectio → Supabase → directory (sequential).
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
            BetterLectioTheme(darkTheme = dark) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    FeedbackHost {
                        BetterLectioRoot(sessionController = sessionController)
                    }
                }
            }
        }
    }
}
