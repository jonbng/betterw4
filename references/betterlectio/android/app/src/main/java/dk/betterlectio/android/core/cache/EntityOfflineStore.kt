package dk.betterlectio.android.core.cache

/**
 * Simple durable key-value offline store for primary surfaces (JSON or plain text).
 * Pure logic over a map; [DiskBackend] is the persistence adapter.
 */
class EntityOfflineStore(
    private val backend: DiskBackend = InMemoryBackend(),
) {
    fun put(key: String, value: String) {
        backend.write(key, value)
    }

    fun get(key: String): String? = backend.read(key)

    fun remove(key: String) = backend.delete(key)

    fun clear() = backend.clear()

    fun contains(key: String): Boolean = backend.read(key) != null

    /** Read-after-write contract used by tests and callers. */
    fun putAndGet(key: String, value: String): String? {
        put(key, value)
        return get(key)
    }

    interface DiskBackend {
        fun write(key: String, value: String)
        fun read(key: String): String?
        fun delete(key: String)
        fun clear()
    }

    class InMemoryBackend : DiskBackend {
        private val map = linkedMapOf<String, String>()
        override fun write(key: String, value: String) {
            map[key] = value
        }
        override fun read(key: String): String? = map[key]
        override fun delete(key: String) {
            map.remove(key)
        }
        override fun clear() = map.clear()
        fun snapshot(): Map<String, String> = map.toMap()
    }
}
