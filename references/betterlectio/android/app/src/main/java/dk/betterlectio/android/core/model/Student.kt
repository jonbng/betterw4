package dk.betterlectio.android.core.model

/**
 * Authenticated student identity (mirrors iOS / lectio_wrapper Student).
 * Credentials live separately in secure storage.
 */
data class Student(
    val studentId: String,
    val gymId: Int,
    val name: String? = null,
    val pictureId: String? = null,
    val classLabel: String? = null,
    val schoolName: String? = null,
    val isDemo: Boolean = false,
) {
    val id: String get() = "${studentId}_$gymId"

    companion object {
        const val DEMO_STUDENT_ID = "demo"
        const val DEMO_GYM_ID = -1

        val Demo = Student(
            studentId = DEMO_STUDENT_ID,
            gymId = DEMO_GYM_ID,
            name = "Demo Elev",
            classLabel = "3.x",
            schoolName = "Demo Gymnasium",
            isDemo = true,
        )
    }
}

data class School(
    val id: Int,
    val name: String,
    val isDemo: Boolean = false,
) {
    companion object {
        val Demo = School(id = Student.DEMO_GYM_ID, name = "Demo Gymnasium", isDemo = true)
    }
}
