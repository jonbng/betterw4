package dk.betterlectio.android.ui.screens.schedule

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Brush
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.Functions
import androidx.compose.material.icons.filled.HistoryEdu
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Science
import androidx.compose.material.icons.filled.ShowChart
import androidx.compose.material.icons.filled.SportsSoccer
import androidx.compose.material.icons.filled.TheaterComedy
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Description
import androidx.compose.ui.graphics.vector.ImageVector
import dk.betterlectio.android.feature.settings.SubjectIcons

fun subjectIcon(title: String): ImageVector {
    return when (SubjectIcons.iconKeyFor(title)) {
        "functions" -> Icons.Default.Functions
        "book" -> Icons.AutoMirrored.Filled.MenuBook
        "translate" -> Icons.Default.Translate
        "science" -> Icons.Default.Science
        "history" -> Icons.Default.HistoryEdu
        "sport" -> Icons.Default.SportsSoccer
        "music" -> Icons.Default.MusicNote
        "brush" -> Icons.Default.Brush
        "computer" -> Icons.Default.Computer
        "globe" -> Icons.Default.Public
        "chart" -> Icons.Default.ShowChart
        "chat" -> Icons.Default.Chat
        "building" -> Icons.Default.AccountBalance
        "people" -> Icons.Default.People
        "film" -> Icons.Default.Movie
        "theater" -> Icons.Default.TheaterComedy
        "bulb" -> Icons.Default.Lightbulb
        "link" -> Icons.Default.Link
        "sparkles" -> Icons.Default.AutoAwesome
        "doc" -> Icons.Default.Description
        else -> Icons.Default.School
    }
}
