package dk.betterlectio.android.feature.offline

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.RoomDatabase

@Entity(tableName = "directory_entities")
data class DirectoryEntityRow(
    @PrimaryKey val compositeKey: String, // studentId|entityId
    val studentId: String,
    val entityId: String,
    val name: String,
    val kind: String,
    val subtitle: String?,
    val avatarUrl: String?,
    val updatedAt: Long,
)

@Entity(tableName = "message_threads")
data class MessageThreadRow(
    @PrimaryKey val compositeKey: String, // studentId|folderId|threadId
    val studentId: String,
    val folderId: String,
    val threadId: String,
    val topic: String,
    val sender: String,
    val dateChangedEpoch: Long?,
    val unread: Boolean,
    val flagged: Boolean,
    val updatedAt: Long,
)

@Dao
interface DirectoryOfflineDao {
    @Query("SELECT * FROM directory_entities WHERE studentId = :studentId ORDER BY name ASC")
    suspend fun loadAll(studentId: String): List<DirectoryEntityRow>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(rows: List<DirectoryEntityRow>)

    @Query("DELETE FROM directory_entities WHERE studentId = :studentId")
    suspend fun clearStudent(studentId: String)

    @Query("DELETE FROM directory_entities")
    suspend fun clearAll()
}

@Dao
interface MessageOfflineDao {
    @Query(
        "SELECT * FROM message_threads WHERE studentId = :studentId AND folderId = :folderId ORDER BY dateChangedEpoch DESC",
    )
    suspend fun loadFolder(studentId: String, folderId: String): List<MessageThreadRow>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(rows: List<MessageThreadRow>)

    @Query("DELETE FROM message_threads WHERE studentId = :studentId AND folderId = :folderId")
    suspend fun clearFolder(studentId: String, folderId: String)

    @Query("DELETE FROM message_threads")
    suspend fun clearAll()
}

@Database(
    entities = [DirectoryEntityRow::class, MessageThreadRow::class],
    version = 1,
    exportSchema = false,
)
abstract class OfflineDatabase : RoomDatabase() {
    abstract fun directoryDao(): DirectoryOfflineDao
    abstract fun messageDao(): MessageOfflineDao

    /** Wipe offline message + directory rows (logout / session expiry). */
    suspend fun wipeOfflineData() {
        directoryDao().clearAll()
        messageDao().clearAll()
    }
}
