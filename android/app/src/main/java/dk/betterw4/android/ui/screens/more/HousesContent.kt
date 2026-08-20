package dk.betterw4.android.ui.screens.more

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import dk.betterw4.android.R
import dk.betterw4.android.feature.directory.DirectoryEntity
import dk.betterw4.android.feature.directory.DirectoryEntityKind
import dk.betterw4.android.feature.directory.House
import dk.betterw4.android.feature.directory.HouseResident
import dk.betterw4.android.feature.directory.flagKind
import dk.betterw4.android.ui.components.AppListDivider
import dk.betterw4.android.ui.components.AppListPrimary
import dk.betterw4.android.ui.components.AppListRow
import dk.betterw4.android.ui.components.AppListSecondary
import dk.betterw4.android.ui.components.EmptyBox
import dk.betterw4.android.ui.components.HouseFlag
import dk.betterw4.android.ui.components.LoadingBox
import dk.betterw4.android.ui.components.PersonAvatar
import dk.betterw4.android.ui.components.SectionHeader

@Composable
fun HousesContent(
    padding: PaddingValues,
    listState: LazyListState,
    loading: Boolean,
    houses: List<House>,
    selectedHouse: House?,
    onOpenHouse: (House) -> Unit,
    onOpenResident: (DirectoryEntity) -> Unit,
    onLongPressResident: (DirectoryEntity) -> Unit,
) {
    when {
        selectedHouse != null -> HouseDetailContent(
            padding = padding,
            listState = listState,
            house = selectedHouse,
            onOpenResident = onOpenResident,
            onLongPressResident = onLongPressResident,
        )
        loading && houses.isEmpty() -> LoadingBox(Modifier.padding(padding))
        houses.isEmpty() -> EmptyBox(
            text = stringResource(R.string.houses_empty),
            description = stringResource(R.string.houses_empty_hint),
            icon = Icons.Default.Home,
            modifier = Modifier.padding(padding),
        )
        else -> LazyColumn(
            state = listState,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            items(houses, key = { it.id }) { house ->
                AppListRow(
                    onClick = { onOpenHouse(house) },
                    leading = {
                        house.flagKind()?.let { HouseFlag(kind = it, width = 36.dp) }
                    },
                ) {
                    AppListPrimary(house.name, emphasized = true)
                    AppListSecondary(houseSubtitle(house))
                }
                AppListDivider()
            }
        }
    }
}

@Composable
private fun HouseDetailContent(
    padding: PaddingValues,
    listState: LazyListState,
    house: House,
    onOpenResident: (DirectoryEntity) -> Unit,
    onLongPressResident: (DirectoryEntity) -> Unit,
) {
    if (!house.loaded && house.rooms.isEmpty() && house.leaders.isEmpty()) {
        LoadingBox(Modifier.padding(padding))
        return
    }
    val empty = house.loaded &&
        house.leaders.isEmpty() &&
        house.rooms.isEmpty() &&
        house.unassigned.isEmpty()
    LazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
    ) {
        house.flagKind()?.let { kind ->
            item(key = "flag-${house.id}") {
                Row(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    HouseFlag(kind = kind, width = 44.dp)
                    Spacer(Modifier.width(12.dp))
                    AppListPrimary(house.name, emphasized = true)
                }
            }
        }
        if (house.leaders.isNotEmpty()) {
            item { SectionHeader(stringResource(R.string.houses_leader)) }
            items(house.leaders, key = { "lead-${it.id}" }) { resident ->
                ResidentRow(resident, onOpenResident, onLongPressResident)
                AppListDivider()
            }
        }
        house.rooms.forEach { room ->
            item(key = "room-h-${room.id}") { SectionHeader(room.name) }
            if (room.residents.isEmpty()) {
                item(key = "room-empty-${room.id}") {
                    AppListRow {
                        AppListSecondary(stringResource(R.string.houses_room_empty))
                    }
                    AppListDivider()
                }
            } else {
                items(room.residents, key = { "${room.id}-${it.id}" }) { resident ->
                    ResidentRow(resident, onOpenResident, onLongPressResident)
                    AppListDivider()
                }
            }
        }
        if (house.unassigned.isNotEmpty()) {
            item { SectionHeader(stringResource(R.string.houses_no_room)) }
            items(house.unassigned, key = { "none-${it.id}" }) { resident ->
                ResidentRow(resident, onOpenResident, onLongPressResident)
                AppListDivider()
            }
        }
        if (empty) {
            item {
                EmptyBox(
                    text = stringResource(R.string.houses_house_empty),
                    icon = Icons.Default.Home,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(240.dp),
                )
            }
        }
    }
}

@Composable
private fun ResidentRow(
    resident: HouseResident,
    onOpenResident: (DirectoryEntity) -> Unit,
    onLongPressResident: (DirectoryEntity) -> Unit,
) {
    AppListRow(
        onClick = { onOpenResident(resident.entity) },
        onLongClick = {
            if (resident.entity.kind == DirectoryEntityKind.STUDENT ||
                resident.entity.kind == DirectoryEntityKind.TEACHER
            ) {
                onLongPressResident(resident.entity)
            }
        },
        leading = { PersonAvatar(entity = resident.entity) },
    ) {
        AppListPrimary(resident.entity.name, emphasized = true)
        resident.detailLine?.let { AppListSecondary(it, maxLines = 2) }
    }
}

@Composable
private fun houseSubtitle(house: House): String {
    if (!house.loaded) return stringResource(R.string.houses_loading_rooms)
    val rooms = house.roomCount
    val people = house.studentCount
    return when {
        rooms == 0 && people == 0 && house.leaders.isNotEmpty() ->
            stringResource(R.string.houses_leader_only)
        rooms == 0 && people == 0 -> stringResource(R.string.houses_no_rooms)
        rooms == 0 -> stringResource(R.string.houses_students_count, people)
        else -> stringResource(R.string.houses_rooms_students, rooms, people)
    }
}
