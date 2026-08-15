package dk.betterw4.android.feature.messages

import dk.betterw4.android.feature.demo.DemoData
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Mutable demo message list used by [MessageRepository].
 * Pure of Android framework so JVM unit tests drive the same mutations as production demo mode.
 */
class DemoMessageState(
    initial: List<MessageThread> = DemoData.messages,
) {
    private val threads = CopyOnWriteArrayList(initial)

    fun snapshot(): List<MessageThread> = threads.toList()

    fun unreadCount(): Int = threads.count { it.unread }

    fun listForFolder(folder: MessageFolder): List<MessageThread> =
        threads.filter {
            folder.id == MessageFolder.NEWEST.id ||
                folder.id == MessageFolder.INBOX.id ||
                it.folderId == folder.id ||
                (folder.id == MessageFolder.UNREAD.id && it.unread)
        }

    fun markRead(id: String): Boolean {
        val idx = threads.indexOfFirst { it.id == id }
        if (idx < 0) return false
        threads[idx] = threads[idx].copy(unread = false)
        return true
    }

    fun markUnread(id: String): Boolean {
        val idx = threads.indexOfFirst { it.id == id }
        if (idx < 0) return false
        threads[idx] = threads[idx].copy(unread = true)
        return true
    }

    fun delete(id: String): Boolean = threads.removeAll { it.id == id }

    fun toggleFlag(id: String): MessageThread? {
        val idx = threads.indexOfFirst { it.id == id }
        if (idx < 0) return null
        val updated = threads[idx].copy(flagged = !threads[idx].flagged)
        threads[idx] = updated
        return updated
    }

    fun find(id: String): MessageThread? = threads.find { it.id == id }

    /**
     * Thread detail for demo: HTML body from [DemoData], thread header from live list
     * so flag/unread mutations survive reopen.
     */
    fun loadDetail(threadId: String): MessageThreadDetail {
        val live = find(threadId)
            ?: DemoData.messages.find { it.id == threadId }
            ?: MessageThread(
                id = threadId,
                topic = "Ukendt",
                sender = "",
                dateChanged = null,
                folderId = MessageFolder.INBOX.id,
            )
        val base = DemoData.messageDetail(threadId)
        return base.copy(thread = live)
    }

    fun reset(initial: List<MessageThread> = DemoData.messages) {
        threads.clear()
        threads.addAll(initial)
    }
}
