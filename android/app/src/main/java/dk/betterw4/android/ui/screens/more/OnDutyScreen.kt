package dk.betterw4.android.ui.screens.more

import android.content.Intent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.outlined.Phone
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterw4.android.R
import dk.betterw4.android.core.result.AppError
import dk.betterw4.android.core.result.AppResult
import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import dk.betterw4.android.feature.onduty.OnDutyContact
import dk.betterw4.android.feature.onduty.OnDutyDay
import dk.betterw4.android.feature.onduty.OnDutyPerson
import dk.betterw4.android.feature.onduty.OnDutyRepository
import dk.betterw4.android.feature.onduty.OnDutySnapshot
import dk.betterw4.android.ui.components.EmptyBox
import dk.betterw4.android.ui.components.ErrorBox
import dk.betterw4.android.ui.components.LoadingBox
import dk.betterw4.android.ui.components.PersonAvatar
import dk.betterw4.android.ui.components.SectionHeader
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import javax.inject.Inject

@HiltViewModel
class OnDutyViewModel @Inject constructor(
    private val repository: OnDutyRepository,
) : ViewModel() {
    private val _snapshot = MutableStateFlow<OnDutySnapshot?>(null)
    val snapshot = _snapshot.asStateFlow()
    private val _loading = MutableStateFlow(true)
    val loading = _loading.asStateFlow()
    private val _error = MutableStateFlow<AppError?>(null)
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
            }
            is AppResult.Failure -> _error.value = res.error
        }
        _loading.value = false
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun OnDutySurface(
    padding: PaddingValues,
    viewModel: OnDutyViewModel = hiltViewModel(),
) {
    val snapshot by viewModel.snapshot.collectAsStateWithLifecycle()
    val loading by viewModel.loading.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }

    PullToRefreshBox(
        isRefreshing = loading && snapshot != null,
        onRefresh = { viewModel.refresh(true) },
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
    ) {
        when {
            loading && snapshot == null -> LoadingBox()
            error != null && snapshot == null -> ErrorBox(
                error,
                onRetry = { viewModel.refresh(true) },
            )
            snapshot == null || (snapshot!!.today.isEmpty && snapshot!!.upcoming.isEmpty()) -> EmptyBox(
                text = stringResource(R.string.on_duty_empty),
                description = stringResource(R.string.on_duty_empty_hint),
                icon = Icons.Outlined.Phone,
            )
            else -> OnDutyList(
                snapshot = snapshot!!,
                snackbar = snackbar,
            )
        }
        SnackbarHost(
            hostState = snackbar,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(16.dp),
        )
    }
}

@Composable
private fun OnDutyList(
    snapshot: OnDutySnapshot,
    snackbar: SnackbarHostState,
) {
    val today = W4Dates.today()
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 24.dp),
    ) {
        snapshot.today.dateLabel?.let { label ->
            item(key = "date") {
                Text(
                    label,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                )
            }
        }
        if (snapshot.today.isEmpty) {
            item(key = "empty-today") {
                Text(
                    stringResource(R.string.on_duty_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }
        }
        snapshot.today.groups.forEach { group ->
            item(key = "role-${group.role}") {
                SectionHeader(group.role)
            }
            items(group.people, key = { it.id }) { person ->
                OnDutyPersonCard(person = person, snackbar = snackbar)
            }
        }
        if (snapshot.upcoming.isNotEmpty()) {
            item(key = "upcoming-header") {
                SectionHeader(stringResource(R.string.on_duty_upcoming))
            }
            items(snapshot.upcoming, key = { it.id }) { day ->
                OnDutyUpcomingCard(day = day, today = today, snackbar = snackbar)
            }
        }
    }
}

@Composable
private fun OnDutyPersonCard(
    person: OnDutyPerson,
    snackbar: SnackbarHostState,
) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    val copied = stringResource(R.string.on_duty_copied)

    fun copy(value: String) {
        clipboard.setText(AnnotatedString(value))
        scope.launch { snackbar.showSnackbar(copied) }
    }

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
        shape = RoundedCornerShape(20.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                PersonAvatar(
                    name = person.name,
                    size = 56.dp,
                    entityId = person.uwcId,
                    kind = DirectoryEntityKind.TEACHER,
                    knownUrl = person.photoUrl,
                )
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        person.name,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    person.location?.takeIf { it.isNotBlank() }?.let { location ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.padding(top = 2.dp),
                        ) {
                            Icon(
                                Icons.Default.Place,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(14.dp),
                            )
                            Spacer(Modifier.width(4.dp))
                            Text(
                                location,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
            if (person.hasContact) {
                Spacer(Modifier.height(12.dp))
                person.phone?.let { phone ->
                    OnDutyContactRow(
                        icon = Icons.Default.Call,
                        title = stringResource(R.string.on_duty_call),
                        detail = phone,
                        tint = Color(0xFF1B7A3D),
                        onClick = {
                            OnDutyContact.telephoneUri(phone)?.let { uri ->
                                runCatching { context.startActivity(Intent(Intent.ACTION_DIAL, uri)) }
                            }
                        },
                        onLongClick = { copy(phone) },
                    )
                    Spacer(Modifier.height(8.dp))
                }
                person.email?.let { email ->
                    OnDutyContactRow(
                        icon = Icons.Default.Email,
                        title = stringResource(R.string.on_duty_email),
                        detail = email,
                        tint = MaterialTheme.colorScheme.primary,
                        onClick = {
                            OnDutyContact.mailtoUri(email)?.let { uri ->
                                runCatching {
                                    context.startActivity(Intent(Intent.ACTION_SENDTO, uri))
                                }
                            }
                        },
                        onLongClick = { copy(email) },
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun OnDutyContactRow(
    icon: ImageVector,
    title: String,
    detail: String,
    tint: Color,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(tint.copy(alpha = 0.10f))
            .combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(18.dp),
        )
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(
                title,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                detail,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Icon(
            Icons.Default.ContentCopy,
            contentDescription = stringResource(R.string.on_duty_copy),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
            modifier = Modifier
                .size(16.dp)
                .clickable(onClick = onLongClick),
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun OnDutyUpcomingCard(
    day: OnDutyDay,
    today: LocalDate,
    snackbar: SnackbarHostState,
) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    val copied = stringResource(R.string.on_duty_copied)
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 6.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 0.dp,
    ) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
            Text(
                captionFor(day, today),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            day.groups.forEach { group ->
                Text(
                    group.role,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp, bottom = 2.dp),
                )
                group.people.forEach { person ->
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            person.name,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.weight(1f),
                        )
                        person.phone?.let { phone ->
                            Text(
                                phone,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.primary,
                                modifier = Modifier
                                    .clip(RoundedCornerShape(8.dp))
                                    .combinedClickable(
                                        onClick = {
                                            OnDutyContact.telephoneUri(phone)?.let { uri ->
                                                runCatching {
                                                    context.startActivity(Intent(Intent.ACTION_DIAL, uri))
                                                }
                                            }
                                        },
                                        onLongClick = {
                                            clipboard.setText(AnnotatedString(phone))
                                            scope.launch { snackbar.showSnackbar(copied) }
                                        },
                                    )
                                    .padding(horizontal = 4.dp, vertical = 2.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

private val DAY_FORMAT = DateTimeFormatter.ofPattern("EEE d MMM", Locale.UK)

private fun captionFor(day: OnDutyDay, today: LocalDate): String {
    val date = day.date ?: return day.dateLabel
    return when (date) {
        today -> "Today"
        today.plusDays(1) -> "Tomorrow"
        else -> date.format(DAY_FORMAT)
    }
}
