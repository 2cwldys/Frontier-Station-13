/*#############################################
	Constants for the persistence subsystem
#############################################*/

#define PERSISTENT_EXPIRATION_CLEANUP_DELAY_DAYS 30 // Grace period for expired database entries before they get cleaned up.
/// How long faction chat history is kept by factionChatPrune() (persistence_factions.dm).
#define FACTION_CHAT_RETENTION_DAYS 30

// Faction-tagger-configurable turret targeting restriction -- see
// code/game/objects/structures/machinery/portable_turret.dm (assess_living())
// and code/game/objects/items/devices/faction_tagger.dm (ui_act "set_turret_mode").
#define TURRET_FACTION_MODE_OFF "off"
#define TURRET_FACTION_MODE_NONFACTION "nonfaction"
#define TURRET_FACTION_MODE_WILDLIFE "wildlife"
#define TURRET_FACTION_MODE_BOTH "both"

// What a pinned away site is FOR (ss13_persistent_away_sites.site_kind).
//
// SIMULATED is the neutral baseline and the column's default: an away site that
// was generated or pinned without anybody declaring a purpose for it, which is
// every RNG-generated site, every "Pin Site I'm At", and the site a faction
// beacon pins underneath itself. COLONY and DRYDOCK are only ever set
// deliberately, by the colony radio's founding request
// (code/game/objects/items/devices/colony_radio.dm).
//
// Only DRYDOCK carries mechanics: ships may be stashed, retrieved and
// commissioned within one overmap tile of one. See _drydock_site_nearby()
// (persistence_shuttles.dm). The other two are descriptive.
#define AWAY_SITE_KIND_SIMULATED "simulated"
#define AWAY_SITE_KIND_COLONY    "colony"
#define AWAY_SITE_KIND_DRYDOCK   "drydock"

// Who may stash/retrieve/commission a ship at a drydock. Set on a faction or
// hub beacon (faction_beacon.dm), or on a drydock control console where no
// beacon reaches -- see drydock_policy_for_z() (persistence_shuttles.dm) for
// which of the two wins. Anything unset resolves to ..._ALL at read time
// rather than being migrated, so an unconfigured drydock is a public yard.
#define DRYDOCK_POLICY_ALL     "all"
#define DRYDOCK_POLICY_FACTION "faction"
#define DRYDOCK_POLICY_ALLIED  "allied"
#define DRYDOCK_POLICY_NONE    "none"

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
