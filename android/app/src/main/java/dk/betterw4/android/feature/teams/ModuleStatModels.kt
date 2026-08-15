package dk.betterw4.android.feature.teams

data class ModuleStat(
    val team: String,
    val held: Int,
    val cancelled: Int,
    val changed: Int,
)
