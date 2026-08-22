package dk.betterw4.android.ui.navigation

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.EventBusy
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.People
import androidx.compose.ui.graphics.vector.ImageVector
import dk.betterw4.android.R

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
    Students(
        route = "students",
        labelRes = R.string.tab_students,
        selectedIcon = Icons.Filled.People,
        unselectedIcon = Icons.Outlined.People,
    ),
    Absence(
        route = "absence",
        labelRes = R.string.tab_absence,
        selectedIcon = Icons.Filled.EventBusy,
        unselectedIcon = Icons.Outlined.EventBusy,
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
