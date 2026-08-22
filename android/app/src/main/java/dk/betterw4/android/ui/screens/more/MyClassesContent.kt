package dk.betterw4.android.ui.screens.more

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Class
import androidx.compose.material.icons.filled.MeetingRoom
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dk.betterw4.android.R
import dk.betterw4.android.core.w4.W4Dates
import dk.betterw4.android.feature.classes.ClassLevel
import dk.betterw4.android.feature.classes.ClassMember
import dk.betterw4.android.feature.classes.ClassRoom
import dk.betterw4.android.feature.classes.MyClass
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import dk.betterw4.android.feature.schedule.ClassNextLesson
import dk.betterw4.android.feature.settings.SubjectColorResolver
import dk.betterw4.android.feature.settings.SubjectMapper
import dk.betterw4.android.ui.components.AppListDivider
import dk.betterw4.android.ui.components.AppListMeta
import dk.betterw4.android.ui.components.AppListPrimary
import dk.betterw4.android.ui.components.AppListRow
import dk.betterw4.android.ui.components.AppListSecondary
import dk.betterw4.android.ui.components.EmptyBox
import dk.betterw4.android.ui.components.LoadingBox
import dk.betterw4.android.ui.components.PersonAvatar
import dk.betterw4.android.ui.components.SectionHeader
import dk.betterw4.android.ui.screens.schedule.subjectIcon
import java.time.format.TextStyle
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyClassesContent(
    padding: PaddingValues,
    listState: LazyListState,
    loading: Boolean,
    classes: List<MyClass>,
    selectedClass: MyClass?,
    onOpenClass: (MyClass) -> Unit,
    onOpenPerson: (DirectoryEntity) -> Unit,
    onLongPressPerson: (DirectoryEntity) -> Unit,
    onOpenRoom: (ClassRoom) -> Unit,
    nextLessons: Map<String, ClassNextLesson> = emptyMap(),
    signedInId: String? = null,
    useSubjectColors: Boolean = true,
    onRefresh: (() -> Unit)? = null,
) {
    val refreshing = loading && (classes.isNotEmpty() || selectedClass != null)
    val body: @Composable () -> Unit = {
        when {
            selectedClass != null -> MyClassDetailContent(
                padding = if (onRefresh == null) padding else PaddingValues(0.dp),
                listState = listState,
                item = selectedClass,
                nextLesson = nextLessons[selectedClass.id.lowercase()],
                signedInId = signedInId,
                onOpenPerson = onOpenPerson,
                onLongPressPerson = onLongPressPerson,
                onOpenRoom = onOpenRoom,
            )
            loading && classes.isEmpty() -> LoadingBox(
                if (onRefresh == null) Modifier.padding(padding) else Modifier,
            )
            classes.isEmpty() -> EmptyBox(
                text = stringResource(R.string.my_classes_empty),
                description = stringResource(R.string.my_classes_empty_hint),
                icon = Icons.Default.Class,
                modifier = if (onRefresh == null) Modifier.padding(padding) else Modifier,
            )
            else -> LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .then(if (onRefresh == null) Modifier.padding(padding) else Modifier),
            ) {
                items(classes, key = { it.id }) { item ->
                    AppListRow(
                        onClick = { onOpenClass(item) },
                        leading = { SubjectGlyph(item.subject, useSubjectColors) },
                        trailing = {
                            if (item.level.badge.isNotEmpty()) {
                                LevelBadge(item.level, compact = true)
                            }
                        },
                    ) {
                        AppListPrimary(item.subject, emphasized = true)
                        classSubtitle(item)?.let { AppListSecondary(it, maxLines = 2) }
                        listMeta(item, nextLessons[item.id.lowercase()])?.let { AppListMeta(it) }
                    }
                    AppListDivider()
                }
            }
        }
    }
    if (onRefresh == null) {
        body()
        return
    }
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = onRefresh,
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
    ) {
        body()
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MyClassDetailContent(
    padding: PaddingValues,
    listState: LazyListState,
    item: MyClass,
    nextLesson: ClassNextLesson?,
    signedInId: String?,
    onOpenPerson: (DirectoryEntity) -> Unit,
    onLongPressPerson: (DirectoryEntity) -> Unit,
    onOpenRoom: (ClassRoom) -> Unit,
) {
    if (!item.loaded && item.teachers.isEmpty() && item.students.isEmpty()) {
        LoadingBox(Modifier.padding(padding))
        return
    }
    LazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
    ) {
        item(key = "header-${item.id}") {
            Column(Modifier.padding(horizontal = 16.dp, vertical = 16.dp)) {
                Text(
                    item.subject,
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.height(10.dp))
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    item.displayLevel.takeIf { it.isNotBlank() }?.let { Chip(it, levelColor(item.level)) }
                    item.year?.let { Chip(stringResource(R.string.my_classes_year, it)) }
                    item.block?.let { Chip(stringResource(R.string.my_classes_block, it)) }
                }
            }
        }
        nextLesson?.let { next ->
            item(key = "next-${item.id}") {
                AppListRow(
                    leading = {
                        Box(
                            Modifier
                                .size(40.dp)
                                .clip(RoundedCornerShape(12.dp))
                                .background(MaterialTheme.colorScheme.surfaceContainerHigh),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                Icons.Outlined.Schedule,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    },
                ) {
                    AppListPrimary(nextLessonDetailLabel(next), emphasized = true)
                    AppListSecondary(stringResource(R.string.my_classes_next_lesson))
                }
                AppListDivider()
            }
        }
        item.room?.let { room ->
            item(key = "room-${item.id}") {
                AppListRow(
                    onClick = room.id?.let { { onOpenRoom(room) } },
                    leading = {
                        Box(
                            Modifier
                                .size(40.dp)
                                .clip(RoundedCornerShape(12.dp))
                                .background(MaterialTheme.colorScheme.surfaceContainerHigh),
                            contentAlignment = Alignment.Center,
                        ) {
                            Icon(
                                Icons.Default.MeetingRoom,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    },
                ) {
                    AppListPrimary(stringResource(R.string.my_classes_room, room.name), emphasized = true)
                    if (room.id != null) {
                        AppListSecondary(stringResource(R.string.room_schedule))
                    }
                }
                AppListDivider()
            }
        }
        if (item.teachers.isNotEmpty()) {
            item(key = "teachers-h") {
                SectionHeader(
                    if (item.teachers.size == 1) {
                        stringResource(R.string.my_classes_teacher)
                    } else {
                        stringResource(R.string.my_classes_teachers)
                    },
                )
            }
            items(item.teachers, key = { "t-${it.id}" }) { member ->
                MemberRow(member, signedInId, onOpenPerson, onLongPressPerson)
                AppListDivider()
            }
        }
        item(key = "students-h") {
            SectionHeader(
                if (item.loaded) {
                    stringResource(R.string.my_classes_students_count, item.students.size)
                } else {
                    stringResource(R.string.my_classes_students)
                },
            )
        }
        if (!item.loaded) {
            item(key = "students-loading") {
                AppListRow {
                    AppListSecondary(stringResource(R.string.my_classes_loading))
                }
            }
        } else if (item.students.isEmpty()) {
            item(key = "students-empty") {
                AppListRow {
                    AppListSecondary(stringResource(R.string.my_classes_no_students))
                }
            }
        } else {
            items(item.students, key = { "s-${it.id}" }) { member ->
                MemberRow(member, signedInId, onOpenPerson, onLongPressPerson)
                AppListDivider()
            }
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun MemberRow(
    member: ClassMember,
    signedInId: String?,
    onOpenPerson: (DirectoryEntity) -> Unit,
    onLongPressPerson: (DirectoryEntity) -> Unit,
) {
    val isSelf = signedInId != null && member.id.equals(signedInId, ignoreCase = true)
    AppListRow(
        onClick = if (member.canOpenProfile) {
            { onOpenPerson(member.entity) }
        } else {
            null
        },
        onLongClick = if (member.canOpenProfile &&
            (member.kind == DirectoryEntityKind.STUDENT || member.kind == DirectoryEntityKind.TEACHER)
        ) {
            { onLongPressPerson(member.entity) }
        } else {
            null
        },
        leading = { PersonAvatar(entity = member.entity) },
        trailing = {
            if (member.level.badge.isNotEmpty()) {
                LevelBadge(member.level, compact = true)
            }
        },
    ) {
        AppListPrimary(member.name, emphasized = true)
        when {
            isSelf -> AppListSecondary(stringResource(R.string.my_classes_you))
            member.kind == DirectoryEntityKind.TEACHER ->
                AppListSecondary(stringResource(R.string.my_classes_teacher))
        }
    }
}

@Composable
private fun SubjectGlyph(subject: String, useSubjectColors: Boolean) {
    val color = if (useSubjectColors) {
        Color(SubjectColorResolver.hueToArgb(SubjectMapper.colorHue(subject)))
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    Box(
        Modifier
            .size(36.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(color.copy(alpha = 0.16f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            subjectIcon(subject),
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun LevelBadge(level: ClassLevel, compact: Boolean = false) {
    val label = level.badge
    if (label.isEmpty()) return
    val color = levelColor(level)
    Surface(
        shape = RoundedCornerShape(if (compact) 8.dp else 10.dp),
        color = color.copy(alpha = 0.16f),
    ) {
        Box(
            Modifier
                .padding(horizontal = 8.dp, vertical = if (compact) 4.dp else 8.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                label,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold,
                color = color,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun Chip(text: String, color: Color = MaterialTheme.colorScheme.primary) {
    Surface(
        shape = RoundedCornerShape(999.dp),
        color = color.copy(alpha = 0.14f),
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelLarge,
            fontWeight = FontWeight.SemiBold,
            color = color,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
        )
    }
}

@Composable
private fun classSubtitle(item: MyClass): String? {
    val bits = buildList {
        item.teacherNames.takeIf { it.isNotBlank() }?.let { add(it) }
        item.room?.name?.takeIf { it.isNotBlank() }?.let { add(it) }
    }
    return bits.joinToString(" · ").ifBlank { null }
}

@Composable
private fun listMeta(item: MyClass, next: ClassNextLesson?): String? {
    if (next != null) return nextLessonListLabel(next)
    val bits = buildList {
        item.year?.let { add(stringResource(R.string.my_classes_year, it)) }
        item.block?.let { add(stringResource(R.string.my_classes_block, it)) }
        if (item.loaded) add(stringResource(R.string.my_classes_students_count, item.students.size))
    }
    return bits.joinToString(" · ").ifBlank { null }
}

@Composable
private fun nextLessonListLabel(item: ClassNextLesson): String {
    val time = "%02d:%02d".format(item.start.hour, item.start.minute)
    val today = W4Dates.today()
    val day = item.start.toLocalDate()
    return if (day == today) {
        stringResource(R.string.my_classes_next_today, time)
    } else {
        val weekday = day.dayOfWeek
            .getDisplayName(TextStyle.SHORT, Locale.getDefault())
            .trimEnd('.')
        stringResource(R.string.my_classes_next_weekday, weekday, time)
    }
}

@Composable
private fun nextLessonDetailLabel(item: ClassNextLesson): String {
    val dayTime = nextLessonListLabel(item)
    val room = item.room
    return if (room.isNullOrBlank()) {
        dayTime
    } else {
        stringResource(R.string.my_classes_next_with_room, dayTime, room)
    }
}

private fun levelColor(level: ClassLevel): Color = when (level) {
    ClassLevel.HIGHER -> Color(0xFF6B3FA0)
    ClassLevel.STANDARD -> Color(0xFF0F7A63)
    ClassLevel.COMBINED -> Color(0xFFB15C00)
    ClassLevel.NONE, ClassLevel.UNKNOWN -> Color(0xFF5F6368)
}
