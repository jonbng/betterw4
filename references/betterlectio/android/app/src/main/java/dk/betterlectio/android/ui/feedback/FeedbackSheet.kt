package dk.betterlectio.android.ui.feedback

import android.graphics.Bitmap
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.rounded.ChatBubbleOutline
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dk.betterlectio.android.R
import dk.betterlectio.android.feature.feedback.FeedbackCategory
import dk.betterlectio.android.feature.feedback.FeedbackCapture
import dk.betterlectio.android.feature.feedback.FeedbackSubmitResult
import dk.betterlectio.android.feature.feedback.FeedbackSubmission
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class SheetPhase {
    Compose,
    Sending,
    Success,
    Error,
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FeedbackSheet(
    capture: FeedbackCapture,
    onDismiss: () -> Unit,
    onSubmit: suspend (FeedbackSubmission) -> FeedbackSubmitResult,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()

    var category by remember { mutableStateOf(FeedbackCategory.BUG) }
    var message by remember { mutableStateOf("") }
    var includeScreenshot by remember {
        mutableStateOf(capture.screenshot != null)
    }
    var includeLogs by remember {
        mutableStateOf(capture.logs.isNotBlank())
    }
    var phase by remember { mutableStateOf(SheetPhase.Compose) }

    val canSend = message.trim().length >= 3 && phase == SheetPhase.Compose

    ModalBottomSheet(
        onDismissRequest = {
            if (phase != SheetPhase.Sending) onDismiss()
        },
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
        dragHandle = null,
    ) {
        AnimatedContent(
            targetState = phase,
            transitionSpec = {
                (
                    fadeIn(tween(220)) +
                        scaleIn(initialScale = 0.96f, animationSpec = tween(220))
                    ) togetherWith fadeOut(tween(140))
            },
            label = "feedback_phase",
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .imePadding(),
        ) { current ->
            when (current) {
                SheetPhase.Success -> SuccessPane(
                    onDone = {
                        scope.launch {
                            sheetState.hide()
                            onDismiss()
                        }
                    },
                )
                SheetPhase.Error -> ErrorPane(
                    onRetry = { phase = SheetPhase.Compose },
                    onDismiss = {
                        scope.launch {
                            sheetState.hide()
                            onDismiss()
                        }
                    },
                )
                SheetPhase.Compose, SheetPhase.Sending -> ComposePane(
                    category = category,
                    onCategoryChange = { category = it },
                    message = message,
                    onMessageChange = { message = it },
                    screenshot = capture.screenshot,
                    includeScreenshot = includeScreenshot,
                    onIncludeScreenshotChange = { includeScreenshot = it },
                    includeLogs = includeLogs,
                    onIncludeLogsChange = { includeLogs = it },
                    hasLogs = capture.logs.isNotBlank(),
                    sending = current == SheetPhase.Sending,
                    canSend = canSend,
                    onClose = {
                        scope.launch {
                            sheetState.hide()
                            onDismiss()
                        }
                    },
                    onSend = {
                        phase = SheetPhase.Sending
                        scope.launch {
                            val result = onSubmit(
                                FeedbackSubmission(
                                    category = category,
                                    message = message,
                                    includeScreenshot = includeScreenshot,
                                    includeLogs = includeLogs,
                                    capture = capture,
                                ),
                            )
                            phase = when (result) {
                                FeedbackSubmitResult.Success -> SheetPhase.Success
                                is FeedbackSubmitResult.Failure -> SheetPhase.Error
                            }
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun ComposePane(
    category: FeedbackCategory,
    onCategoryChange: (FeedbackCategory) -> Unit,
    message: String,
    onMessageChange: (String) -> Unit,
    screenshot: Bitmap?,
    includeScreenshot: Boolean,
    onIncludeScreenshotChange: (Boolean) -> Unit,
    includeLogs: Boolean,
    onIncludeLogsChange: (Boolean) -> Unit,
    hasLogs: Boolean,
    sending: Boolean,
    canSend: Boolean,
    onClose: () -> Unit,
    onSend: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp)
            .padding(top = 8.dp, bottom = 20.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(44.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Rounded.ChatBubbleOutline,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    modifier = Modifier.size(22.dp),
                )
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.feedback_title),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    stringResource(R.string.feedback_subtitle),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            IconButton(onClick = onClose, enabled = !sending) {
                Icon(
                    Icons.Outlined.Close,
                    contentDescription = stringResource(R.string.action_cancel),
                )
            }
        }

        Spacer(Modifier.height(20.dp))

        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                stringResource(R.string.feedback_category_label),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FeedbackCategory.entries.forEach { cat ->
                    CategoryCard(
                        category = cat,
                        selected = category == cat,
                        enabled = !sending,
                        onClick = { onCategoryChange(cat) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            OutlinedTextField(
                value = message,
                onValueChange = { if (it.length <= 4000) onMessageChange(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 140.dp),
                enabled = !sending,
                placeholder = {
                    Text(stringResource(category.hintRes))
                },
                shape = RoundedCornerShape(16.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant,
                ),
                minLines = 5,
                maxLines = 10,
            )

            AttachmentSection(
                screenshot = screenshot,
                includeScreenshot = includeScreenshot,
                onIncludeScreenshotChange = onIncludeScreenshotChange,
                includeLogs = includeLogs,
                onIncludeLogsChange = onIncludeLogsChange,
                hasLogs = hasLogs,
                enabled = !sending,
            )
        }

        Spacer(Modifier.height(16.dp))

        Button(
            onClick = onSend,
            enabled = canSend && !sending,
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
            shape = RoundedCornerShape(16.dp),
            elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp),
        ) {
            if (sending) {
                CircularProgressIndicator(
                    modifier = Modifier.size(22.dp),
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onPrimary,
                )
                Spacer(Modifier.width(10.dp))
                Text(
                    stringResource(R.string.feedback_sending),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            } else {
                Icon(
                    Icons.AutoMirrored.Rounded.Send,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(10.dp))
                Text(
                    stringResource(R.string.feedback_send),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }

        Spacer(Modifier.height(8.dp))
        Text(
            stringResource(R.string.feedback_privacy_note),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun CategoryCard(
    category: FeedbackCategory,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scale by animateFloatAsState(
        targetValue = if (selected) 1f else 0.98f,
        animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
        label = "cat_scale",
    )
    val icon = when (category) {
        FeedbackCategory.BUG -> Icons.Outlined.BugReport
        FeedbackCategory.IDEA -> Icons.Outlined.Lightbulb
        FeedbackCategory.OTHER -> Icons.Outlined.MoreHoriz
    }
    Surface(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.graphicsLayer {
            scaleX = scale
            scaleY = scale
        },
        shape = RoundedCornerShape(14.dp),
        color = if (selected) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.surfaceContainerHigh
        },
        border = if (selected) {
            BorderStroke(1.5.dp, MaterialTheme.colorScheme.primary)
        } else {
            BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
        },
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(vertical = 14.dp, horizontal = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = if (selected) {
                    MaterialTheme.colorScheme.onPrimaryContainer
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                modifier = Modifier.size(22.dp),
            )
            Text(
                stringResource(category.labelRes),
                style = MaterialTheme.typography.labelLarge,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                color = if (selected) {
                    MaterialTheme.colorScheme.onPrimaryContainer
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                textAlign = TextAlign.Center,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun AttachmentSection(
    screenshot: Bitmap?,
    includeScreenshot: Boolean,
    onIncludeScreenshotChange: (Boolean) -> Unit,
    includeLogs: Boolean,
    onIncludeLogsChange: (Boolean) -> Unit,
    hasLogs: Boolean,
    enabled: Boolean,
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            stringResource(R.string.feedback_attachments_label),
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (screenshot != null) {
            AttachmentToggleRow(
                selected = includeScreenshot,
                enabled = enabled,
                onClick = { onIncludeScreenshotChange(!includeScreenshot) },
                leading = {
                    Image(
                        bitmap = screenshot.asImageBitmap(),
                        contentDescription = stringResource(R.string.feedback_screenshot_cd),
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .size(width = 52.dp, height = 72.dp)
                            .clip(RoundedCornerShape(10.dp)),
                    )
                },
                title = stringResource(R.string.feedback_screenshot_title),
                subtitle = stringResource(
                    if (includeScreenshot) {
                        R.string.feedback_screenshot_included
                    } else {
                        R.string.feedback_screenshot_excluded
                    },
                ),
            )
        } else {
            AttachmentToggleRow(
                selected = false,
                enabled = false,
                onClick = {},
                leading = {
                    Box(
                        Modifier
                            .size(width = 52.dp, height = 72.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(MaterialTheme.colorScheme.surfaceContainerHighest),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.Outlined.Description,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                title = stringResource(R.string.feedback_screenshot_title),
                subtitle = stringResource(R.string.feedback_screenshot_unavailable),
            )
        }

        if (hasLogs) {
            AttachmentToggleRow(
                selected = includeLogs,
                enabled = enabled,
                onClick = { onIncludeLogsChange(!includeLogs) },
                leading = {
                    Box(
                        Modifier
                            .size(width = 52.dp, height = 52.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(
                                if (includeLogs) {
                                    MaterialTheme.colorScheme.secondaryContainer
                                } else {
                                    MaterialTheme.colorScheme.surfaceContainerHighest
                                },
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            Icons.Outlined.Description,
                            contentDescription = null,
                            tint = if (includeLogs) {
                                MaterialTheme.colorScheme.onSecondaryContainer
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant
                            },
                        )
                    }
                },
                title = stringResource(R.string.feedback_logs_title),
                subtitle = stringResource(
                    if (includeLogs) {
                        R.string.feedback_logs_included
                    } else {
                        R.string.feedback_logs_excluded
                    },
                ),
            )
        }
    }
}

@Composable
private fun AttachmentToggleRow(
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    leading: @Composable () -> Unit,
    title: String,
    subtitle: String,
) {
    Surface(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(14.dp),
        color = if (selected) {
            MaterialTheme.colorScheme.surfaceContainerHigh
        } else {
            MaterialTheme.colorScheme.surfaceContainerLow
        },
        border = BorderStroke(
            1.dp,
            if (selected) {
                MaterialTheme.colorScheme.outline.copy(alpha = 0.35f)
            } else {
                MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f)
            },
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            leading()
            Column(Modifier.weight(1f)) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            // Visual selected indicator without checkbox chrome
            Box(
                Modifier
                    .size(22.dp)
                    .clip(CircleShape)
                    .background(
                        if (selected) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.outlineVariant
                        },
                    ),
                contentAlignment = Alignment.Center,
            ) {
                if (selected) {
                    Icon(
                        Icons.Outlined.CheckCircle,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onPrimary,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun SuccessPane(onDone: () -> Unit) {
    LaunchedEffect(Unit) {
        delay(1_800)
        onDone()
    }
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 28.dp, vertical = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        val appear = remember { mutableStateOf(false) }
        LaunchedEffect(Unit) { appear.value = true }
        AnimatedVisibility(
            visible = appear.value,
            enter = scaleIn(
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioMediumBouncy,
                    stiffness = Spring.StiffnessMedium,
                ),
            ) + fadeIn(),
        ) {
            Box(
                Modifier
                    .size(72.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Outlined.CheckCircle,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    modifier = Modifier.size(40.dp),
                )
            }
        }
        Text(
            stringResource(R.string.feedback_success_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Text(
            stringResource(R.string.feedback_success_body),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(8.dp))
        TextButton(onClick = onDone) {
            Text(stringResource(R.string.feedback_done))
        }
    }
}

@Composable
private fun ErrorPane(
    onRetry: () -> Unit,
    onDismiss: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 28.dp, vertical = 36.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            stringResource(R.string.feedback_error_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Text(
            stringResource(R.string.feedback_error_body),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(12.dp))
        Button(
            onClick = onRetry,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(14.dp),
        ) {
            Text(stringResource(R.string.action_retry))
        }
        TextButton(onClick = onDismiss) {
            Text(stringResource(R.string.action_cancel))
        }
    }
}
