package dk.betterlectio.android.ui.components.bbcode

import android.graphics.Color as AndroidColor
import android.graphics.Typeface
import android.text.Editable
import android.text.Spanned
import android.text.TextWatcher
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import android.util.TypedValue
import android.view.Gravity
import android.widget.EditText
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.FormatListBulleted
import androidx.compose.material.icons.filled.FormatBold
import androidx.compose.material.icons.filled.FormatItalic
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.FormatUnderlined
import androidx.compose.material.icons.filled.Link
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import dk.betterlectio.android.R
import dk.betterlectio.android.feature.messages.BbcodeSpannable
import dk.betterlectio.android.feature.messages.BbcodeSpannable.StyleKind

/**
 * Stable rich-text BBCode editor.
 *
 * Uses a platform [EditText] + [android.text.Spannable] (Android equivalent of the
 * extension's contentEditable) instead of Compose TextField spans, which lose
 * selection/styles when the toolbar steals focus.
 *
 * Toolbar buttons are non-focusable so the EditText keeps its selection
 * (same idea as preventing mousedown default on the extension toolbar).
 */
@Composable
fun BbcodeEditor(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    placeholder: String? = null,
    minLines: Int = 6,
    maxLines: Int = 16,
    enabled: Boolean = true,
) {
    val linkColor = MaterialTheme.colorScheme.primary.toArgb()
    val textColor = MaterialTheme.colorScheme.onSurface.toArgb()
    val hintColor = MaterialTheme.colorScheme.onSurfaceVariant.toArgb()
    val density = LocalDensity.current
    val minHeightPx = with(density) { (minLines * 24).dp.roundToPx() }

    var editTextRef by remember { mutableStateOf<EditText?>(null) }
    var lastExported by remember { mutableStateOf(value) }
    var boldActive by remember { mutableStateOf(false) }
    var italicActive by remember { mutableStateOf(false) }
    var underlineActive by remember { mutableStateOf(false) }
    // Format-as-you-type when caret is collapsed (extension execCommand behavior).
    var pendingBold by remember { mutableStateOf(false) }
    var pendingItalic by remember { mutableStateOf(false) }
    var pendingUnderline by remember { mutableStateOf(false) }

    var showLinkDialog by remember { mutableStateOf(false) }
    var linkUrl by remember { mutableStateOf("") }

    fun refreshActiveFromSelection(edit: EditText) {
        val start = edit.selectionStart
        val end = edit.selectionEnd
        if (start < 0 || end <= start) {
            boldActive = pendingBold
            italicActive = pendingItalic
            underlineActive = pendingUnderline
            return
        }
        // Real selection wins over pending typing styles.
        pendingBold = false
        pendingItalic = false
        pendingUnderline = false
        boldActive = BbcodeSpannable.rangeHasStyle(edit, StyleKind.Bold)
        italicActive = BbcodeSpannable.rangeHasStyle(edit, StyleKind.Italic)
        underlineActive = BbcodeSpannable.rangeHasStyle(edit, StyleKind.Underline)
    }

    fun emitFrom(edit: EditText) {
        val bb = BbcodeSpannable.spannableToBbcode(edit.text ?: "")
        lastExported = bb
        onValueChange(bb)
        refreshActiveFromSelection(edit)
    }

    // Parent reset (open compose / clear) — not our own echo.
    LaunchedEffect(value, linkColor) {
        if (value == lastExported) return@LaunchedEffect
        editTextRef?.let { edit ->
            BbcodeSpannable.setFromBbcode(edit, value, linkColor)
            lastExported = value
            pendingBold = false
            pendingItalic = false
            pendingUnderline = false
            refreshActiveFromSelection(edit)
        }
    }

    fun withEdit(block: (EditText) -> Unit) {
        val edit = editTextRef ?: return
        // Keep focus so selection is not cleared mid-action.
        if (!edit.hasFocus()) edit.requestFocus()
        block(edit)
        emitFrom(edit)
    }

    fun toggleOrPending(kind: StyleKind) {
        val edit = editTextRef ?: return
        if (!edit.hasFocus()) edit.requestFocus()
        val start = edit.selectionStart
        val end = edit.selectionEnd
        if (start >= 0 && end > start) {
            when (kind) {
                StyleKind.Bold -> boldActive = BbcodeSpannable.toggleStyle(edit, kind, linkColor)
                StyleKind.Italic -> italicActive = BbcodeSpannable.toggleStyle(edit, kind, linkColor)
                StyleKind.Underline -> underlineActive = BbcodeSpannable.toggleStyle(edit, kind, linkColor)
            }
            emitFrom(edit)
        } else {
            when (kind) {
                StyleKind.Bold -> {
                    pendingBold = !pendingBold
                    boldActive = pendingBold
                }
                StyleKind.Italic -> {
                    pendingItalic = !pendingItalic
                    italicActive = pendingItalic
                }
                StyleKind.Underline -> {
                    pendingUnderline = !pendingUnderline
                    underlineActive = pendingUnderline
                }
            }
        }
    }

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (label != null) {
            Text(
                label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        BbcodeToolbar(
            enabled = enabled,
            boldActive = boldActive,
            italicActive = italicActive,
            underlineActive = underlineActive,
            onBold = { toggleOrPending(StyleKind.Bold) },
            onItalic = { toggleOrPending(StyleKind.Italic) },
            onUnderline = { toggleOrPending(StyleKind.Underline) },
            onLink = {
                linkUrl = ""
                showLinkDialog = true
            },
            onBulletList = {
                withEdit { BbcodeSpannable.insertListPrefix(it, ordered = false) }
            },
            onNumberedList = {
                withEdit { BbcodeSpannable.insertListPrefix(it, ordered = true) }
            },
        )

        val shape = RoundedCornerShape(12.dp)
        val borderColor = MaterialTheme.colorScheme.outline
        AndroidView(
            factory = { context ->
                object : EditText(context) {
                    override fun onSelectionChanged(selStart: Int, selEnd: Int) {
                        super.onSelectionChanged(selStart, selEnd)
                        // Called during construction before fully ready — guard.
                        if (text != null) {
                            refreshActiveFromSelection(this)
                        }
                    }
                }.apply {
                    setBackgroundColor(AndroidColor.TRANSPARENT)
                    setTextColor(textColor)
                    setHintTextColor(hintColor)
                    hint = placeholder
                    gravity = Gravity.TOP or Gravity.START
                    minHeight = minHeightPx
                    val pad = (16 * resources.displayMetrics.density).toInt()
                    val padV = (12 * resources.displayMetrics.density).toInt()
                    setPadding(pad, padV, pad, padV)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                    // Avoid LinkMovementMethod stealing selection / opening URLs while editing
                    movementMethod = null
                    isEnabled = enabled
                    BbcodeSpannable.setFromBbcode(this, value, linkColor)
                    lastExported = value

                    addTextChangedListener(object : TextWatcher {
                        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                            // Apply pending typing styles to newly inserted characters.
                            if (count <= 0) return
                            if (!pendingBold && !pendingItalic && !pendingUnderline) return
                            val editable = text ?: return
                            val end = (start + count).coerceAtMost(editable.length)
                            if (start >= end) return
                            val flag = Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                            when {
                                pendingBold && pendingItalic ->
                                    editable.setSpan(StyleSpan(Typeface.BOLD_ITALIC), start, end, flag)
                                pendingBold ->
                                    editable.setSpan(StyleSpan(Typeface.BOLD), start, end, flag)
                                pendingItalic ->
                                    editable.setSpan(StyleSpan(Typeface.ITALIC), start, end, flag)
                            }
                            if (pendingUnderline) {
                                editable.setSpan(UnderlineSpan(), start, end, flag)
                            }
                        }
                        override fun afterTextChanged(s: Editable?) {
                            val bb = BbcodeSpannable.spannableToBbcode(s ?: "")
                            if (bb != lastExported) {
                                lastExported = bb
                                onValueChange(bb)
                            }
                        }
                    })
                }.also { editTextRef = it }
            },
            update = { edit ->
                edit.isEnabled = enabled
                edit.setTextColor(textColor)
                edit.setHintTextColor(hintColor)
                edit.hint = placeholder
                if (editTextRef !== edit) editTextRef = edit
            },
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 120.dp, max = (maxLines * 24).dp)
                .clip(shape)
                .border(1.dp, borderColor, shape)
                .background(MaterialTheme.colorScheme.surface, shape),
        )
    }

    if (showLinkDialog) {
        AlertDialog(
            onDismissRequest = { showLinkDialog = false },
            title = { Text(stringResource(R.string.message_bbcode_link_title)) },
            text = {
                OutlinedTextField(
                    value = linkUrl,
                    onValueChange = { linkUrl = it },
                    label = { Text(stringResource(R.string.message_bbcode_link_url)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        withEdit { edit ->
                            BbcodeSpannable.applyLink(edit, linkUrl, linkColor)
                        }
                        showLinkDialog = false
                    },
                ) {
                    Text(stringResource(R.string.message_bbcode_link_insert))
                }
            },
            dismissButton = {
                TextButton(onClick = { showLinkDialog = false }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        )
    }
}

@Composable
fun BbcodeToolbar(
    enabled: Boolean,
    boldActive: Boolean = false,
    italicActive: Boolean = false,
    underlineActive: Boolean = false,
    onBold: () -> Unit,
    onItalic: () -> Unit,
    onUnderline: () -> Unit,
    onLink: () -> Unit,
    onBulletList: () -> Unit,
    onNumberedList: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val activeTint = MaterialTheme.colorScheme.primary
    val idleTint = if (enabled) {
        MaterialTheme.colorScheme.onSurface
    } else {
        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
    }
    // Non-focusable toolbar: EditText keeps selection (extension mousedown trick).
    val noFocus = Modifier.focusProperties { canFocus = false }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .then(noFocus),
        horizontalArrangement = Arrangement.spacedBy(0.dp),
    ) {
        IconButton(onClick = onBold, enabled = enabled, modifier = noFocus) {
            Icon(
                Icons.Default.FormatBold,
                contentDescription = stringResource(R.string.message_bbcode_bold),
                tint = if (boldActive) activeTint else idleTint,
            )
        }
        IconButton(onClick = onItalic, enabled = enabled, modifier = noFocus) {
            Icon(
                Icons.Default.FormatItalic,
                contentDescription = stringResource(R.string.message_bbcode_italic),
                tint = if (italicActive) activeTint else idleTint,
            )
        }
        IconButton(onClick = onUnderline, enabled = enabled, modifier = noFocus) {
            Icon(
                Icons.Default.FormatUnderlined,
                contentDescription = stringResource(R.string.message_bbcode_underline),
                tint = if (underlineActive) activeTint else idleTint,
            )
        }
        IconButton(onClick = onLink, enabled = enabled, modifier = noFocus) {
            Icon(
                Icons.Default.Link,
                contentDescription = stringResource(R.string.message_bbcode_link),
                tint = idleTint,
            )
        }
        IconButton(onClick = onBulletList, enabled = enabled, modifier = noFocus) {
            Icon(
                Icons.AutoMirrored.Filled.FormatListBulleted,
                contentDescription = stringResource(R.string.message_bbcode_list_bullet),
                tint = idleTint,
            )
        }
        IconButton(onClick = onNumberedList, enabled = enabled, modifier = noFocus) {
            Icon(
                Icons.Default.FormatListNumbered,
                contentDescription = stringResource(R.string.message_bbcode_list_numbered),
                tint = idleTint,
            )
        }
    }
}
