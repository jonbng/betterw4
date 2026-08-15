package dk.betterlectio.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import dk.betterlectio.android.R
import dk.betterlectio.android.core.result.AppError

@Composable
fun LoadingBox(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
fun ErrorBox(
    error: AppError?,
    onRetry: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val title = when (error) {
        AppError.Offline -> stringResource(R.string.error_offline)
        AppError.SessionExpired, AppError.Unauthorized -> stringResource(R.string.error_session_expired)
        AppError.RobotDetection -> stringResource(R.string.error_robot)
        is AppError.Network -> error.message ?: stringResource(R.string.error_generic)
        is AppError.Parsing -> error.message
        is AppError.Unknown -> error.message ?: stringResource(R.string.error_generic)
        null -> stringResource(R.string.error_generic)
    }
    val icon = when (error) {
        AppError.Offline -> Icons.Outlined.CloudOff
        else -> Icons.Outlined.ErrorOutline
    }
    val description = when (error) {
        AppError.Offline -> stringResource(R.string.error_offline_hint)
        AppError.SessionExpired, AppError.Unauthorized -> stringResource(R.string.error_session_hint)
        AppError.RobotDetection -> stringResource(R.string.error_robot_hint)
        else -> stringResource(R.string.error_generic_hint)
    }

    EmptyStateContent(
        icon = icon,
        title = title,
        description = description,
        modifier = modifier,
        actionLabel = if (onRetry != null) stringResource(R.string.action_retry) else null,
        onAction = onRetry,
    )
}

/**
 * Friendly empty state: icon in a soft circle, short title, optional hint + action.
 */
@Composable
fun EmptyBox(
    text: String,
    modifier: Modifier = Modifier,
    description: String? = null,
    icon: ImageVector = Icons.Outlined.Inbox,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    EmptyStateContent(
        icon = icon,
        title = text,
        description = description,
        modifier = modifier,
        actionLabel = actionLabel,
        onAction = onAction,
    )
}

@Composable
private fun EmptyStateContent(
    icon: ImageVector,
    title: String,
    description: String?,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    Column(
        modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            Modifier
                .size(72.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surfaceContainerHigh),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(32.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(20.dp))
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
        )
        if (!description.isNullOrBlank()) {
            Spacer(Modifier.height(8.dp))
            Text(
                text = description,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
        if (actionLabel != null && onAction != null) {
            Spacer(Modifier.height(20.dp))
            Button(onClick = onAction) { Text(actionLabel) }
        }
    }
}
