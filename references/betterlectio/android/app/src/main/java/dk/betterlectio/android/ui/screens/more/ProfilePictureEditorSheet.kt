package dk.betterlectio.android.ui.screens.more

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Upload
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import dk.betterlectio.android.R
import dk.betterlectio.android.feature.profilepicture.ProfilePictureState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

private const val MAX_PROFILE_PICTURE_BYTES = 5 * 1024 * 1024

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ProfilePictureEditorSheet(
    state: ProfilePictureState?,
    loading: Boolean,
    uploading: Boolean,
    errorText: String?,
    onDismiss: () -> Unit,
    onRefresh: () -> Unit,
    onSubmit: (ByteArray, String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var selectedUri by remember { mutableStateOf<Uri?>(null) }
    var selectedBytes by remember { mutableStateOf<ByteArray?>(null) }
    var selectedMime by remember { mutableStateOf<String?>(null) }
    var localError by remember { mutableStateOf<String?>(null) }
    var reading by remember { mutableStateOf(false) }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        reading = true
        localError = null
        scope.launch {
            val mime = normalizeMime(context.contentResolver.getType(uri))
            val bytes = if (mime != null) readLimitedBytes(context.contentResolver, uri) else null
            reading = false
            if (mime == null || bytes == null) {
                selectedUri = null
                selectedBytes = null
                selectedMime = null
                localError = context.getString(R.string.profile_picture_invalid_file)
            } else {
                selectedUri = uri
                selectedBytes = bytes
                selectedMime = mime
            }
        }
    }

    ModalBottomSheet(onDismissRequest = { if (!uploading) onDismiss() }) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                stringResource(R.string.profile_picture_title),
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                stringResource(R.string.profile_picture_format_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
            Spacer(Modifier.height(20.dp))

            Box(contentAlignment = Alignment.BottomEnd) {
                Surface(
                    modifier = Modifier
                        .width(144.dp)
                        .height(192.dp),
                    shape = RoundedCornerShape(24.dp),
                    color = MaterialTheme.colorScheme.surfaceContainerHighest,
                    shadowElevation = 6.dp,
                ) {
                    val model: Any? = selectedUri ?: state?.currentUrl
                    if (model != null) {
                        AsyncImage(
                            model = model,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            alignment = Alignment.TopCenter,
                            modifier = Modifier.clip(RoundedCornerShape(24.dp)),
                        )
                    } else {
                        Box(Modifier.background(MaterialTheme.colorScheme.surfaceContainerHighest), contentAlignment = Alignment.Center) {
                            Icon(Icons.Default.Edit, contentDescription = null, modifier = Modifier.size(36.dp))
                        }
                    }
                }
                if (state?.unlocked == true) {
                    Surface(
                        shape = RoundedCornerShape(999.dp),
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(38.dp),
                        shadowElevation = 3.dp,
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(Icons.Default.Check, contentDescription = null, tint = MaterialTheme.colorScheme.onPrimary, modifier = Modifier.size(20.dp))
                        }
                    }
                }
            }

            Spacer(Modifier.height(22.dp))

            when {
                loading && state == null -> LinearProgressIndicator(Modifier.fillMaxWidth())
                state == null -> TextButton(onClick = onRefresh) { Text(stringResource(R.string.profile_picture_refresh)) }
                !state.unlocked -> LockedState(state)
                state.isPending -> PendingState(onRefresh)
                else -> {
                    if (state.wasRejected) RejectedState(state)
                    val nextDate = state.nextEligibleLabel()
                    if (!state.canSubmit && nextDate != null) {
                        Text(
                            stringResource(R.string.profile_picture_cooldown, nextDate),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    } else {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            OutlinedButton(
                                onClick = {
                                    picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                                },
                                enabled = !uploading && !reading,
                                modifier = Modifier.weight(1f),
                            ) {
                                Icon(Icons.Default.Edit, contentDescription = null)
                                Spacer(Modifier.size(8.dp))
                                Text(stringResource(if (selectedBytes == null) R.string.profile_picture_choose else R.string.profile_picture_choose_another))
                            }
                            if (selectedBytes != null && selectedMime != null) {
                                Button(
                                    onClick = { onSubmit(selectedBytes!!, selectedMime!!) },
                                    enabled = !uploading && !reading,
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Icon(Icons.Default.Upload, contentDescription = null)
                                    Spacer(Modifier.size(8.dp))
                                    Text(stringResource(if (uploading) R.string.profile_picture_uploading else R.string.profile_picture_submit))
                                }
                            }
                        }
                    }
                }
            }

            (localError ?: errorText)?.let {
                Text(
                    it,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 12.dp),
                )
            }
        }
    }
}

@Composable
private fun LockedState(state: ProfilePictureState) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Outlined.Lock, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Text(
            stringResource(R.string.profile_picture_locked, state.referralConversions, state.unlockThreshold),
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 8.dp),
        )
        LinearProgressIndicator(
            progress = { (state.referralConversions.toFloat() / state.unlockThreshold).coerceIn(0f, 1f) },
            modifier = Modifier.fillMaxWidth().padding(top = 14.dp).height(7.dp).clip(RoundedCornerShape(99.dp)),
        )
    }
}

@Composable
private fun PendingState(onRefresh: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Default.Shield, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
        Text(stringResource(R.string.profile_picture_pending_title), fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 8.dp))
        Text(
            stringResource(R.string.profile_picture_pending_body),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 4.dp),
        )
        TextButton(onClick = onRefresh) {
            Icon(Icons.Default.Refresh, contentDescription = null)
            Spacer(Modifier.size(6.dp))
            Text(stringResource(R.string.profile_picture_refresh))
        }
    }
}

@Composable
private fun RejectedState(state: ProfilePictureState) {
    val reason = when (state.submission?.rejectionReason) {
        "inappropriate" -> stringResource(R.string.profile_picture_reason_inappropriate)
        "privacy_or_impersonation" -> stringResource(R.string.profile_picture_reason_privacy)
        "unsuitable" -> stringResource(R.string.profile_picture_reason_unsuitable)
        else -> stringResource(R.string.profile_picture_reason_other)
    }
    Surface(
        color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.55f),
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth().padding(bottom = 14.dp),
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.Top) {
            Icon(Icons.Default.Warning, contentDescription = null, tint = MaterialTheme.colorScheme.error)
            Spacer(Modifier.size(10.dp))
            Column {
                Text(stringResource(R.string.profile_picture_rejected), fontWeight = FontWeight.SemiBold)
                Text(
                    listOfNotNull(reason, state.submission?.reviewNote).joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 3.dp),
                )
            }
        }
    }
}

private fun normalizeMime(raw: String?): String? = when (raw?.lowercase()) {
    "image/jpeg", "image/jpg" -> "image/jpeg"
    "image/png" -> "image/png"
    "image/webp" -> "image/webp"
    else -> null
}

private suspend fun readLimitedBytes(
    resolver: android.content.ContentResolver,
    uri: Uri,
): ByteArray? = withContext(Dispatchers.IO) {
    resolver.openInputStream(uri)?.use { input ->
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        var total = 0
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            if (total > MAX_PROFILE_PICTURE_BYTES) return@withContext null
            output.write(buffer, 0, count)
        }
        output.toByteArray().takeIf { it.isNotEmpty() }
    }
}
