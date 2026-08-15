package dk.betterlectio.android.ui.components

import android.text.method.LinkMovementMethod
import android.widget.TextView
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BrokenImage
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.text.HtmlCompat
import coil3.compose.SubcomposeAsyncImage
import coil3.request.ImageRequest
import coil3.request.crossfade
import dk.betterlectio.android.R
import dk.betterlectio.android.feature.attachments.AttachmentClassifier
import dk.betterlectio.android.feature.content.LectioHtmlSegment
import dk.betterlectio.android.feature.content.LectioHtmlSegments

/**
 * Cookie-aware Lectio image via the app Coil [ImageLoader] (session cookies injected in AppModule).
 * Tap opens a full-screen preview.
 */
@Composable
fun LectioAsyncImage(
    url: String,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    maxHeight: Dp = 320.dp,
    contentScale: ContentScale = ContentScale.Fit,
) {
    val context = LocalContext.current
    val absolute = remember(url) { AttachmentClassifier.absolutize(url) }
    var showPreview by remember { mutableStateOf(false) }
    val request = remember(absolute) {
        ImageRequest.Builder(context)
            .data(absolute)
            .crossfade(true)
            .build()
    }

    SubcomposeAsyncImage(
        model = request,
        contentDescription = contentDescription,
        contentScale = contentScale,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(max = maxHeight)
            .clip(RoundedCornerShape(10.dp))
            .clickable(enabled = absolute.isNotBlank()) { showPreview = true },
        loading = {
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 96.dp)
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(Modifier.size(28.dp), strokeWidth = 2.dp)
            }
        },
        error = {
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 72.dp)
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                    .padding(12.dp),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.BrokenImage,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        stringResource(R.string.image_load_failed),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        },
    )

    if (showPreview) {
        LectioImagePreviewDialog(
            url = absolute,
            contentDescription = contentDescription,
            onDismiss = { showPreview = false },
        )
    }
}

@Composable
fun LectioImagePreviewDialog(
    url: String,
    contentDescription: String?,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val absolute = remember(url) { AttachmentClassifier.absolutize(url) }
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.92f)),
        ) {
            SubcomposeAsyncImage(
                model = ImageRequest.Builder(context)
                    .data(absolute)
                    .crossfade(true)
                    .build(),
                contentDescription = contentDescription,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp),
                loading = {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color.White)
                    }
                },
                error = {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            stringResource(R.string.image_load_failed),
                            color = Color.White,
                        )
                    }
                },
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
        }
    }
}

/**
 * Renders Lectio HTML (messages, homework fragments) with bold/italic/links and real images.
 * Uses the cookie-aware Coil loader so Lectio `GetFile` / `GetImage` URLs work.
 */
@Composable
fun LectioHtmlBody(
    html: String?,
    modifier: Modifier = Modifier,
    imageMaxHeight: Dp = 320.dp,
) {
    val segments = remember(html) { LectioHtmlSegments.parse(html) }
    if (segments.isEmpty()) return

    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        segments.forEach { segment ->
            when (segment) {
                is LectioHtmlSegment.Text -> HtmlTextBlock(segment.html)
                is LectioHtmlSegment.Image -> LectioAsyncImage(
                    url = segment.url,
                    contentDescription = segment.alt,
                    maxHeight = imageMaxHeight,
                )
                LectioHtmlSegment.Divider -> HorizontalDivider(
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f),
                )
            }
        }
    }
}

/**
 * Lesson content blocks from [dk.betterlectio.android.feature.schedule.LessonDetailParser].
 */
@Composable
fun LessonContentBlocks(
    blocks: List<dk.betterlectio.android.feature.schedule.LessonContentBlock>,
    modifier: Modifier = Modifier,
    imageMaxHeight: Dp = 320.dp,
) {
    if (blocks.isEmpty()) return
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        blocks.forEach { block ->
            when (block.kind) {
                "heading" -> Text(
                    block.text,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
                    modifier = Modifier.padding(top = 4.dp),
                )
                "note" -> Text(
                    block.text,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                "image" -> {
                    val url = block.url
                    if (!url.isNullOrBlank()) {
                        LectioAsyncImage(
                            url = url,
                            contentDescription = block.text.ifBlank { null },
                            maxHeight = imageMaxHeight,
                        )
                    } else if (block.text.isNotBlank()) {
                        Text(block.text, style = MaterialTheme.typography.bodyMedium)
                    }
                }
                "divider" -> HorizontalDivider(
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.6f),
                )
                else -> {
                    if (block.text.isNotBlank()) {
                        Text(block.text, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        }
    }
}

@Composable
private fun HtmlTextBlock(html: String) {
    val textColor = MaterialTheme.colorScheme.onSurface
    val linkColor = MaterialTheme.colorScheme.primary
    val spanned = remember(html) {
        HtmlCompat.fromHtml(html, HtmlCompat.FROM_HTML_MODE_COMPACT)
    }
    AndroidView(
        factory = { ctx ->
            TextView(ctx).apply {
                setTextIsSelectable(true)
                movementMethod = LinkMovementMethod.getInstance()
                textSize = 15f
                setLineSpacing(0f, 1.2f)
            }
        },
        update = { tv ->
            tv.setTextColor(textColor.toArgb())
            tv.setLinkTextColor(linkColor.toArgb())
            tv.text = spanned
        },
        modifier = Modifier.fillMaxWidth(),
    )
}
