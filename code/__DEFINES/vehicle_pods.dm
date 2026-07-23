// Slot keys for /obj/vehicle/pod's installed_parts dict (persistence_shuttles.dm-style
// string-keyed slots, not a fixed var per part -- see pods/pod.dm install_part()/get_part()).
#define POD_PART_ENGINE "engine"
#define POD_PART_MAIN_WEAPON "main_weapon"
#define POD_PART_SECONDARY "sec_system"
#define POD_PART_COMMS "comms"
#define POD_PART_SENSORS "sensors"
#define POD_PART_LIGHTS "lights"
#define POD_PART_LOCK "lock"

// Phase 4: warp travel + sensors tunables.
/// How far (overmap tiles) a pod can warp-jump -- deliberately well above
/// PERSONAL_TRAVEL_LEAP_RANGE (10, misc.dm) so pods can cross the whole map
/// where personal travel can't, hopping sector-to-sector. Verify against a
/// real map's sector layout before trusting this default (see the port plan).
#define POD_WARP_RANGE 25
/// Moles of phoron consumed from the warp engine's inserted tank per jump.
#define POD_JUMP_FUEL_MOLES 50
/// Cooldown between jumps.
#define POD_JUMP_COOLDOWN (20 SECONDS)
/// Charge-up delay before a jump actually executes.
#define POD_JUMP_SPOOL_TIME (3 SECONDS)
/// Default detection range for the pod sensors part -- matches
/// /obj/structure/machinery/shipsensors/weak's max_range (Aurora's own
/// existing small-craft sensor tuning).
#define POD_SENSOR_RANGE 7
