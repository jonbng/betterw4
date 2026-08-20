package dk.betterw4.android.feature.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider as DayNightColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import dk.betterw4.android.MainActivity
import dk.betterw4.android.R
import dk.betterw4.android.feature.schedule.EventStatus
import dk.betterw4.android.ui.theme.BrandBlue
import dk.betterw4.android.ui.theme.StatusCancelled
import dk.betterw4.android.ui.theme.StatusChanged

import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Glance home-screen widget showing today's schedule from a structured
 * [WidgetSnapshot] written by [ScheduleWidgetSnapshot] when schedule loads.
 */
class ScheduleWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val snapshot = ScheduleWidgetCodec.decode(prefs.getString(KEY_SNAPSHOT, null))
            ?: migrateLegacy(prefs)
        val presentation = ScheduleWidgetProjector.present(snapshot)

        provideContent {
            GlanceTheme {
                ScheduleWidgetContent(
                    context = context,
                    presentation = presentation,
                )
            }
        }
    }

    companion object {
        const val PREFS = "schedule_widget"
        const val KEY_SNAPSHOT = "snapshot"

        /** Legacy keys — read once for migration. */
        const val KEY_TITLE = "title"
        const val KEY_LINES = "lines"
    }
}

private fun migrateLegacy(
    prefs: android.content.SharedPreferences,
): WidgetSnapshot? {
    val title = prefs.getString(ScheduleWidget.KEY_TITLE, null) ?: return null
    val lines = prefs.getString(ScheduleWidget.KEY_LINES, null)
        ?.split("\n")
        ?.filter { it.isNotBlank() }
        .orEmpty()
    if (lines.isEmpty() && title.isBlank()) return null
    // Treat legacy dumps as stale so we don't invent lesson structure.
    return WidgetSnapshot(
        date = "",
        dayLabel = title,
        lessons = emptyList(),
    )
}

@Composable
private fun ScheduleWidgetContent(
    context: Context,
    presentation: WidgetPresentation,
) {
    val size = LocalSize.current
    val openApp = actionStartActivity<MainActivity>()
    val rowBudget = rowBudgetFor(size)

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .background(GlanceTheme.colors.widgetBackground)
            .cornerRadius(20.dp)
            .clickable(openApp)
            .padding(horizontal = 14.dp, vertical = 12.dp),
    ) {
        WidgetHeader(
            title = context.getString(R.string.widget_schedule_label),
            subtitle = presentation.dayLabel.ifBlank {
                ScheduleWidgetSnapshot.defaultDayLabel()
            },
        )

        Spacer(GlanceModifier.height(8.dp))

        when (presentation.kind) {
            WidgetContentKind.STALE -> {
                EmptyMessage(context.getString(R.string.widget_open_app_hint))
            }
            WidgetContentKind.FREE_DAY -> {
                EmptyMessage(context.getString(R.string.widget_free_day))
            }
            WidgetContentKind.CONTENT -> {
                // Nested column keeps the outer tree under Glance's 10-child limit.
                // Each list entry is a single child (padding replaces inter-item Spacers).
                Column(modifier = GlanceModifier.fillMaxWidth()) {
                    val featured = presentation.featured
                    var childCount = 0
                    if (featured != null && presentation.featuredKind != null) {
                        FeaturedLesson(
                            context = context,
                            kind = presentation.featuredKind,
                            lesson = featured,
                        )
                        childCount++
                    } else if (presentation.rows.isEmpty() || rowBudget == 0) {
                        EmptyMessage(context.getString(R.string.widget_day_done))
                        childCount++
                    }

                    if (featured != null || rowBudget > 0) {
                        // Leave room for an overflow label (max 10 children total).
                        val maxRows = (10 - childCount - 1).coerceAtLeast(0).coerceAtMost(rowBudget)
                        val visible = presentation.rows.take(maxRows)
                        visible.forEachIndexed { index, lesson ->
                            LessonRow(
                                context = context,
                                lesson = lesson,
                                modifier = GlanceModifier.padding(
                                    top = if (index == 0 && featured != null) 8.dp else if (index > 0) 4.dp else 0.dp,
                                ),
                            )
                        }
                        val overflow = presentation.rows.size - visible.size
                        if (overflow > 0) {
                            Text(
                                text = context.getString(R.string.widget_more, overflow),
                                style = TextStyle(
                                    fontSize = 11.sp,
                                    color = GlanceTheme.colors.onSurfaceVariant,
                                ),
                                modifier = GlanceModifier.padding(top = 4.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun rowBudgetFor(size: DpSize): Int {
    // Keep nested Column children ≤ 10 (featured + spacers + rows + overflow).
    val height = size.height.value
    return when {
        height < 130f -> 0
        height < 180f -> 2
        height < 240f -> 3
        height < 300f -> 4
        else -> 5
    }
}

@Composable
private fun WidgetHeader(title: String, subtitle: String) {
    Row(
        modifier = GlanceModifier.fillMaxWidth(),
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        Text(
            text = title,
            style = TextStyle(
                fontWeight = FontWeight.Bold,
                fontSize = 14.sp,
                color = GlanceTheme.colors.onSurface,
            ),
            modifier = GlanceModifier.defaultWeight(),
        )
        if (subtitle.isNotBlank()) {
            Text(
                text = subtitle,
                style = TextStyle(
                    fontSize = 11.sp,
                    color = GlanceTheme.colors.onSurfaceVariant,
                    textAlign = TextAlign.End,
                ),
            )
        }
    }
}

@Composable
private fun EmptyMessage(message: String) {
    Text(
        text = message,
        style = TextStyle(
            fontSize = 13.sp,
            color = GlanceTheme.colors.onSurfaceVariant,
        ),
        modifier = GlanceModifier.fillMaxWidth().padding(top = 4.dp),
    )
}

@Composable
private fun FeaturedLesson(
    context: Context,
    kind: WidgetFeaturedKind,
    lesson: WidgetLesson,
) {
    val accent = accentColor(lesson)
    val label = when (kind) {
        WidgetFeaturedKind.CURRENT -> context.getString(R.string.widget_now)
        WidgetFeaturedKind.NEXT -> context.getString(R.string.widget_next)
    }
    val cancelled = lesson.status == EventStatus.CANCELLED.name
    val titleColor = if (cancelled) {
        GlanceTheme.colors.onSurfaceVariant
    } else {
        GlanceTheme.colors.onSurface
    }

    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .cornerRadius(12.dp)
            .background(GlanceTheme.colors.surface)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.Vertical.Top,
    ) {
        Spacer(
            modifier = GlanceModifier
                .width(3.dp)
                .height(36.dp)
                .cornerRadius(2.dp)
                .background(ColorProvider(accent)),
        )
        Spacer(GlanceModifier.width(10.dp))
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                text = label,
                style = TextStyle(
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Medium,
                    color = GlanceTheme.colors.onSurfaceVariant,
                ),
            )
            Spacer(GlanceModifier.height(2.dp))
            Text(
                text = lesson.title,
                style = TextStyle(
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    color = titleColor,
                ),
                maxLines = 1,
            )
            Spacer(GlanceModifier.height(2.dp))
            Text(
                text = featuredMeta(context, lesson),
                style = TextStyle(
                    fontSize = 11.sp,
                    color = GlanceTheme.colors.onSurfaceVariant,
                ),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun LessonRow(
    context: Context,
    lesson: WidgetLesson,
    modifier: GlanceModifier = GlanceModifier,
) {
    val accent = accentColor(lesson)
    val cancelled = lesson.status == EventStatus.CANCELLED.name
    val titleColor = if (cancelled) {
        GlanceTheme.colors.onSurfaceVariant
    } else {
        GlanceTheme.colors.onSurface
    }

    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        Spacer(
            modifier = GlanceModifier
                .width(3.dp)
                .height(22.dp)
                .cornerRadius(2.dp)
                .background(ColorProvider(accent)),
        )
        Spacer(GlanceModifier.width(8.dp))
        Text(
            text = lesson.startLabel.ifBlank { "—" },
            style = TextStyle(
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                color = GlanceTheme.colors.onSurfaceVariant,
            ),
            modifier = GlanceModifier.width(40.dp),
            maxLines = 1,
        )
        Text(
            text = lesson.title,
            style = TextStyle(
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
                color = titleColor,
            ),
            modifier = GlanceModifier.defaultWeight(),
            maxLines = 1,
        )
        val trailing = buildString {
            statusShort(context, lesson)?.let(::append)
            lesson.room?.takeIf { it.isNotBlank() }?.let { room ->
                if (isNotEmpty()) append(" · ")
                append(room)
            }
        }
        if (trailing.isNotBlank()) {
            Spacer(GlanceModifier.width(6.dp))
            Text(
                text = trailing,
                style = TextStyle(
                    fontSize = 11.sp,
                    color = statusColor(lesson) ?: GlanceTheme.colors.onSurfaceVariant,
                ),
                maxLines = 1,
            )
        }
    }
}

private fun featuredMeta(context: Context, lesson: WidgetLesson): String {
    val parts = mutableListOf<String>()
    lesson.timeRange.takeIf { it.isNotBlank() }?.let(parts::add)
    lesson.room?.takeIf { it.isNotBlank() }?.let(parts::add)
    statusShort(context, lesson)?.let(parts::add)
    return parts.joinToString(" · ")
}

private fun statusShort(context: Context, lesson: WidgetLesson): String? = when (lesson.status) {
    EventStatus.CHANGED.name -> context.getString(R.string.event_status_changed)
    EventStatus.CANCELLED.name -> context.getString(R.string.event_status_cancelled)
    else -> null
}

@Composable
private fun statusColor(lesson: WidgetLesson): ColorProvider? = when (lesson.status) {
    EventStatus.CHANGED.name -> DayNightColorProvider(StatusChanged, StatusChanged)
    EventStatus.CANCELLED.name -> DayNightColorProvider(StatusCancelled, StatusCancelled)
    else -> null
}

private fun accentColor(lesson: WidgetLesson): Color {
    val raw = lesson.accentArgb
    return if (raw == 0L) BrandBlue else Color(raw.toInt())
}

class ScheduleWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ScheduleWidget()
}

object ScheduleWidgetSnapshot {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun write(context: Context, snapshot: WidgetSnapshot) {
        context.getSharedPreferences(ScheduleWidget.PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(ScheduleWidget.KEY_SNAPSHOT, ScheduleWidgetCodec.encode(snapshot))
            .remove(ScheduleWidget.KEY_TITLE)
            .remove(ScheduleWidget.KEY_LINES)
            .apply()
        scope.launch {
            try {
                ScheduleWidget().updateAll(context.applicationContext)
            } catch (_: Exception) {
                // Best-effort; next launcher request will pick up prefs.
            }
        }
    }

    fun defaultDayLabel(date: LocalDate = LocalDate.now()): String {
        val fmt = DateTimeFormatter.ofPattern("EEE d. MMM", Locale.getDefault())
        return date.format(fmt)
    }

    fun epochMilli(dateTime: java.time.LocalDateTime?, zoneId: ZoneId = ZoneId.systemDefault()): Long? =
        dateTime?.atZone(zoneId)?.toInstant()?.toEpochMilli()
}
