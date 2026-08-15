package dk.betterw4.android.ui.navigation

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import dk.betterw4.android.core.w4.session.AuthState
import dk.betterw4.android.core.w4.session.SessionController
import dk.betterw4.android.feature.messages.MessageRepository
import dk.betterw4.android.feature.review.ReviewPromptCoordinator
import dk.betterw4.android.feature.settings.SettingsStore
import dk.betterw4.android.ui.auth.LoginScreen
import dk.betterw4.android.ui.components.LoadingBox
import dk.betterw4.android.ui.onboarding.OnboardingOverlay
import dk.betterw4.android.ui.review.ReviewPromptSheet
import dk.betterw4.android.ui.screens.homework.HomeworkScreen
import dk.betterw4.android.ui.screens.messages.MessagesScreen
import dk.betterw4.android.ui.screens.more.MoreScreen
import dk.betterw4.android.ui.screens.schedule.ScheduleScreen
@Composable
fun BetterW4Root(
    sessionController: SessionController,
) {
    val authState by sessionController.authState.collectAsStateWithLifecycle()
    AnimatedContent(
        targetState = authState,
        transitionSpec = {
            fadeIn(animationSpec = tween(220)) togetherWith fadeOut(animationSpec = tween(160))
        },
        contentKey = {
            when (it) {
                AuthState.Loading -> "loading"
                AuthState.Unauthenticated -> "login"
                is AuthState.Authenticated -> "app"
            }
        },
        label = "auth",
    ) { state ->
        when (state) {
            AuthState.Loading -> LoadingBox()
            AuthState.Unauthenticated -> LoginScreen()
            is AuthState.Authenticated -> AuthenticatedShell()
        }
    }
}

@Composable
private fun AuthenticatedShell() {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination

    val context = LocalContext.current
    val entryPoint = remember {
        EntryPointAccessors.fromApplication(
            context.applicationContext,
            AuthenticatedShellEntryPoint::class.java,
        )
    }
    val messageRepository = remember { entryPoint.messageRepository() }
    val settingsStore = remember { entryPoint.settingsStore() }
    val reviewPromptCoordinator = remember { entryPoint.reviewPromptCoordinator() }
    val unreadCount by messageRepository.unreadCount.collectAsStateWithLifecycle()
    val reviewPromptVisible by reviewPromptCoordinator.softPromptVisible.collectAsStateWithLifecycle()

    var showOnboarding by remember { mutableStateOf(settingsStore.shouldShowOnboarding()) }

    LaunchedEffect(showOnboarding) {
        reviewPromptCoordinator.setExternalPromptBlocking("onboarding", showOnboarding)
    }

    LaunchedEffect(showOnboarding) {
        if (showOnboarding) return@LaunchedEffect
        reviewPromptCoordinator.onAuthenticatedLaunch()
    }

    // Same-tab reselect → bump scroll token for active route
    val scrollTokens = remember { mutableStateMapOf<String, Int>() }
    var scheduleScroll by remember { mutableIntStateOf(0) }
    var messagesScroll by remember { mutableIntStateOf(0) }
    var homeworkScroll by remember { mutableIntStateOf(0) }
    var moreScroll by remember { mutableIntStateOf(0) }

    // Zero content insets: child screens own status-bar handling via their TopAppBars.
    // Without this, the outer Scaffold (no topBar) pads the NavHost for the status bar,
    // and each tab Scaffold/TopAppBar pads again → empty gap above every page title.
    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            NavigationBar(
                containerColor = MaterialTheme.colorScheme.surface,
                tonalElevation = 0.dp,
            ) {
                AppDestination.bottomBarItems.forEach { destination ->
                    val selected = currentDestination
                        ?.hierarchy
                        ?.any { it.route == destination.route } == true
                    NavigationBarItem(
                        selected = selected,
                        onClick = {
                            // More: always land on the top-level menu (not a nested sub-page).
                            // Bump the token whether reselecting or switching from another tab so
                            // MoreScreen pops to root when it (re)appears.
                            if (destination == AppDestination.More) {
                                moreScroll++
                            }
                            if (selected) {
                                when (destination) {
                                    AppDestination.Schedule -> scheduleScroll++
                                    AppDestination.Messages -> messagesScroll++
                                    AppDestination.Homework -> homeworkScroll++
                                    AppDestination.More -> Unit // already bumped above
                                }
                                scrollTokens[destination.route] =
                                    (scrollTokens[destination.route] ?: 0) + 1
                            } else {
                                navController.navigate(destination.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            }
                        },
                        icon = {
                            val icon = if (selected) destination.selectedIcon else destination.unselectedIcon
                            if (destination == AppDestination.Messages && unreadCount > 0) {
                                BadgedBox(
                                    badge = {
                                        Badge {
                                            Text(if (unreadCount > 9) "9+" else "$unreadCount")
                                        }
                                    },
                                ) {
                                    Icon(icon, contentDescription = stringResource(destination.labelRes))
                                }
                            } else {
                                Icon(icon, contentDescription = stringResource(destination.labelRes))
                            }
                        },
                        // Keep labels on one line on narrow phones (e.g. "Assignments").
                        // Auto-size down a bit, then ellipsize rather than wrap to two lines.
                        label = {
                            Text(
                                text = stringResource(destination.labelRes),
                                maxLines = 1,
                                softWrap = false,
                                overflow = TextOverflow.Ellipsis,
                                textAlign = TextAlign.Center,
                                style = MaterialTheme.typography.labelMedium.copy(
                                    letterSpacing = 0.sp,
                                    lineHeight = 14.sp,
                                ),
                                autoSize = TextAutoSize.StepBased(
                                    minFontSize = 9.sp,
                                    maxFontSize = 12.sp,
                                    stepSize = 0.5.sp,
                                ),
                            )
                        },
                    )
                }
            }
        },
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = AppDestination.Schedule.route,
            modifier = Modifier.padding(innerPadding),
            enterTransition = { fadeIn(animationSpec = tween(180)) },
            exitTransition = { fadeOut(animationSpec = tween(140)) },
            popEnterTransition = { fadeIn(animationSpec = tween(180)) },
            popExitTransition = { fadeOut(animationSpec = tween(140)) },
        ) {
            composable(AppDestination.Schedule.route) {
                ScheduleScreen(
                    scrollToTopToken = scheduleScroll,
                    onOpenMail = {
                        navController.navigate(AppDestination.Messages.route) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    onOpenAssessments = {
                        navController.navigate(AppDestination.Homework.route) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                )
            }
            composable(AppDestination.Messages.route) {
                MessagesScreen(scrollToTopToken = messagesScroll)
            }
            composable(AppDestination.Homework.route) {
                HomeworkScreen(scrollToTopToken = homeworkScroll)
            }
            composable(AppDestination.More.route) {
                MoreScreen(
                    scrollToTopToken = moreScroll,
                    onComposeToPerson = {
                        // PendingComposeRecipient is already offered by MoreViewModel;
                        // switch tab so MessagesViewModel can open compose.
                        navController.navigate(AppDestination.Messages.route) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = true
                            }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                )
            }
        }
    }

    if (showOnboarding) {
        OnboardingOverlay(
            settingsStore = settingsStore,
            onComplete = {
                settingsStore.markOnboardingCompleted()
                showOnboarding = false
            },
        )
    }

    if (reviewPromptVisible && !showOnboarding) {
        ReviewPromptSheet(
            onPositive = { activity -> reviewPromptCoordinator.onPositive(activity) },
            onNegative = { reviewPromptCoordinator.onNegative() },
            onDismiss = { reviewPromptCoordinator.onDismissed() },
        )
    }
}

@EntryPoint
@InstallIn(SingletonComponent::class)
interface AuthenticatedShellEntryPoint {
    fun messageRepository(): MessageRepository
    fun settingsStore(): SettingsStore
    fun reviewPromptCoordinator(): ReviewPromptCoordinator
}
