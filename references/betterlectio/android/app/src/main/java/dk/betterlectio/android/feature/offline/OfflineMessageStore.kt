package dk.betterlectio.android.feature.offline

import dk.betterlectio.android.feature.messages.MessageThread
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class OfflineMessageStore @Inject constructor(
    private val db: OfflineDatabase,
) {
    private val dao get() = db.messageDao()

    suspend fun loadFolder(studentId: String, folderId: String): List<MessageThread> =
        dao.loadFolder(studentId, folderId).map { it.toModel() }

    suspend fun saveFolder(studentId: String, folderId: String, threads: List<MessageThread>) {
        dao.clearFolder(studentId, folderId)
        val now = System.currentTimeMillis()
        dao.upsertAll(
            threads.map { t ->
                MessageThreadRow(
                    compositeKey = "$studentId|$folderId|${t.id}",
                    studentId = studentId,
                    folderId = folderId,
                    threadId = t.id,
                    topic = t.topic,
                    sender = t.sender,
                    dateChangedEpoch = t.dateChanged
                        ?.atZone(ZoneId.systemDefault())
                        ?.toInstant()
                        ?.toEpochMilli(),
                    unread = t.unread,
                    flagged = t.flagged,
                    updatedAt = now,
                )
            },
        )
    }

    private fun MessageThreadRow.toModel() = MessageThread(
        id = threadId,
        topic = topic,
        sender = sender,
        dateChanged = dateChangedEpoch?.let {
            LocalDateTime.ofInstant(Instant.ofEpochMilli(it), ZoneId.systemDefault())
        },
        folderId = folderId,
        // Always re-derive so offline round-trips match MessageParser (Flutter `_$_` parity).
        normalizedId = dk.betterlectio.android.feature.messages.MessageParser.normalizeThreadId(threadId),
        unread = unread,
        flagged = flagged,
    )
}
