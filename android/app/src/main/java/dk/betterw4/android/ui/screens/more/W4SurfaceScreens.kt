package dk.betterw4.android.ui.screens.more

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterw4.android.R
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Urls
import dk.betterw4.android.feature.extraacademics.ExtraAcademicsPage
import dk.betterw4.android.feature.extraacademics.ExtraAcademicsRepository
import dk.betterw4.android.feature.extraacademics.W4PageSnapshot
import dk.betterw4.android.feature.home.HomeRepository
import dk.betterw4.android.feature.home.HomeSnapshot
import dk.betterw4.android.feature.trips.TravelForm
import dk.betterw4.android.feature.trips.TravelPage
import dk.betterw4.android.feature.trips.W4TripList
import dk.betterw4.android.feature.trips.W4TripsRepository
import dk.betterw4.android.feature.studiekort.StudentCard
import dk.betterw4.android.ui.components.EmptyBox
import dk.betterw4.android.ui.components.ErrorBox
import dk.betterw4.android.ui.components.HtmlBody
import dk.betterw4.android.ui.components.LoadingBox
import dk.betterw4.android.ui.components.PersonAvatar
import dk.betterw4.android.ui.components.SectionHeader
import dk.betterw4.android.ui.components.W4ChromeViewModel
import dk.betterw4.android.ui.components.W4WebSheet
import dk.betterw4.android.ui.components.W4WebTarget
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class HomeSurfaceViewModel @Inject constructor(
    private val repository: HomeRepository,
) : ViewModel() {
    private val _snapshot = MutableStateFlow<HomeSnapshot?>(null)
    val snapshot = _snapshot.asStateFlow()
    private val _loading = MutableStateFlow(true)
    val loading = _loading.asStateFlow()
    private val _error = MutableStateFlow<dk.betterw4.android.core.result.AppError?>(null)
    val error = _error.asStateFlow()

    init {
        refresh(false)
    }

    fun refresh(force: Boolean = true) = viewModelScope.launch {
        _loading.value = true
        when (val res = repository.load(force)) {
            is AppResult.Success -> {
                _snapshot.value = res.data
                _error.value = null
                _loading.value = false
            }
            is AppResult.Failure -> {
                _error.value = res.error
                _loading.value = false
            }
        }
    }
}

@Composable
fun HomeSurface(
    padding: PaddingValues,
    viewModel: HomeSurfaceViewModel = hiltViewModel(),
) {
    val snapshot by viewModel.snapshot.collectAsStateWithLifecycle()
    val loading by viewModel.loading.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var webTarget by remember { mutableStateOf<W4WebTarget?>(null) }
    val page = snapshot?.page

    when {
        loading && snapshot == null -> LoadingBox(Modifier.padding(padding))
        error != null && snapshot == null -> ErrorBox(
            error,
            onRetry = { viewModel.refresh(true) },
            modifier = Modifier.padding(padding),
        )
        page == null || page.isEmpty -> EmptyBox(
            text = stringResource(R.string.home_empty),
            modifier = Modifier.padding(padding),
        )
        else -> LazyColumn(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize(),
        ) {
            item {
                Column(Modifier.padding(16.dp)) {
                    Text(
                        page.greetingText ?: stringResource(R.string.more_home),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                    )
                    page.uwcId?.let {
                        Text(
                            it,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            snapshot?.let { snap ->
                item { SectionHeader(stringResource(R.string.home_attendance)) }
                item {
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.more_absence)) },
                        supportingContent = {
                            Text(
                                "AC ${snap.academicAbsences} absences · ${snap.academicLatenesses} late  ·  " +
                                    "EA ${snap.eaAbsences} absences · ${snap.eaLatenesses} late",
                            )
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
            }
            if (page.birthdaysToday.isNotEmpty()) {
                item { SectionHeader(stringResource(R.string.home_birthdays_today)) }
                items(page.birthdaysToday, key = { "today-${it.uwcId}" }) { birthday ->
                    ListItem(
                        headlineContent = { Text(birthday.uwcId) },
                        supportingContent = birthday.takeIf { it.isStaff }?.let {
                            { Text(stringResource(R.string.more_teachers)) }
                        },
                        leadingContent = { PersonAvatar(name = birthday.uwcId, knownUrl = birthday.photoUrl) },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
            }
            if (page.birthdaysTomorrow.isNotEmpty()) {
                item { SectionHeader(stringResource(R.string.home_birthdays_tomorrow)) }
                items(page.birthdaysTomorrow, key = { "tomorrow-${it.uwcId}" }) { birthday ->
                    ListItem(
                        headlineContent = { Text(birthday.uwcId) },
                        leadingContent = { PersonAvatar(name = birthday.uwcId, knownUrl = birthday.photoUrl) },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
            }
            item { SectionHeader(stringResource(R.string.home_announcements)) }
            if (page.announcements.isEmpty()) {
                item {
                    ListItem(
                        headlineContent = {
                            Text(page.announcementsEmptyText ?: stringResource(R.string.home_empty))
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
            } else {
                items(page.announcements, key = { it.id }) { announcement ->
                    ListItem(
                        headlineContent = { Text(announcement.title) },
                        supportingContent = announcement.date?.let { { Text(it) } },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
            }
            if (page.links.isNotEmpty()) {
                item { SectionHeader(stringResource(R.string.home_links)) }
                items(page.links, key = { it.url }) { link ->
                    ListItem(
                        headlineContent = { Text(link.title) },
                        modifier = Modifier.clickable {
                            if (link.isInternal) {
                                webTarget = W4WebTarget(link.title, link.url)
                            } else {
                                runCatching {
                                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(link.url)))
                                }
                            }
                        },
                        trailingContent = {
                            Icon(Icons.Default.OpenInNew, contentDescription = null)
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
            }
            page.serverVersion?.let { version ->
                item {
                    Text(
                        "W4 v. $version",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(16.dp),
                    )
                }
            }
        }
    }
    W4WebSheet(target = webTarget, onDismiss = { webTarget = null })
}

@Composable
fun ExtraAcademicsMenu(
    padding: PaddingValues,
    onOpenPage: (ExtraAcademicsPage) -> Unit,
    onOpenDocuments: () -> Unit,
) {
    LazyColumn(
        modifier = Modifier
            .padding(padding)
            .fillMaxSize(),
    ) {
        item { SectionHeader(stringResource(R.string.ea_section_activities)) }
        item {
            EaLink(Icons.Default.DirectionsBike, stringResource(R.string.ea_my_activities)) {
                onOpenPage(ExtraAcademicsPage.MY_ACTIVITIES)
            }
        }
        item {
            EaLink(Icons.Default.Book, stringResource(R.string.ea_diary)) {
                onOpenPage(ExtraAcademicsPage.DIARY)
            }
        }
        item {
            EaLink(Icons.Default.Folder, stringResource(R.string.ea_portfolio)) {
                onOpenPage(ExtraAcademicsPage.PORTFOLIO)
            }
        }
        item { SectionHeader(stringResource(R.string.ea_section_reviews)) }
        item {
            EaLink(Icons.Default.People, stringResource(R.string.ea_interviews)) {
                onOpenPage(ExtraAcademicsPage.INTERVIEWS)
            }
        }
        item {
            EaLink(Icons.Default.Favorite, stringResource(R.string.ea_safetynet)) {
                onOpenPage(ExtraAcademicsPage.SAFETY_NET)
            }
        }
        item {
            Text(
                stringResource(R.string.ea_safetynet_footer),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
        item { SectionHeader(stringResource(R.string.more_documents)) }
        item {
            EaLink(Icons.Default.Description, stringResource(R.string.ea_documents), onOpenDocuments)
        }
    }
}

@Composable
private fun EaLink(icon: ImageVector, title: String, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        leadingContent = {
            Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        },
        modifier = Modifier.clickable(onClick = onClick),
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}

@HiltViewModel
class ExtraAcademicsPageViewModel @Inject constructor(
    private val repository: ExtraAcademicsRepository,
) : ViewModel() {
    private val _snapshot = MutableStateFlow<W4PageSnapshot?>(null)
    val snapshot = _snapshot.asStateFlow()
    private val _loading = MutableStateFlow(true)
    val loading = _loading.asStateFlow()

    fun load(page: ExtraAcademicsPage, force: Boolean = false) = viewModelScope.launch {
        _loading.value = true
        when (val res = repository.page(page, force)) {
            is AppResult.Success -> {
                _snapshot.value = res.data
                _loading.value = false
            }
            is AppResult.Failure -> _loading.value = false
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExtraAcademicsPageSurface(
    page: ExtraAcademicsPage,
    padding: PaddingValues,
    viewModel: ExtraAcademicsPageViewModel = hiltViewModel(),
) {
    val snapshot by viewModel.snapshot.collectAsStateWithLifecycle()
    val loading by viewModel.loading.collectAsStateWithLifecycle()
    var webTarget by remember { mutableStateOf<W4WebTarget?>(null) }
    LaunchedEffect(page) { viewModel.load(page) }

    Column(
        Modifier
            .padding(padding)
            .fillMaxSize(),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
        ) {
            TextButton(
                onClick = {
                    webTarget = W4WebTarget(page.displayName, W4Urls.route(page.route).toString())
                },
            ) {
                Text(stringResource(R.string.open_in_w4))
            }
        }
        when {
            loading && snapshot == null -> LoadingBox()
            snapshot?.contentFragmentHtml.isNullOrBlank() -> EmptyBox(
                text = stringResource(R.string.home_empty),
            )
            else -> Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
            ) {
                HtmlBody(html = snapshot!!.contentFragmentHtml)
            }
        }
    }
    W4WebSheet(target = webTarget, onDismiss = { webTarget = null })
}

@HiltViewModel
class TripsTravelViewModel @Inject constructor(
    private val repository: W4TripsRepository,
) : ViewModel() {
    private val _trips = MutableStateFlow<W4TripList?>(null)
    val trips = _trips.asStateFlow()
    private val _travel = MutableStateFlow<TravelPage?>(null)
    val travel = _travel.asStateFlow()
    private val _loading = MutableStateFlow(true)
    val loading = _loading.asStateFlow()

    init {
        refresh(false)
    }

    fun refresh(force: Boolean = true) = viewModelScope.launch {
        _loading.value = true
        val tripRes = repository.load(force)
        val travelRes = repository.loadTravel(force)
        _trips.value = tripRes.getOrNull()
        _travel.value = travelRes.getOrNull()
        _loading.value = false
    }
}

@Composable
fun TripsTravelSurface(
    padding: PaddingValues,
    viewModel: TripsTravelViewModel = hiltViewModel(),
) {
    val trips by viewModel.trips.collectAsStateWithLifecycle()
    val travel by viewModel.travel.collectAsStateWithLifecycle()
    val loading by viewModel.loading.collectAsStateWithLifecycle()
    var webTarget by remember { mutableStateOf<W4WebTarget?>(null) }

    if (loading && trips == null && travel == null) {
        LoadingBox(Modifier.padding(padding))
        return
    }

    LazyColumn(
        modifier = Modifier
            .padding(padding)
            .fillMaxSize(),
    ) {
        item {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                TextButton(
                    onClick = {
                        val href = trips?.planNewTripHref
                        val url = if (!href.isNullOrBlank()) {
                            W4Urls.resolve(href).toString()
                        } else {
                            W4Urls.route(W4Urls.Routes.TRIPS).toString()
                        }
                        webTarget = W4WebTarget(
                            title = "Plan new trip",
                            url = url,
                        )
                    },
                ) {
                    Text(stringResource(R.string.trips_plan_new))
                }
            }
        }
        item { SectionHeader(stringResource(R.string.trips_my_trips)) }
        val tripRows = trips?.trips.orEmpty()
        if (tripRows.isEmpty()) {
            item {
                ListItem(
                    headlineContent = { Text(trips?.emptyMessage ?: stringResource(R.string.empty_trips)) },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        } else {
            items(tripRows, key = { it.id }) { trip ->
                ListItem(
                    headlineContent = { Text(trip.name) },
                    supportingContent = {
                        Text(
                            listOf(trip.destination, trip.outgoing, trip.status)
                                .filter { it.isNotBlank() }
                                .joinToString(" · "),
                        )
                    },
                    modifier = Modifier.clickable {
                        trip.href?.let {
                            webTarget = W4WebTarget(trip.name, W4Urls.resolve(it).toString())
                        }
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
        if (trips?.hasMorePages == true) {
            item {
                Text(
                    stringResource(R.string.trips_more_pages),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
        item { SectionHeader(stringResource(R.string.trips_travel_forms)) }
        val forms = travel?.forms.orEmpty()
        if (forms.isEmpty()) {
            item {
                ListItem(
                    headlineContent = {
                        Text(travel?.emptyMessage ?: stringResource(R.string.trips_no_travel))
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        } else {
            items(forms, key = { it.id }) { form ->
                TravelFormRow(form) { target -> webTarget = target }
            }
        }
        travel?.manageContactsLabel?.let { label ->
            item {
                ListItem(
                    headlineContent = { Text(label) },
                    modifier = Modifier.clickable {
                        val href = travel?.manageContactsHref
                        if (!href.isNullOrBlank()) {
                            webTarget = W4WebTarget(label, W4Urls.resolve(href).toString())
                        }
                    },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
    W4WebSheet(target = webTarget, onDismiss = { webTarget = null })
}

@Composable
private fun TravelFormRow(form: TravelForm, onOpen: (W4WebTarget) -> Unit) {
    ListItem(
        headlineContent = { Text(form.journey?.displayName ?: form.title) },
        supportingContent = form.status?.let { { Text(it) } },
        modifier = Modifier.clickable {
            val href = form.href
            if (!href.isNullOrBlank()) {
                onOpen(W4WebTarget(form.title, W4Urls.resolve(href).toString()))
            } else {
                onOpen(
                    W4WebTarget(
                        form.title,
                        W4Urls.route(W4Urls.Routes.TRAVEL).toString(),
                    ),
                )
            }
        },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}

@Composable
fun NotificationsSurface(
    padding: PaddingValues,
    chrome: W4ChromeViewModel = hiltViewModel(),
) {
    val snapshot by chrome.notificationSnapshot.collectAsStateWithLifecycle()
    val visible = snapshot.forDisplay()
    if (visible.isEmpty) {
        EmptyBox(
            text = stringResource(R.string.notif_empty),
            modifier = Modifier.padding(padding),
        )
        return
    }
    LazyColumn(
        modifier = Modifier
            .padding(padding)
            .fillMaxSize(),
    ) {
        visible.taskGroups.forEach { group ->
            item { SectionHeader(group.title) }
            items(group.items, key = { it.id }) { item ->
                ListItem(
                    headlineContent = { Text(item.title) },
                    supportingContent = item.subtitle?.let { { Text(it) } },
                    modifier = Modifier.clickable { chrome.markNotificationRead(item) },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
        visible.emailGroups.forEach { group ->
            item { SectionHeader(group.title.ifBlank { stringResource(R.string.notif_emails) }) }
            items(group.items, key = { it.id }) { item ->
                ListItem(
                    headlineContent = { Text(item.title) },
                    supportingContent = item.subtitle?.let { { Text(it) } },
                    modifier = Modifier.clickable { chrome.markNotificationRead(item) },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
            }
        }
        item {
            TextButton(
                onClick = chrome::markAllNotificationsRead,
                modifier = Modifier.padding(16.dp),
            ) {
                Text(stringResource(R.string.notif_mark_all_read))
            }
        }
    }
}

@Composable
fun IdCardSurface(
    card: StudentCard,
    padding: PaddingValues,
) {
    val context = LocalContext.current
    var copied by remember { mutableStateOf(false) }
    var webTarget by remember { mutableStateOf<W4WebTarget?>(null) }
    val displayName = card.student.name ?: stringResource(R.string.student_fallback)
    val email = card.email
    Column(
        Modifier
            .fillMaxSize()
            .padding(padding)
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Surface(
            shape = RoundedCornerShape(24.dp),
            color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
            tonalElevation = 2.dp,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                Modifier.padding(horizontal = 24.dp, vertical = 28.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                PersonAvatar(
                    name = displayName,
                    size = 132.dp,
                    entityId = card.student.studentId,
                    knownUrl = card.photoUrl,
                )
                Spacer(Modifier.height(20.dp))
                Text(
                    stringResource(R.string.id_card_school).uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    displayName,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                )
                card.student.classLabel?.takeIf { it.isNotBlank() }?.let { subtitle ->
                    Text(
                        subtitle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.height(22.dp))
                IdCardField(stringResource(R.string.id_card_uwc_id), card.student.studentId, mono = true)
                card.year?.takeIf { it.isNotBlank() }?.let {
                    IdCardField(stringResource(R.string.id_card_year), it)
                }
                card.house?.takeIf { it.isNotBlank() }?.let {
                    IdCardField(stringResource(R.string.id_card_house), it)
                }
                card.country?.takeIf { it.isNotBlank() }?.let {
                    IdCardField(stringResource(R.string.id_card_country), it)
                }
                if (!email.isNullOrBlank()) {
                    IdCardField(
                        label = if (copied) {
                            stringResource(R.string.id_card_email_copied)
                        } else {
                            stringResource(R.string.id_card_email)
                        },
                        value = email,
                        mono = true,
                        onClick = {
                            val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            clipboard.setPrimaryClip(ClipData.newPlainText("email", email))
                            copied = true
                        },
                    )
                }
            }
        }
        if (!card.student.isDemo) {
            ListItem(
                headlineContent = { Text(stringResource(R.string.more_letter_attendance)) },
                supportingContent = { Text(stringResource(R.string.id_card_letter_hint)) },
                leadingContent = {
                    Icon(Icons.Default.Description, contentDescription = null)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        webTarget = W4WebTarget(
                            title = context.getString(R.string.more_letter_attendance),
                            url = W4Urls.route(W4Urls.Routes.LETTER_ATTENDANCE).toString(),
                        )
                    },
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
            )
        }
    }
    W4WebSheet(target = webTarget, onDismiss = { webTarget = null })
}

@Composable
private fun IdCardField(
    label: String,
    value: String,
    mono: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(end = 12.dp),
        )
        Text(
            value,
            style = if (mono) {
                MaterialTheme.typography.bodyMedium.copy(
                    fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
                )
            } else {
                MaterialTheme.typography.bodyMedium
            },
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
fun PrivacyStoresSurface(padding: PaddingValues) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(bottom = 24.dp),
    ) {
        item {
            Text(
                stringResource(R.string.settings_privacy_intro),
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            )
        }
        item { SectionHeader(stringResource(R.string.settings_privacy_on_device)) }
        item {
            PrivacyRow(
                title = stringResource(R.string.settings_privacy_session_title),
                detail = stringResource(R.string.settings_privacy_session_detail),
            )
        }
        item {
            PrivacyRow(
                title = stringResource(R.string.settings_privacy_cache_title),
                detail = stringResource(R.string.settings_privacy_cache_detail),
            )
        }
        item {
            PrivacyRow(
                title = stringResource(R.string.settings_privacy_settings_title),
                detail = stringResource(R.string.settings_privacy_settings_detail),
            )
        }
        item { SectionHeader(stringResource(R.string.settings_privacy_never)) }
        item {
            PrivacyRow(
                title = stringResource(R.string.settings_privacy_analytics_title),
                detail = stringResource(R.string.settings_privacy_analytics_detail),
            )
        }
        item {
            PrivacyRow(
                title = stringResource(R.string.settings_privacy_third_parties_title),
                detail = stringResource(R.string.settings_privacy_third_parties_detail),
            )
        }
        item {
            Text(
                stringResource(R.string.settings_privacy_logout_note),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 16.dp),
            )
        }
    }
}

@Composable
private fun PrivacyRow(title: String, detail: String) {
    ListItem(
        headlineContent = { Text(title, fontWeight = FontWeight.SemiBold) },
        supportingContent = { Text(detail) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
    )
}
