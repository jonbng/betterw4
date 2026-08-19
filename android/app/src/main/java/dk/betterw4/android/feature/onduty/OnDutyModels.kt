package dk.betterw4.android.feature.onduty

import android.net.Uri
import java.time.LocalDate

data class OnDutyPerson(
    val id: String,
    val name: String,
    val role: String,
    val uwcId: String? = null,
    val phone: String? = null,
    val email: String? = null,
    val location: String? = null,
    val photoUrl: String? = null,
) {
    val hasContact: Boolean get() = !phone.isNullOrBlank() || !email.isNullOrBlank()
}

data class OnDutyGroup(
    val role: String,
    val people: List<OnDutyPerson>,
)

data class OnDutyPage(
    val title: String? = null,
    val date: LocalDate? = null,
    val dateLabel: String? = null,
    val groups: List<OnDutyGroup> = emptyList(),
) {
    val people: List<OnDutyPerson> get() = groups.flatMap { it.people }
    val isEmpty: Boolean get() = people.isEmpty()
}

data class OnDutyDay(
    val id: String,
    val date: LocalDate?,
    val dateLabel: String,
    val isToday: Boolean = false,
    val groups: List<OnDutyGroup> = emptyList(),
) {
    val people: List<OnDutyPerson> get() = groups.flatMap { it.people }
}

data class OnDutySchedule(
    val monthLabel: String? = null,
    val year: Int? = null,
    val month: Int? = null,
    val days: List<OnDutyDay> = emptyList(),
)

data class OnDutySnapshot(
    val today: OnDutyPage,
    val upcoming: List<OnDutyDay> = emptyList(),
)

object OnDutyContact {
    fun telephoneUri(phone: String): Uri? {
        val digits = digitsForDialing(phone) ?: return null
        return Uri.parse("tel:$digits")
    }

    fun smsUri(phone: String): Uri? {
        val digits = digitsForDialing(phone) ?: return null
        return Uri.parse("smsto:$digits")
    }

    fun mailtoUri(email: String): Uri? {
        val trimmed = email.trim()
        if (trimmed.isEmpty() || !trimmed.contains('@')) return null
        return Uri.parse("mailto:${Uri.encode(trimmed)}")
    }

    fun digitsForDialing(phone: String): String? {
        val builder = StringBuilder()
        for (ch in phone) {
            when {
                ch.isDigit() -> builder.append(ch)
                ch == '+' && builder.isEmpty() -> builder.append(ch)
            }
        }
        val digits = builder.toString()
        val digitCount = digits.count { it.isDigit() }
        return digits.takeIf { digitCount >= 5 }
    }
}
