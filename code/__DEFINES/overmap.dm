#define SHIP_SIZE_TINY	1
#define SHIP_SIZE_SMALL	2
#define SHIP_SIZE_LARGE	3

//multipliers for max_speed to find 'slow' and 'fast' speeds for the ship
#define SHIP_SPEED_SLOW  1/(40 SECONDS)
#define SHIP_SPEED_FAST  3/(20 SECONDS)// 15 speed

#define OVERMAP_WEAKNESS_NONE 0
#define OVERMAP_WEAKNESS_FIRE 1
#define OVERMAP_WEAKNESS_EMP 2
#define OVERMAP_WEAKNESS_MINING 4
#define OVERMAP_WEAKNESS_EXPLOSIVE 8

#define SENSOR_COEFFICENT 1000

#define waypoint_sector(waypoint) GLOB.map_sectors["[waypoint.z]"]

/// Standard small-craft build/dock envelope (tiles) -- the max footprint a
/// commissioned player-built sub-ship can be built within (ship_commissioning
/// console), and the size a docking landmark can restrict itself to via
/// max_footprint_x/max_footprint_y (shuttle_landmark/player_dock,
/// docking_beacon.dm) so oversized ships never see it as a valid destination.
/// One shared standard, not per-slot arbitrary sizes, so any compliant
/// sub-ship can dock at any compliant slot -- a station cycler beacon or an
/// open hangar berth aboard another ship alike.
/// Matches Persistent-Bay's own max sub-ship size (9x9).
#define SUBSHIP_FOOTPRINT_X 9
#define SUBSHIP_FOOTPRINT_Y 9

/// Credits charged by drydockCommission() (persistence_shuttles.dm) to turn
/// a player-built hull into a real, independently-owned shuttle -- flat fee
/// regardless of what was actually built, same spirit as drydockScuttle()'s
/// flat fee.
#define SHIP_COMMISSION_PRICE 100000

/// Max tiles a ship_commissioning console will look for a linked, active
/// docking_beacon before refusing to preview/commission -- a same-Z, real-
/// space proximity check (unrelated to any overmap-scale range).
#define BUILD_ENVELOPE_BEACON_RANGE 12

/// Minimum /obj/structure/shuttle/engine/propulsion instances
/// drydockCommission() requires anywhere in the build envelope -- no
/// particular placement required, just physically present somewhere in the
/// hull. See propulsion_engine_crate (engineering.dm).
#define SHIP_COMMISSION_MIN_PROPULSION 4
