package dk.betterlectio.android.feature.directory

import android.content.Context
import androidx.core.content.edit
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DirectoryPinRepository @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs = context.getSharedPreferences("directory_pins", Context.MODE_PRIVATE)

    val store = PinStore(
        load = {
            prefs.getStringSet("pins", emptySet())?.toSet().orEmpty()
        },
        persist = { ids ->
            prefs.edit { putStringSet("pins", ids) }
        },
    )

    fun isPinned(id: String): Boolean = store.isPinned(id)
    fun toggle(id: String): Boolean = store.toggle(id)
    fun pinnedIds(): Set<String> = store.pinnedIds()
    fun sortPinnedFirst(items: List<DirectoryEntity>): List<DirectoryEntity> =
        store.sortPinnedFirst(items) { it.id }
}
