package dk.betterlectio.android.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dk.betterlectio.android.feature.absence.SubjectAbsence

/** iOS AbsenceView subjectColors palette. */
val AbsenceSubjectColors: List<Color> = listOf(
    Color(0xFF1E88E5), // blue
    Color(0xFF8E24AA), // purple
    Color(0xFFFB8C00), // orange
    Color(0xFF00897B), // teal
    Color(0xFFD81B60), // pink
    Color(0xFF3949AB), // indigo
    Color(0xFF00ACC1), // cyan
    Color(0xFF6D4C41), // brown
    Color(0xFFE53935), // red
    Color(0xFF43A047), // green
)

/**
 * Donut + legend for per-subject entry counts (iOS "Fravær pr. fag").
 */
@Composable
fun AbsenceDonutChart(
    subjects: List<SubjectAbsence>,
    modifier: Modifier = Modifier,
    modulesLabel: String,
) {
    if (subjects.isEmpty()) return
    val total = subjects.sumOf { it.totalEntries }.coerceAtLeast(1)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(160.dp),
            contentAlignment = Alignment.Center,
        ) {
            Canvas(Modifier.size(148.dp)) {
                val strokeWidth = size.minDimension * 0.18f
                val stroke = Stroke(width = strokeWidth, cap = StrokeCap.Butt)
                var start = -90f
                subjects.forEachIndexed { index, subject ->
                    val sweep = 360f * (subject.totalEntries.toFloat() / total)
                    drawArc(
                        color = AbsenceSubjectColors[index % AbsenceSubjectColors.size],
                        startAngle = start,
                        sweepAngle = sweep,
                        useCenter = false,
                        style = stroke,
                    )
                    start += sweep
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    "$total",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                )
                Text(
                    modulesLabel,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        // 2-column legend
        val rows = subjects.chunked(2)
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            rows.forEach { pair ->
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    pair.forEach { subject ->
                        val idx = subjects.indexOf(subject)
                        Row(
                            Modifier.weight(1f),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Box(
                                Modifier
                                    .size(10.dp)
                                    .clip(CircleShape)
                                    .background(
                                        AbsenceSubjectColors[idx % AbsenceSubjectColors.size],
                                    ),
                            )
                            Text(
                                subject.subject.uppercase(),
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1,
                            )
                            Text(
                                "${subject.totalEntries}",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    if (pair.size == 1) {
                        Box(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

fun subjectColorForHold(hold: String, subjects: List<SubjectAbsence>): Color {
    val idx = subjects.indexOfFirst { it.fullHold == hold }
    if (idx < 0) return Color.Gray
    return AbsenceSubjectColors[idx % AbsenceSubjectColors.size]
}
