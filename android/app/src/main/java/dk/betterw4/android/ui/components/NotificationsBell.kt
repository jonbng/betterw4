package dk.betterw4.android.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dk.betterw4.android.R
import dk.betterw4.android.feature.notifications.W4NotificationItem
import dk.betterw4.android.feature.notifications.W4NotificationSection
import dk.betterw4.android.feature.notifications.W4NotificationSnapshot

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NotificationsBell(
    snapshot: W4NotificationSnapshot,
    onOpenChanged: (Boolean) -> Unit,
    onMarkRead: (W4NotificationItem) -> Unit,
    onMarkAllRead: () -> Unit,
    onMarkEmailsRead: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var open by remember { mutableStateOf(false) }
    DisposableEffect(open) {
        onOpenChanged(open)
        onDispose { if (open) onOpenChanged(false) }
    }
    val count = snapshot.count.takeIf { it > 0 } ?: snapshot.items.size
    IconButton(
        onClick = { open = true },
        modifier = modifier,
    ) {
        BadgedBox(
            badge = {
                if (count > 0) {
                    Badge { Text(if (count > 99) "99+" else count.toString()) }
                }
            },
        ) {
            Icon(
                if (count > 0) Icons.Filled.Notifications else Icons.Outlined.Notifications,
                contentDescription = stringResource(R.string.cd_notifications),
            )
        }
    }
    if (open) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { open = false },
            sheetState = sheetState,
        ) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 8.dp)
                    .verticalScroll(rememberScrollState()),
            ) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        stringResource(R.string.cd_notifications),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    if (snapshot.taskGroups.any { it.items.isNotEmpty() }) {
                        TextButton(onClick = onMarkAllRead) {
                            Text(stringResource(R.string.notif_mark_all_read))
                        }
                    }
                }
                if (snapshot.isEmpty) {
                    Text(
                        stringResource(R.string.notif_empty),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(16.dp),
                    )
                } else {
                    if (snapshot.taskGroups.any { it.items.isNotEmpty() }) {
                        SectionLabel(stringResource(R.string.notif_tasks))
                        snapshot.taskGroups.forEach { group ->
                            if (group.items.isEmpty()) return@forEach
                            GroupHeader(group.title)
                            group.items.forEach { item ->
                                NotificationRow(item) {
                                    onMarkRead(item)
                                    open = false
                                }
                            }
                        }
                    }
                    if (snapshot.emailGroups.any { it.items.isNotEmpty() }) {
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween,
                        ) {
                            SectionLabel(stringResource(R.string.notif_emails), padded = false)
                            TextButton(onClick = onMarkEmailsRead) {
                                Text(stringResource(R.string.notif_mark_emails_read))
                            }
                        }
                        snapshot.emailGroups.forEach { group ->
                            if (group.items.isEmpty()) return@forEach
                            GroupHeader(group.title)
                            group.items.forEach { item ->
                                NotificationRow(item) {
                                    onMarkRead(item)
                                    open = false
                                }
                            }
                        }
                    }
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun SectionLabel(text: String, padded: Boolean = true) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(
            start = if (padded) 16.dp else 0.dp,
            end = 16.dp,
            top = 12.dp,
            bottom = 4.dp,
        ),
    )
}

@Composable
private fun GroupHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
    )
}

@Composable
private fun NotificationRow(item: W4NotificationItem, onClick: () -> Unit) {
    AppListRow(onClick = onClick) {
        AppListPrimary(item.title, emphasized = item.section == W4NotificationSection.TASK)
        item.subtitle?.let { AppListSecondary(it) }
    }
    HorizontalDivider()
}
