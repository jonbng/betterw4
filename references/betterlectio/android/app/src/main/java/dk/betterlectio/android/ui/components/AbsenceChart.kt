package dk.betterlectio.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dk.betterlectio.android.feature.absence.AbsenceChartBar

/**
 * Horizontal bar breakdown of absence by team (Flutter AbsenceChart parity).
 */
@Composable
fun AbsenceBarChart(
    bars: List<AbsenceChartBar>,
    modifier: Modifier = Modifier,
) {
    if (bars.isEmpty()) return
    val maxFrac = bars.maxOf { it.fraction }.coerceAtLeast(0.01)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        bars.forEach { bar ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    bar.label,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.widthIn(min = 48.dp, max = 72.dp),
                    maxLines = 1,
                )
                val track = MaterialTheme.colorScheme.surfaceVariant
                val fill = barColor(bar.fraction)
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(14.dp)
                        .clip(RoundedCornerShape(7.dp))
                        .background(track),
                ) {
                    val widthFrac = (bar.fraction / maxFrac).toFloat().coerceIn(0.02f, 1f)
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(widthFrac)
                            .height(14.dp)
                            .clip(RoundedCornerShape(7.dp))
                            .background(fill),
                    )
                }
                Text(
                    "%.0f%%".format(bar.percent),
                    style = MaterialTheme.typography.labelSmall,
                    color = fill,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.widthIn(min = 36.dp),
                )
            }
        }
    }
}

private fun barColor(fraction: Double): Color {
    val pct = fraction * 100
    return when {
        pct < 5 -> Color(0xFF2E7D32)
        pct < 10 -> Color(0xFFF9A825)
        else -> Color(0xFFC62828)
    }
}
