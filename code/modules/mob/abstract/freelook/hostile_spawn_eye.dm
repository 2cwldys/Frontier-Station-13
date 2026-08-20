/// Floating admin eye for the hostile spawn panel's placement mode -- fly
/// anywhere, left click a tile to spawn one hostile from the configured
/// preset/faction (phasing in exactly like the panel's batch spawn does),
/// right click a tile to remove one admin-spawned hostile standing there
/// (phasing out the same way). Every mob placed this way joins the same
/// spawn_group the panel already tracks in GLOB.hostile_spawn_groups
/// (persistence_hostile_npcs.dm), so it shows up in and can be
/// bulk-dismissed from Active Groups like any other batch.
/mob/abstract/eye/hostile_spawn
	name_suffix = "Hostile Spawn Eye"

	/// Pool of preset ids to randomly pick from on each placement -- more
	/// than one entry means every left click can drop a different loadout,
	/// same as the panel's batch spawn (_pick_pool_preset()).
	var/list/preset_ids
	var/faction_uid
	var/pack_id
	var/datum/hostile_spawn_group/spawn_group
	/// Invisible parent object this eye's /datum/component/eye is attached
	/// to (persistence_hostile_npcs.dm) -- deleted in release() so it never
	/// lingers after the placement session ends.
	var/obj/effect/eye_anchor/anchor

/mob/abstract/eye/hostile_spawn/Initialize(mapload, list/preset_ids, faction_uid, pack_id, datum/hostile_spawn_group/spawn_group)
	. = ..(mapload)
	src.preset_ids = preset_ids
	src.faction_uid = faction_uid
	src.pack_id = pack_id
	src.spawn_group = spawn_group

/mob/abstract/eye/hostile_spawn/Destroy()
	spawn_group = null
	return ..()

/mob/abstract/eye/hostile_spawn/release(mob/user)
	. = ..()
	QDEL_NULL(anchor)

/mob/abstract/eye/hostile_spawn/additional_sight_flags()
	return SEE_TURFS|SEE_MOBS|SEE_OBJS

/mob/abstract/eye/hostile_spawn/apply_visual(mob/living/M)
	M.overlay_fullscreen("blueprints", /atom/movable/screen/fullscreen/blueprints/less_alpha)

/mob/abstract/eye/hostile_spawn/remove_visual(mob/living/M)
	M.clear_fullscreen("blueprints", 0)

/mob/abstract/eye/hostile_spawn/ClickOn(atom/A, params)
	params = params2list(params)
	if(!canClick())
		return
	var/turf/T = get_turf(A)
	if(!T)
		return
	if(params[LEFT_CLICK])
		place_at(T)
	else if(params[RIGHT_CLICK])
		remove_at(T)

/mob/abstract/eye/hostile_spawn/proc/place_at(turf/T)
	if(T.density)
		to_chat(owner, SPAN_WARNING("You can't place a hostile there."))
		return
	if(QDELETED(spawn_group))
		to_chat(owner, SPAN_WARNING("Your spawn group no longer exists."))
		return
	var/mob/living/carbon/human/npc/hostile/H = spawn_hostile_npc_from_preset(pick(preset_ids), T, faction_uid)
	if(!H)
		to_chat(owner, SPAN_WARNING("Failed to spawn -- the preset may have been disabled."))
		return
	if(pack_id)
		H.pack_id = pack_id
	spawn_group.add_member(H)

/mob/abstract/eye/hostile_spawn/proc/remove_at(turf/T)
	for(var/mob/living/carbon/human/npc/hostile/H in T)
		if(!find_hostile_spawn_group(H))
			continue
		_telepad_phase_arrival(T, H.dir)
		qdel(H)
		return
	to_chat(owner, SPAN_WARNING("Nothing here was spawned by the admin spawn system."))
