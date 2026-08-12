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

/* Faction member ranks (ss13_faction_members.rank).
 *
 * The Faction Management program states the working scale itself when adding a
 * job: "Rank (0=crew, 1=officer, 2=command)". CIVILIAN sits below all of it.
 *
 * CIVILIAN exists because merely printing an ID from a faction console used to
 * register the printer as rank-0 CREW -- indistinguishable from someone
 * actually employed on a rank-0 job. The row still has to exist (payroll,
 * account number, clock-in all key off it), so it gets a rank that grants
 * nothing instead: -1, the same value get_faction_member() resolves to for
 * somebody with no row at all. Only a real job assignment through Faction
 * Management issues CREW or above.
 */
#define FACTION_RANK_CIVILIAN -1
#define FACTION_RANK_CREW      0
#define FACTION_RANK_OFFICER   1
#define FACTION_RANK_COMMAND   2
