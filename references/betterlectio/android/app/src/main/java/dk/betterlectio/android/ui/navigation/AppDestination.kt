package dk.betterlectio.android.ui.navigation

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Mail
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Mail
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.ui.graphics.vector.ImageVector
import dk.betterlectio.android.R

/**
 * Primary bottom tabs — mirrors iOS AuthenticatedTabShell.
 */
enum class AppDestination(
    val route: String,
    @param:StringRes val labelRes: Int,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector,
) {
    Schedule(
        route = "schedule",
        labelRes = R.string.tab_schedule,
        selectedIcon = Icons.Filled.CalendarMonth,
        unselectedIcon = Icons.Outlined.CalendarMonth,
    ),
    Messages(
        route = "messages",
        labelRes = R.string.tab_messages,
        selectedIcon = Icons.Filled.Mail,
        unselectedIcon = Icons.Outlined.Mail,
    ),
    Homework(
        route = "homework",
        labelRes = R.string.tab_homework,
        selectedIcon = Icons.AutoMirrored.Filled.MenuBook,
        unselectedIcon = Icons.AutoMirrored.Outlined.MenuBook,
    ),
    Assignments(
        route = "assignments",
        labelRes = R.string.tab_assignments,
        selectedIcon = Icons.Filled.Description,
        unselectedIcon = Icons.Outlined.Description,
    ),
    More(
        route = "more",
        labelRes = R.string.tab_more,
        selectedIcon = Icons.Filled.MoreHoriz,
        unselectedIcon = Icons.Outlined.MoreHoriz,
    );

    companion object {
        val bottomBarItems: List<AppDestination> = entries
    }
}
