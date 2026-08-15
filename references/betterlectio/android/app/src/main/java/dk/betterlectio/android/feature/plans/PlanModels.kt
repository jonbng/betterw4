package dk.betterlectio.android.feature.plans

data class StudyPlan(
    val id: String,
    val title: String,
    val team: String,
    val detailHtml: String? = null,
)
