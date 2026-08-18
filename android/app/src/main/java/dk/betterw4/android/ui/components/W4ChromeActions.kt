package dk.betterw4.android.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.RowScope
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.TextFieldValue
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterw4.android.R
import dk.betterw4.android.feature.campus.CampusLocationOption
import dk.betterw4.android.feature.campus.CampusStatusRepository
import dk.betterw4.android.feature.notifications.W4NotificationItem
import dk.betterw4.android.feature.notifications.W4NotificationRepository
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class W4ChromeViewModel @Inject constructor(
    private val campusStatus: CampusStatusRepository,
    private val notifications: W4NotificationRepository,
) : ViewModel() {
    val campus = campusStatus.status
    val notificationSnapshot = notifications.snapshot

    init {
        notifications.startPolling()
        viewModelScope.launch {
            if (campusStatus.status.value == null) campusStatus.refresh()
        }
    }

    fun setCampus(option: CampusLocationOption, freeText: String? = null) {
        viewModelScope.launch { campusStatus.set(option, freeText) }
    }

    fun refreshCampus() {
        viewModelScope.launch { campusStatus.refresh() }
    }

    fun setNotificationsOpen(open: Boolean) = notifications.setDropdownOpen(open)

    fun markNotificationRead(item: W4NotificationItem) {
        viewModelScope.launch { notifications.markRead(item.id) }
    }

    fun markAllNotificationsRead() {
        viewModelScope.launch { notifications.markAllRead() }
    }

    fun markAllNotificationEmailsRead() {
        viewModelScope.launch { notifications.markAllEmailsRead() }
    }
}

/**
 * Campus capsule + notifications bell — iOS chrome on every authenticated tab.
 */
@Composable
fun RowScope.W4ChromeActions(
    viewModel: W4ChromeViewModel = hiltViewModel(),
    onNotificationHref: ((String?) -> Unit)? = null,
) {
    val snapshot by viewModel.notificationSnapshot.collectAsStateWithLifecycle()
    NotificationsBell(
        snapshot = snapshot,
        onOpenChanged = viewModel::setNotificationsOpen,
        onMarkRead = { item ->
            viewModel.markNotificationRead(item)
            onNotificationHref?.invoke(item.href)
        },
        onMarkAllRead = viewModel::markAllNotificationsRead,
        onMarkEmailsRead = viewModel::markAllNotificationEmailsRead,
    )
    CampusStatusChip(viewModel)
}

@Composable
fun CampusStatusChip(
    viewModel: W4ChromeViewModel = hiltViewModel(),
) {
    val campus by viewModel.campus.collectAsStateWithLifecycle()
    var menu by remember { mutableStateOf(false) }
    var otherDialog by remember { mutableStateOf(false) }
    var otherText by remember { mutableStateOf(TextFieldValue()) }

    Box {
        FilterChip(
            selected = campus?.onCampus == true,
            onClick = { menu = true },
            label = {
                Text(
                    campus?.label ?: stringResource(R.string.campus_status),
                    maxLines = 1,
                    style = MaterialTheme.typography.labelMedium,
                )
            },
        )
        DropdownMenu(
            expanded = menu,
            onDismissRequest = { menu = false },
        ) {
            val options = campus?.options.orEmpty().ifEmpty { CampusLocationOption.defaults }
            options.forEach { option ->
                DropdownMenuItem(
                    text = {
                        Text(if (option.isFreeText) "${option.label}…" else option.label)
                    },
                    onClick = {
                        menu = false
                        if (option.isFreeText) {
                            otherText = TextFieldValue()
                            otherDialog = true
                        } else {
                            viewModel.setCampus(option)
                        }
                    },
                )
            }
            DropdownMenuItem(
                text = { Text(stringResource(R.string.campus_refresh)) },
                onClick = {
                    menu = false
                    viewModel.refreshCampus()
                },
            )
        }
    }

    if (otherDialog) {
        val otherOption = (campus?.options ?: CampusLocationOption.defaults)
            .firstOrNull { it.isFreeText }
            ?: CampusLocationOption.defaults.last()
        AlertDialog(
            onDismissRequest = { otherDialog = false },
            title = { Text(stringResource(R.string.campus_picker_title)) },
            text = {
                OutlinedTextField(
                    value = otherText,
                    onValueChange = { next ->
                        otherText = next.copy(
                            text = next.text.take(CampusLocationOption.FREE_TEXT_MAX_LENGTH),
                        )
                    },
                    label = { Text(stringResource(R.string.campus_other_hint)) },
                    singleLine = true,
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val trimmed = otherText.text.trim()
                        if (trimmed.isNotEmpty()) {
                            viewModel.setCampus(otherOption, trimmed)
                            otherDialog = false
                        }
                    },
                    enabled = otherText.text.trim().isNotEmpty(),
                ) {
                    Text(stringResource(R.string.campus_set_status))
                }
            },
            dismissButton = {
                TextButton(onClick = { otherDialog = false }) {
                    Text(stringResource(android.R.string.cancel))
                }
            },
        )
    }
}
