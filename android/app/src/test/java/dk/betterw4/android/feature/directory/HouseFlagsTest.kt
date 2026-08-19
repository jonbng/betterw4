package dk.betterw4.android.feature.directory

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HouseFlagsTest {
    @Test
    fun maps_house_ids_and_names() {
        assertEquals(HouseFlagKind.DENMARK, HouseFlagKind.of("denmark"))
        assertEquals(HouseFlagKind.FINLAND, HouseFlagKind.of("Finland"))
        assertEquals(HouseFlagKind.ICELAND, HouseFlagKind.of("iceland"))
        assertEquals(HouseFlagKind.NORWAY, HouseFlagKind.of("Norway"))
        assertEquals(HouseFlagKind.SWEDEN, HouseFlagKind.of("sweden"))
        assertEquals(HouseFlagKind.GRADUATED, HouseFlagKind.of("grad"))
        assertEquals(HouseFlagKind.GRADUATED, HouseFlagKind.of("Graduated"))
        assertNull(HouseFlagKind.of("unknown"))
    }

    @Test
    fun prefixes_known_houses_with_the_flag() {
        assertEquals("🇩🇰 Denmark", houseFlagLabel("Denmark", "denmark"))
        assertEquals("🎓 Graduated", houseFlagLabel("Graduated", "grad"))
        assertEquals("Mystery", houseFlagLabel("Mystery"))
    }
}
