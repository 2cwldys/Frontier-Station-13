/*
	This file must be one of the first files included right after the linters to lint it
	This is because the compile options must be defined in every other file, including /world that are included
*/


#define BACKGROUND_ENABLED 0    // The default value for all uses of set background. Set background can cause gradual lag and is recommended you only turn this on if necessary.
								// 1 will enable set background. 0 will disable set background.

// If defined, the sunlight system is enabled. Caution: this uses a LOT of memory.
//#define ENABLE_SUNLIGHT

// If defined, the Missions Board's "kill" mission type is offered/active again.
// Disabled by default -- missions currently only offer "fetch" and "visit".
//#define ENABLE_KILL_MISSIONS

// If defined, faction-affiliated hostile NPCs (commander's beacon/faction
// barracks soldiers) show an extra examine line marking them as cloned
// combat drones. Off by default.
#define FACTION_AI_CLONE_SOLDIERS

// If defined, admins (R_ADMIN) examining a hostile NPC see a live "[NPC AI]"
// state dump (stance, order, scheduling, move loop, commanding beacon).
// Defined by default -- comment out to strip it entirely from the build.
//#define NPC_AI_DEBUG_EXAMINE

// If defined, the airlock cycler controller's console shows a "Diagnostics"
// section (live cycle state/target, chamber/external/internal pressure,
// pump status, and every linked tag or "not linked"). Meant for build-time
// troubleshooting -- comment out to strip it from live/production builds so
// players don't see internal tag/ref debug info in a normal console.
//#define AIRLOCK_CYCLER_DIAGNOSTICS

// If defined, a shuttle console that finds no valid landing sites also
// reports WHY each nearby destination was refused -- in chat when Choose
// Destination comes up empty, and as a section on the console itself. The
// text names raw turf types and coordinates, so comment this out for a
// live/production build; defined by default while docking geometry is still
// being actively tested.
//#define DOCKING_REFUSAL_DIAGNOSTICS

// If defined, ship engines log their own ship-registration attempt (whether
// the SSshuttle.ships scan ran, which area the engine is actually in, and
// whether check_ownership() matched) plus every backup fuel draw, and the
// commission capture logs what it captured. For chasing the "no engines
// detected" / fuel port not reaching the engine terminal problem -- comment
// out to strip it entirely.
//#define DRYDOCK_ENGINE_DIAGNOSTICS

// If defined, restoring a saved /turf/simulated/wall logs whether the row
// carried a saved material, what material the turf actually ended up with,
// and its icon var before/after the restore path's own guarantee step runs.
// For chasing a restored wall showing icon=null despite ChangeTurf()'s own
// Initialize() supposedly assigning a default material -- comment out to
// strip it entirely. Defined by default while this is still being actively
// chased.
#define WALL_RESTORE_DIAGNOSTICS

// If defined, wall-mounted machine save/restore logs each machine's
// type/position/dir/pixel offset at save time and at worldstate restore
// time -- so a mismatch can be diagnosed by comparing what was saved
// against what came back. Offsets are now persisted verbatim rather than
// re-derived from dir, so a healthy boot should show the saved and restored
// values matching exactly. Defined by default while wall-mount positioning
// is still being actively chased.
#define WALL_MACHINE_DIAGNOSTICS

// If defined, fastening a pipe fitting logs its pipe_type/dir/pipe_dir
// before construction (construction.dm), and explicitly logs when no case
// in the build switch matched -- so a fitting that vanishes without
// building anything leaves a trace of exactly which pipe_type value was
// responsible. Defined by default while this is actively being chased.
#define PIPE_CONSTRUCTION_DIAGNOSTICS

// If defined, the floor-item persistence path logs every decision it makes
// for a faction-tagged clothing item: which branch dropped it (if any),
// whether its extra state blob was built, and which restore branch ran on
// the next boot. Purely diagnostic -- comment out to strip it entirely.
//#define PERSISTENCE_FLOOR_ITEM_DEBUG

// If defined, real (non-Hub) factions are limited to ONE cargo order
// category, chosen at founding and changeable later (command rank, 1-month
// real-world cooldown, or admin override anytime). Off -- every
// faction console orders from every category, same as today.
#define FACTION_CARGO_SPECIALIZATION

// Sentinel value for allowed_cargo_category meaning "no restriction" --
// admin-only ("Manage Faction Account" -> "Set Cargo Category"), for
// granting a real faction the same unrestricted ordering Hub already gets
// hardcoded by uid, without actually making it Hub.
#define FACTION_CARGO_CATEGORY_ALL "*all*"

// If defined, world.visibility is toggled off then back on ~10 seconds after
// the persistence world-ready gate finishes (persistence_world_ready.dm) --
// works around BYOND's hub-announce apparently needing an explicit runtime
// change to world.visibility rather than firing off its already-TRUE default
// at boot. Defined by default -- comment out to disable the workaround.
#define REPUBLISH_HUB_VISIBILITY_ON_BOOT

// If defined, show_revision_info() (getrev.dm) actually displays anything --
// server revision/branch/date, GitHub commit link, current map, and any
// test-merged PRs. Covers both the "Show Server Revision" OOC verb and the
// automatic display that fires once per client session right after a
// character wakes from cryo (new_player.dm). Defined by default -- comment
// out to strip revision/build info from what players can see entirely.
#define SHOW_GIT_LOG

// If defined, a connecting player who has certifiably spawned a character
// at least once before hears WELCOME_BACK instead of
// WELCOME_TO_FRONTIER_STATION when they reach the lobby (ss13_characters'
// first_spawned_at column, via a new SQL COUNT query -- requires
// GLOB.config.sql_saves). Off -- every connecting player always hears
// WELCOME_TO_FRONTIER_STATION regardless of history, no DB query at all.
//#define WELCOME_BACK_VOICE_LINES

// If defined, the server automatically triggers a deployment sync
// (scripts/deploy.sh / deploy.ps1, same as the "Sync Deployment Branch"
// admin verb) the moment SSgithub detects a pull request merge into the
// configured deployment branch (GLOB.config.github_branch) -- no admin
// action needed. Requires GITHUB_ENABLED, GITHUBURL, and GITHUB_BRANCH all
// configured in config.txt (see docs/deployment.md). Off by default --
// leave undefined to require the admin verb to be run manually instead.
//#define FORCE_COMPILE_ON_MERGE

// ##### Local game-server shards (containerized, admin/auto-spawned) #####
// DO NOT ENABLE THIS UNLESS YOU KNOW WHAT YOU'RE DOING.
//
// If defined, this server can create and manage OTHER local DreamDaemon
// instances ("shards") on the same machine -- each a fresh-local-data
// Docker container sharing this server's own central database (see
// docs/cross_server_persistence.md), triggered by an admin TGUI panel
// (default) or, optionally, automatically once population crosses a
// configured threshold. This works by letting the game process shell out
// to Docker (world.shelleo(), same Trusted-security-level gate every other
// shelleo() call site in this codebase already requires) -- that's real
// blast radius beyond anything else compile-gated in this file, which is
// why this is a compile-time barrier rather than just a config.txt toggle
// like everything else in the cross-server system. Off by default; a
// normal build never compiles any of this in, not even as dead code behind
// a runtime check.
//#define ALLOW_CENTRAL_SHARD_SPAWNING

// If defined, every log_admin() entry is also mirrored to Discord via a new
// "admin_log" webhook tag (WEBHOOK_ADMIN_LOG, __DEFINES/webhook.dm) -- add a
// webhook to config/webhooks.json (or ss13_webhooks) with "admin_log" in its
// tags list to actually receive them. log_admin_private()/log_admin_circuit()/
// log_adminsay() are deliberately NOT included -- see admin.dm's own
// ADMINPRIVATE-is-stripped-from-public-logs convention. Off by default --
// leave undefined to keep admin logs server-local only.
#define EXPORT_ADMIN_LOG_TO_DISCORD

// If defined, security events are mirrored to a separate law-enforcement
// Discord channel via the "law_enforcement" webhook tag
// (WEBHOOK_LAW_ENFORCEMENT, __DEFINES/webhook.dm) -- highsec offenses and
// distress calls as they reach responders' PDAs, plus First Responder
// enforcement actions (repossession, force-stash, scuttling, schematic
// withdrawal, stolen-flag clearing). Separate from EXPORT_ADMIN_LOG_TO_DISCORD
// so a security channel can get these WITHOUT being handed the whole admin
// log; admin logging is unaffected either way. Add a webhook carrying that
// tag to config/webhooks.json (its optional "mention" field is what pings a
// role). On by default -- harmless when no such webhook is configured, since
// post_webhook_event() only delivers to webhooks that carry the tag.
#define EXPORT_LAW_ENFORCEMENT_TO_DISCORD

// If defined, the last active player character going to cryo immediately
// triggers a full persistence autosave (runLobbyEmptyAutosave(),
// persistence.dm) instead of waiting for the next periodic save. Comment
// out to disable -- lobby-empty saves then only happen on the regular
// periodic timer.
#define LOBBY_EMPTY_AUTOSAVE

// If defined, growing a clone through the resleeving pipeline
// (order_clone_from_lace(), resleever_cloning.dm) charges CLONE_ORDER_COST --
// to the faction when the cloning pod and resleever are both tagged to the
// same faction, otherwise to the ordering character's own account. Comment
// out to make cloning free: the charge, the refund-on-failure path, and the
// affordability checks are all skipped, and the resleever's UI stops showing
// a price. On by default.
#define CLONING_COSTS_CREDITS
/// Credits charged per clone while CLONING_COSTS_CREDITS is enabled. Lives
/// here rather than beside the pipeline so the machine, its UI data and the
/// billing path all read one number.
#define CLONE_ORDER_COST 10000

// If defined, the server launches the Discord status bot
// (scripts/discord_status_bot.py) on startup and kills it when the server
// actually closes -- see discordStatusBotStart()/Stop() (persistence.dm).
// Requires config/discord_status_bot.json (a bot token), Python with
// discord.py installed, AND a TGS security level of Trusted, since this is a
// raw OS shell-out that BYOND refuses under Safe/Ultrasafe. All three are
// checked at runtime; a missing one skips the launch with a logged reason
// rather than failing the round.
//
// Off by default -- it spawns an OS process that outlives the call, so opting
// in should be deliberate. Leave undefined to keep starting the bot by hand.
#define DISCORD_STATUS_BOT_AUTOSTART

// If defined, faction raiding is SUSPENDED whenever no staff are online and
// restored when one returns -- raidingUpdateForStaffPresence()
// (persistence_factions.dm), driven off the GLOB.staff transitions in
// client_procs.dm and holder2.dm. Two config.txt settings tune it:
// RAIDING_STAFF_RIGHTS (who counts -- any/mod/admin) and
// RAIDING_STAFF_MINIMUM (how many of those are needed).
//
// Suspension is deliberately LIVE-ONLY: it never writes
// ss13_faction_raiding_toggle, so staff's own setting survives an unattended
// stretch and is what gets restored. Raiding turned off on purpose therefore
// stays off when an admin logs back in, rather than being silently re-enabled.
//
// Off by default -- it changes live gameplay behaviour with no admin action,
// so opting in should be deliberate.
#define AUTO_SUSPEND_RAIDING_WHEN_UNSTAFFED

// If defined, faction-tagged equipment can only be WORN by people employed by
// that faction (can_use_faction_equipment(), persistence_factions.dm) -- gated
// in mob_can_equip() (items.dm) so every equip route is covered at once.
// Untagged and "public" gear is never affected, and carrying/storing/
// confiscating tagged gear stays unrestricted either way: only wearing is.
// Comment out to let anyone wear anything, as before this existed.
//#define FACTION_EQUIPMENT_WEAR_LOCK

// If defined, two factions can become allied via a Faction Management
// propose/accept handshake -- either side can break it anytime. Allied
// factions can access each other's station under the faction raiding gate,
// their hostile NPCs treat each other as friendly, and their tagged turrets
// don't fire on each other. Off -- no faction is ever allied
// with another.
#define FACTION_ALLIANCES

// If defined, every airlock plays a fixed custom open/close sound pair
// (sound/machines/airlock/cargobayopen.ogg and cargobayclose.ogg) instead of
// its own subtype's normal open_sound_powered/close_sound_powered -- the
// forced/unpowered open sound is unaffected. Off by default -- leave
// undefined to keep each airlock subtype's own sound flavor.
#define CUSTOM_AIRLOCK_SOUNDS

// If defined, clicking a button on a PDA/modular computer/laptop's TGUI
// plays a random one of 6 short click sounds, audible to anyone standing
// nearby (playsound()), throttled to once per 4.5 seconds per device so
// rapid clicking doesn't spam it. Off -- no click sound.
#define PADD_BUTTON_PRESS_SOUNDS

// We want to use external resources. Kthx.
#define PRELOAD_RSC 0

#ifndef PRELOAD_RSC				//set to:
	#define PRELOAD_RSC 2		//  0 to allow using external resources or on-demand behaviour;
#endif							//  1 to use the default behaviour;
								//  2 for preloading absolutely everything;


//Since we do not currently use some of the flags that TG uses, we have to perform a bit of an adaptation
#if defined(UNIT_TEST) && !defined(OPENDREAM) && !defined(SPACEMAN_DMM)
	#define CIBUILDING
	#define TESTING
#endif //UNIT_TEST


/*
	Manual runs area, uncomment the appropriate defines depending on what you want to do
*/

// !!! For manual use only, remember to recomment before PRing !!!
// #define TESTING // Creates debug feedback messages and enables many optional testing procs/checks
// #define UNIT_TEST
// #define MANUAL_UNIT_TEST

#if defined(MANUAL_UNIT_TEST) && !defined(SPACEMAN_DMM) && !defined(OPENDREAM)
	#warn Manual unit test is defined, remember to recomment it before PRing!
#endif // MANUAL_UNIT_TEST

#ifdef TESTING
	///Used to find the sources of harddels, quite laggy, don't be surpised if it freezes your client for a good while
	// #define REFERENCE_TRACKING
	#ifdef REFERENCE_TRACKING

		//Run a lookup on things hard deleting by default.
		#define GC_FAILURE_HARD_LOOKUP

		#ifdef GC_FAILURE_HARD_LOOKUP
			///Don't stop when searching, go till you're totally done
			#define FIND_REF_NO_CHECK_TICK
		#endif //GC_FAILURE_HARD_LOOKUP

	#endif //REFERENCE_TRACKING

#endif //TESTING



//Additional code for the above flags.
//A warning on compile is treated as an error in the CI, therefore unlike TG we must avoid the warn if it's running in the CI
#if defined(TESTING) && !defined(CIBUILDING) && !defined(OPENDREAM) && !defined(SPACEMAN_DMM)
	#warn compiling in TESTING mode. testing() debug messages will be visible.
#endif //TESTING

//CIBUILDING requires UNIT_TEST to be defined, if it isn't, define it here
#if defined(CIBUILDING) && !defined(UNIT_TEST)
	#define UNIT_TEST
#endif //CIBUILDING


//Enable various trackings and debugs if we're running the unit tests
#if defined(UNIT_TEST) && !defined(OPENDREAM) && !defined(SPACEMAN_DMM)

	//Hard del testing defines, if you leave a reference, it will search for it
	#define REFERENCE_TRACKING
	#define REFERENCE_TRACKING_DEBUG
	#define FIND_REF_NO_CHECK_TICK
	#define GC_FAILURE_HARD_LOOKUP

	//Ensures all early assets can actually load early
	#define DO_NOT_DEFER_ASSETS

	//Test at full capacity, the extra cost doesn't matter
	#define TIMER_DEBUG

	//If you really are lost with atmos issues
	// #define ZASDBG

	#define SQL_PREF_DEBUG
#endif //UNIT_TEST

#ifdef TGS
	// TGS performs its own build of dm.exe, but includes a prepended TGS define.
	#define CBT
#endif //TGS


//Poor man's code to try to catch people that are running the codebase without compiling tgui, aka in an unsupported way
//Basically, this tells you to use a supported compilation as defined in the repo's README
#if !defined(CBT) && !defined(SPACEMAN_DMM) && !defined(OPENDREAM) && !defined(CIBUILDING)
	#warn Building with Dream Maker is no longer supported and will result in errors.
	#warn In order to build, run BUILD.bat in the root directory.
	#warn Consider switching to VSCode editor instead, where you can press Ctrl+Shift+B to build.
	#error Not compiling in a supported environment! Use Visual Studio Code or BUILD.bat!
#endif
