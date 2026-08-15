package dk.betterlectio.android.feature.teams

data class ModuleStat(
    val team: String,
    val held: Int,
    val cancelled: Int,
    val changed: Int,
)
