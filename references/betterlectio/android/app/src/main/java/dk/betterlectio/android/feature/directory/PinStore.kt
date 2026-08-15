package dk.betterlectio.android.feature.directory

/**
 * Pure pin set for directory entities. Persistence is injected via [persist]/[load].
 * Unit-testable without Android.
 */
class PinStore(
    private val load: () -> Set<String> = { emptySet() },
    private val persist: (Set<String>) -> Unit = {},
) {
    private var pins: MutableSet<String> = load().toMutableSet()

    fun pinnedIds(): Set<String> = pins.toSet()

    fun isPinned(id: String): Boolean = id in pins

    fun toggle(id: String): Boolean {
        if (id in pins) pins.remove(id) else pins.add(id)
        persist(pins.toSet())
        return id in pins
    }

    fun pin(id: String) {
        if (pins.add(id)) persist(pins.toSet())
    }

    fun unpin(id: String) {
        if (pins.remove(id)) persist(pins.toSet())
    }

    fun replaceAll(ids: Set<String>) {
        pins = ids.toMutableSet()
        persist(pins.toSet())
    }

    /** Sort so pinned entities come first, preserving relative order within groups. */
    fun <T> sortPinnedFirst(items: List<T>, idOf: (T) -> String): List<T> {
        val pinned = items.filter { isPinned(idOf(it)) }
        val rest = items.filter { !isPinned(idOf(it)) }
        return pinned + rest
    }
}
