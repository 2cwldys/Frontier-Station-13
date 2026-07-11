/*#############################################
	Constants for the persistence subsystem
#############################################*/

#define PERSISTENT_DEFAULT_EXPIRATION_DAYS 30 // Default expire timespan for newly created persistent objects
#define PERSISTENT_EXPIRATION_CLEANUP_DELAY_DAYS 30 // Grace period for expired database entries before they get cleaned up.

// Faction-tagger-configurable turret targeting restriction -- see
// code/game/objects/structures/machinery/portable_turret.dm (assess_living())
// and code/game/objects/items/devices/faction_tagger.dm (ui_act "set_turret_mode").
#define TURRET_FACTION_MODE_OFF "off"
#define TURRET_FACTION_MODE_NONFACTION "nonfaction"
#define TURRET_FACTION_MODE_WILDLIFE "wildlife"
#define TURRET_FACTION_MODE_BOTH "both"
