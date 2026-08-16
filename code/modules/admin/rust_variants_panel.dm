/*
 * Live admin toggle for "rusted/derelict" cosmetics in this codebase.
 * Covers two unrelated mechanisms under one flag/button:
 *
 * 1. A hard-coded dedicated subtype -- rusty walls (MATERIAL_RUST) -- bakes
 *    its rusty look in at Initialize(). Rare: only used by a handful of
 *    away-site/exoplanet-ruin maps. Tracked in rust_variant_walls
 *    (wall_types.dm). Dedicated rust floor tiles and old/rusty grates also
 *    exist in code (flooring_premade_.dm/lattice.dm) but were never actually
 *    placed on any map, so they're deliberately not tracked/toggled here.
 * 2. The REAL, pervasive weathering effect: nearly every ordinary steel or
 *    plasteel wall in the game (station included) draws its icon from a
 *    per-material wall_icon_variants pool, picked deterministically per-turf
 *    from an x/y/z hash (pick_wall_icon_variant(), wall_icon.dm) -- most
 *    "this wall looks rusty" sightings, including at away sites, are this,
 *    not (1). Tracked in rust_variant_weathered_walls, populated by
 *    /turf/simulated/wall/update_material() (wall_icon.dm) and the two
 *    unsimulated wall/steel + wall/darkshuttlewall Initialize()s
 *    (unsimulated/walls.dm).
 *
 * Toggling forces every tracked instance to its clean look (or, for the
 * weathered pool, restores each turf's own natural per-tile hash pick)
 * live, in either direction, without touching untracked/normally-clean
 * areas.
 */

/// Every currently-loaded dedicated rusty wall instance, populated by its
/// own Initialize() and pruned in Destroy() -- see wall_types.dm.
GLOBAL_LIST_EMPTY(rust_variant_walls)
/// Every currently-loaded wall turf (any type -- see
/// /turf/proc/get_rust_weathering_variants() overrides in wall_icon.dm and
/// unsimulated/walls.dm) drawing from a real weathered-icon pool -- the
/// actual, pervasive "some walls look worn/rusty" mechanism used almost
/// everywhere in the game (ordinary steel/plasteel walls, station included),
/// completely separate from the rare dedicated MATERIAL_RUST subtype
/// rust_variant_walls above tracks. Populated in update_material()
/// (wall_icon.dm) and the two unsimulated Initialize()s, pruned in Destroy().
GLOBAL_LIST_EMPTY(rust_variant_weathered_walls)
/// The single live-readable flag driving all three -- TRUE (default)
/// matches today's as-mapped behavior (every rusty instance shows rusty).
GLOBAL_VAR_INIT(rust_variants_enabled, TRUE)

/client/proc/rust_variants_panel()
	set name = "Rust Variants Panel"
	set category = "Admin"
	if(!check_rights(R_ADMIN))
		return

	var/static/datum/tgui_module/admin/rust_variants/global_rust_variants_panel = new()
	global_rust_variants_panel.ui_interact(usr)
	feedback_add_details("admin_verb", "RVP")

/datum/tgui_module/admin/rust_variants

/datum/tgui_module/admin/rust_variants/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "RustVariantsPanel", "Rust Variants Panel", 420, 260)
		ui.open()

/datum/tgui_module/admin/rust_variants/ui_data(mob/user)
	var/list/data = list()
	data["enabled"] = GLOB.rust_variants_enabled
	data["wall_count"] = length(GLOB.rust_variant_walls)
	data["weathered_wall_count"] = length(GLOB.rust_variant_weathered_walls)
	return data

/datum/tgui_module/admin/rust_variants/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	if(!check_rights(R_ADMIN))
		log_and_message_admins("attempted to use the Rust Variants Panel without sufficient rights.")
		return

	if(action == "toggle")
		GLOB.rust_variants_enabled = !GLOB.rust_variants_enabled
		_apply_rust_state(usr)
		. = TRUE

/datum/tgui_module/admin/rust_variants/proc/_apply_rust_state(mob/user)
	PRIVATE_PROC(TRUE)

	for(var/turf/simulated/wall/rusty/W as anything in GLOB.rust_variant_walls)
		W.set_material(SSmaterials.get_material_by_name(GLOB.rust_variants_enabled ? MATERIAL_RUST : DEFAULT_WALL_MATERIAL))
	for(var/turf/T as anything in GLOB.rust_variant_weathered_walls)
		var/list/variants = T.get_rust_weathering_variants()
		if(!length(variants))
			continue // stale entry -- e.g. a dedicated /rusty wall that passed through the steel material mid-toggle; harmless, just skip
		T.icon = GLOB.rust_variants_enabled ? pick_wall_icon_variant(T.x, T.y, T.z, variants) : variants[length(variants)]
		if(istype(T, /turf/simulated/wall))
			var/turf/simulated/wall/SW = T
			SW.update_icon()

	log_and_message_admins("[GLOB.rust_variants_enabled ? "enabled" : "disabled"] rust variants ([length(GLOB.rust_variant_walls)] dedicated wall\s, [length(GLOB.rust_variant_weathered_walls)] weathered wall\s).")
