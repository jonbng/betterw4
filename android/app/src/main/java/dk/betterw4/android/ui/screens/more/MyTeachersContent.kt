package dk.betterw4.android.ui.screens.more

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dk.betterw4.android.R
import dk.betterw4.android.feature.classes.ClassLevel
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.teachers.MyTeacher
import dk.betterw4.android.ui.components.AppListDivider
import dk.betterw4.android.ui.components.AppListPrimary
import dk.betterw4.android.ui.components.AppListRow
import dk.betterw4.android.ui.components.AppListSecondary
import dk.betterw4.android.ui.components.EmptyBox
import dk.betterw4.android.ui.components.LoadingBox
import dk.betterw4.android.ui.components.PersonAvatar

@Composable
fun MyTeachersContent(
    padding: PaddingValues,
    listState: LazyListState,
    loading: Boolean,
    teachers: List<MyTeacher>,
    onOpenTeacher: (MyTeacher) -> Unit,
    onLongPressTeacher: (DirectoryEntity) -> Unit,
) {
    when {
        loading && teachers.isEmpty() -> LoadingBox(Modifier.padding(padding))
        teachers.isEmpty() -> EmptyBox(
            text = stringResource(R.string.my_teachers_empty),
            description = stringResource(R.string.my_teachers_empty_hint),
            icon = Icons.Default.Groups,
            modifier = Modifier.padding(padding),
        )
        else -> LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            items(teachers, key = { it.id }) { teacher ->
                AppListRow(
                    onClick = { onOpenTeacher(teacher) },
                    onLongClick = { onLongPressTeacher(teacher.entity) },
                    leading = { PersonAvatar(entity = teacher.entity) },
                    trailing = {
                        if (teacher.displayLevel.isNotEmpty()) {
                            LevelBadge(teacher.level)
                        }
                    },
                ) {
                    AppListPrimary(teacher.name, emphasized = true)
                    teacher.role?.takeIf { it.isNotBlank() }?.let { AppListSecondary(it, maxLines = 2) }
                }
                AppListDivider()
            }
        }
    }
}

@Composable
private fun LevelBadge(level: ClassLevel) {
    val label = level.badge
    if (label.isEmpty()) return
    val color = levelColor(level)
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = color.copy(alpha = 0.16f),
    ) {
        Box(
            Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
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

private fun levelColor(level: ClassLevel): Color = when (level) {
    ClassLevel.HIGHER -> Color(0xFF6B3FA0)
    ClassLevel.STANDARD -> Color(0xFF0F7A63)
    ClassLevel.COMBINED -> Color(0xFFB15C00)
    ClassLevel.NONE, ClassLevel.UNKNOWN -> Color(0xFF5F6368)
}
