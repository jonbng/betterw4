package dk.betterlectio.android.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Percentage circle — iOS AbsenceView / Flutter absence_percentage_circle.
 * @param fraction 0.0–1.0 absence rate
 * @param approved when true, shows a green check (iOS godskrevet indicator)
 */
@Composable
fun AbsenceRing(
    fraction: Double,
    modifier: Modifier = Modifier,
    size: Dp = 56.dp,
    trackColor: Color = Color.Unspecified,
    /** Summary bands (iOS absenceColor): green &lt;5, yellow &lt;10, orange &lt;15, else red. */
    useSummaryBands: Boolean = true,
    approved: Boolean = false,
    /** One decimal like iOS "%.1f%%"; false uses whole percent for compact entry rings. */
    oneDecimal: Boolean = true,
) {
    val pct = (fraction * 100).coerceIn(0.0, 100.0)
    val color = when {
        approved -> Color(0xFF2E7D32)
        useSummaryBands -> summaryBandColor(pct)
        else -> entryBandColor(pct)
    }
    val resolvedTrack = if (trackColor == Color.Unspecified) color.copy(alpha = 0.2f) else trackColor
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.matchParentSize()) {
            val stroke = Stroke(width = size.toPx() * 0.12f, cap = StrokeCap.Round)
            drawArc(
                color = resolvedTrack,
                startAngle = -90f,
                sweepAngle = 360f,
                useCenter = false,
                style = stroke,
            )
            drawArc(
                color = color,
                startAngle = -90f,
                sweepAngle = (360f * fraction.toFloat()).coerceIn(0f, 360f),
                useCenter = false,
                style = stroke,
            )
        }
        if (approved) {
            Icon(
                Icons.Default.Check,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(size * 0.38f),
            )
        } else {
            val label = if (oneDecimal) "%.1f%%".format(pct) else "%.0f%%".format(pct)
            Text(
                label,
                fontSize = if (size < 50.dp) 10.sp else 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = color,
            )
        }
    }
}

/** iOS AbsenceViewModel.absenceColor */
fun summaryBandColor(pct: Double): Color = when {
    pct < 5 -> Color(0xFF2E7D32)
    pct < 10 -> Color(0xFFF9A825)
    pct < 15 -> Color(0xFFEF6C00)
    else -> Color(0xFFC62828)
}

/** iOS absencePercentColor for entry rings */
fun entryBandColor(pct: Double): Color = when {
    pct == 0.0 -> Color(0xFF2E7D32)
    pct < 50 -> Color(0xFFEF6C00)
    else -> Color(0xFFC62828)
}
