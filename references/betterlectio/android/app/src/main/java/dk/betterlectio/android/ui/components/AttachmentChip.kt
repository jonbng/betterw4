package dk.betterlectio.android.ui.components

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material.icons.filled.Slideshow
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import dagger.hilt.android.lifecycle.HiltViewModel
import dk.betterlectio.android.R
import dk.betterlectio.android.feature.attachments.AttachmentActionResult
import dk.betterlectio.android.feature.attachments.AttachmentError
import dk.betterlectio.android.feature.attachments.AttachmentKind
import dk.betterlectio.android.feature.attachments.AttachmentMime
import dk.betterlectio.android.feature.attachments.AttachmentRef
import dk.betterlectio.android.feature.attachments.AttachmentRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class AttachmentOpenerViewModel @Inject constructor(
    private val repository: AttachmentRepository,
) : ViewModel() {
    private val _loadingUrls = MutableStateFlow<Set<String>>(emptySet())
    val loadingUrls: StateFlow<Set<String>> = _loadingUrls.asStateFlow()

    private val _imagePreview = MutableStateFlow<AttachmentRef?>(null)
    val imagePreview: StateFlow<AttachmentRef?> = _imagePreview.asStateFlow()

    fun open(ref: AttachmentRef, onResult: (AttachmentActionResult) -> Unit) {
        viewModelScope.launch {
            markLoading(ref.url, true)
            try {
                val result = repository.open(ref)
                if (result is AttachmentActionResult.ImagePreview) {
                    _imagePreview.value = ref
                }
                onResult(result)
            } finally {
                markLoading(ref.url, false)
            }
        }
    }

    fun save(ref: AttachmentRef, onResult: (AttachmentActionResult) -> Unit) {
        viewModelScope.launch {
            markLoading(ref.url, true)
            try {
                onResult(repository.save(ref))
            } finally {
                markLoading(ref.url, false)
            }
        }
    }

    fun share(ref: AttachmentRef, onResult: (AttachmentActionResult) -> Unit) {
        viewModelScope.launch {
            markLoading(ref.url, true)
            try {
                onResult(repository.share(ref))
            } finally {
                markLoading(ref.url, false)
            }
        }
    }

    fun dismissImagePreview() {
        _imagePreview.value = null
    }

    private fun markLoading(url: String, loading: Boolean) {
        _loadingUrls.update { current ->
            if (loading) current + url else current - url
        }
    }
}

@Stable
class AttachmentFeedback(
    private val snackbarHostState: SnackbarHostState?,
    private val scope: kotlinx.coroutines.CoroutineScope,
    private val messages: AttachmentMessages,
) {
    fun handle(result: AttachmentActionResult) {
        val msg = when (result) {
            AttachmentActionResult.Opened,
            AttachmentActionResult.WebLinkOpened,
            AttachmentActionResult.Shared,
            AttachmentActionResult.ImagePreview,
            -> null
            AttachmentActionResult.Saved -> messages.saved
            is AttachmentActionResult.Failed -> messages.forError(result.error)
        } ?: return
        val host = snackbarHostState ?: return
        scope.launch { host.showSnackbar(msg) }
    }
}

data class AttachmentMessages(
    val saved: String,
    val offline: String,
    val session: String,
    val robot: String,
    val empty: String,
    val html: String,
    val noApp: String,
    val generic: String,
) {
    fun forError(error: AttachmentError): String = when (error) {
        AttachmentError.OFFLINE -> offline
        AttachmentError.SESSION -> session
        AttachmentError.ROBOT -> robot
        AttachmentError.EMPTY -> empty
        AttachmentError.HTML_INSTEAD_OF_FILE -> html
        AttachmentError.NO_APP -> noApp
        AttachmentError.GENERIC -> generic
    }
}

@Composable
fun rememberAttachmentMessages(): AttachmentMessages = AttachmentMessages(
    saved = stringResource(R.string.attachment_saved),
    offline = stringResource(R.string.attachment_error_offline),
    session = stringResource(R.string.attachment_error_session),
    robot = stringResource(R.string.attachment_error_robot),
    empty = stringResource(R.string.attachment_error_empty),
    html = stringResource(R.string.attachment_error_html),
    noApp = stringResource(R.string.attachment_error_no_app),
    generic = stringResource(R.string.attachment_error_generic),
)

@Composable
fun rememberAttachmentFeedback(
    snackbarHostState: SnackbarHostState?,
): AttachmentFeedback {
    val scope = rememberCoroutineScope()
    val messages = rememberAttachmentMessages()
    return remember(snackbarHostState, messages) {
        AttachmentFeedback(snackbarHostState, scope, messages)
    }
}

@Composable
fun AttachmentIcon(ref: AttachmentRef, modifier: Modifier = Modifier) {
    Icon(
        imageVector = attachmentIcon(ref),
        contentDescription = null,
        modifier = modifier,
        tint = MaterialTheme.colorScheme.primary,
    )
}

fun attachmentIcon(ref: AttachmentRef): ImageVector {
    if (ref.kind == AttachmentKind.WEB_LINK) return Icons.Default.Link
    if (ref.kind == AttachmentKind.IMAGE) return Icons.Default.Image
    val ext = AttachmentMime.extensionOf(ref.name)
        ?: AttachmentMime.extensionOf(ref.url)
        ?: return Icons.AutoMirrored.Filled.InsertDriveFile
    return when (ext.lowercase()) {
        "pdf" -> Icons.Default.PictureAsPdf
        "doc", "docx", "odt", "rtf", "txt" -> Icons.Default.Description
        "xls", "xlsx", "ods", "csv" -> Icons.Default.TableChart
        "ppt", "pptx", "odp" -> Icons.Default.Slideshow
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "svg" -> Icons.Default.Image
        else -> Icons.AutoMirrored.Filled.InsertDriveFile
    }
}

/**
 * Chip-style attachment control: tap to open, long-press for open/save/share.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AttachmentChip(
    name: String,
    url: String,
    isFileHint: Boolean = false,
    snackbarHostState: SnackbarHostState? = null,
    modifier: Modifier = Modifier,
    opener: AttachmentOpenerViewModel = hiltViewModel(),
) {
    val ref = remember(name, url, isFileHint) {
        AttachmentRef(name = name, url = url, isFileHint = isFileHint)
    }
    val loadingUrls by opener.loadingUrls.collectAsStateWithLifecycleCompat()
    val imagePreview by opener.imagePreview.collectAsStateWithLifecycleCompat()
    val feedback = rememberAttachmentFeedback(snackbarHostState)
    val loading = url in loadingUrls
    var menuOpen by remember { mutableStateOf(false) }

    val showMenu = ref.kind != AttachmentKind.WEB_LINK

    Box(modifier = modifier) {
        Surface(
            shape = RoundedCornerShape(12.dp),
            color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.55f),
            modifier = Modifier
                .clip(RoundedCornerShape(12.dp))
                .combinedClickable(
                    onClick = {
                        if (!loading) opener.open(ref, feedback::handle)
                    },
                    onLongClick = {
                        if (showMenu && !loading) menuOpen = true
                    },
                ),
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (loading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                    )
                } else {
                    AttachmentIcon(ref, modifier = Modifier.size(18.dp))
                }
                Text(
                    text = name.ifBlank { url },
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
            }
        }

        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.attachment_open)) },
                onClick = {
                    menuOpen = false
                    opener.open(ref, feedback::handle)
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.attachment_save)) },
                onClick = {
                    menuOpen = false
                    opener.save(ref, feedback::handle)
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.attachment_share)) },
                onClick = {
                    menuOpen = false
                    opener.share(ref, feedback::handle)
                },
            )
        }
    }

    imagePreview?.let { preview ->
        if (preview.url == url) {
            ImagePreviewDialog(
                ref = preview,
                onDismiss = opener::dismissImagePreview,
            )
        }
    }
}

/**
 * Full-width list row variant for assignment/schedule resource lists.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AttachmentRow(
    name: String,
    url: String,
    isFileHint: Boolean = false,
    snackbarHostState: SnackbarHostState? = null,
    modifier: Modifier = Modifier,
    opener: AttachmentOpenerViewModel = hiltViewModel(),
) {
    val ref = remember(name, url, isFileHint) {
        AttachmentRef(name = name, url = url, isFileHint = isFileHint)
    }
    val loadingUrls by opener.loadingUrls.collectAsStateWithLifecycleCompat()
    val imagePreview by opener.imagePreview.collectAsStateWithLifecycleCompat()
    val feedback = rememberAttachmentFeedback(snackbarHostState)
    val loading = url in loadingUrls
    var menuOpen by remember { mutableStateOf(false) }
    val showMenu = ref.kind != AttachmentKind.WEB_LINK

    Box(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .combinedClickable(
                    onClick = { if (!loading) opener.open(ref, feedback::handle) },
                    onLongClick = { if (showMenu && !loading) menuOpen = true },
                )
                .padding(vertical = 10.dp, horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (loading) {
                CircularProgressIndicator(modifier = Modifier.size(22.dp), strokeWidth = 2.dp)
            } else {
                AttachmentIcon(ref, modifier = Modifier.size(22.dp))
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = name.ifBlank { url },
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (ref.kind == AttachmentKind.WEB_LINK) {
                    Text(
                        text = url,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }

        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.attachment_open)) },
                onClick = {
                    menuOpen = false
                    opener.open(ref, feedback::handle)
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.attachment_save)) },
                onClick = {
                    menuOpen = false
                    opener.save(ref, feedback::handle)
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.attachment_share)) },
                onClick = {
                    menuOpen = false
                    opener.share(ref, feedback::handle)
                },
            )
        }
    }

    imagePreview?.let { preview ->
        if (preview.url == url) {
            ImagePreviewDialog(
                ref = preview,
                onDismiss = opener::dismissImagePreview,
            )
        }
    }
}

@Composable
private fun ImagePreviewDialog(
    ref: AttachmentRef,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.92f)),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(AttachmentClassifierAbsolutize(ref.url))
                    .crossfade(true)
                    .build(),
                contentDescription = ref.name,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp),
            )
            IconButton(
                onClick = onDismiss,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp),
            ) {
                Icon(
                    Icons.Default.Close,
                    contentDescription = stringResource(R.string.attachment_close_preview),
                    tint = MaterialTheme.colorScheme.onPrimary,
                )
            }
            Text(
                text = ref.name,
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(16.dp),
            )
        }
    }
}

/** Avoid importing classifier name clash in Compose file. */
private fun AttachmentClassifierAbsolutize(url: String): String =
    dk.betterlectio.android.feature.attachments.AttachmentClassifier.absolutize(url)

@Composable
private fun <T> StateFlow<T>.collectAsStateWithLifecycleCompat(): androidx.compose.runtime.State<T> =
    collectAsStateWithLifecycle()
