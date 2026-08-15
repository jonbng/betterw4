package dk.betterlectio.android.feature.messages

/**
 * In-list message search (iOS `.searchable` parity).
 * Matches sender and topic case-insensitively.
 */
object MessageSearch {
    fun filter(threads: List<MessageThread>, query: String): List<MessageThread> {
        val q = query.trim()
        if (q.isEmpty()) return threads
        return threads.filter { thread ->
            thread.sender.contains(q, ignoreCase = true) ||
                thread.topic.contains(q, ignoreCase = true)
        }
    }
}
