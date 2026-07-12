#define MAX_AREA_SIZE 300

/mob/abstract/eye/blueprints
	/// Associative list of turfs -> boolean validity that the player has selected for new area creation.
	var/list/selected_turfs = list()
	///The overlayed images of the user's selection.
	var/list/selection_images = list()
	///The last turf selected.
	var/turf/last_selected_turf
	///The image overlayed on the last selected turf
	var/image/last_selected_image

	///On what z-levels the blueprints can be used to modify or create areas.
	var/list/valid_z_levels = list()

	///Displayed to the user to allow them to see what area they're hovering over
	var/obj/effect/overlay/area_name_effect
	///The prefix of the area name effect display
	var/area_prefix

	///Displayed to the user on failed area creation
	var/list/errors = list()

/mob/abstract/eye/blueprints/Initialize(mapload, var/list/valid_zs, var/area_p)
	. = ..(mapload)
	if(valid_zs)
		valid_z_levels = valid_zs.Copy()
	area_prefix = area_p
	area_name_effect = new(src)

	area_name_effect.icon_state = "nothing"
	area_name_effect.maptext_height = 64
	area_name_effect.maptext_width = 128
	area_name_effect.layer = FLOAT_LAYER
	area_name_effect.plane = HUD_PLANE
	area_name_effect.appearance_flags = APPEARANCE_UI_IGNORE_ALPHA
	area_name_effect.screen_loc = "LEFT+1,BOTTOM+2"

	last_selected_image = image('icons/effects/blueprints.dmi', "selected")
	last_selected_image.plane = HUD_PLANE
	last_selected_image.appearance_flags = NO_CLIENT_COLOR|RESET_COLOR

/mob/abstract/eye/blueprints/Destroy()
	QDEL_NULL(area_name_effect)
	errors = null
	selected_turfs = null
	valid_z_levels = null
	last_selected_turf = null
	return ..()

/mob/abstract/eye/blueprints/release(var/mob/user)
	if(owner && owner.client && user == owner)
		owner.client.images.Cut()
	. = ..()

/// Resolves the acting mob's faction UID + rank from their ID card, via the
/// same get_faction_member() lookup used by telepad/faction-beacon gating
/// elsewhere. rank is -1 with no ID/faction/membership record.
/mob/abstract/eye/blueprints/proc/get_faction_tier(mob/user)
	var/obj/item/card/id/ID = user.GetIdCard()
	if(!ID || !ID.employer_faction)
		return list("uid" = null, "rank" = -1)
	var/uid = normalize_faction_uid(ID.employer_faction)
	var/list/member = get_faction_member(user.ckey, uid)
	return list("uid" = uid, "rank" = member ? (member["rank"] || 0) : -1)

/mob/abstract/eye/blueprints/proc/create_area()
	if(!check_rights(R_ADMIN, 0, owner))
		var/list/tier = get_faction_tier(owner)
		if(tier["rank"] < 1)
			to_chat(owner, SPAN_WARNING("You need officer access in a faction to modify blueprint areas."))
			return

	var/area_name = sanitizeSafe(tgui_input_text(owner, "New area name: ", "Area Creation", "", MAX_NAME_LEN))
	if(!area_name || !length(area_name))
		return
	if(length(area_name) > 50)
		to_chat(owner, SPAN_WARNING("That name is too long!"))
		return

	if(!check_selection_validity())
		to_chat(owner, SPAN_WARNING("Could not mark area: [english_list(errors)]!"))
		return

	var/area/A = finalize_area(area_name)
	for(var/turf/T in selected_turfs)
		T.change_area(T.loc, A)
	remove_selection() // Reset the selection for clarity.

/mob/abstract/eye/blueprints/proc/finalize_area(var/area_name)
	var/area/A = new()
	A.name = area_name
	A.is_blueprint_area = TRUE
	var/area/old_area = get_area(selected_turfs[1])
	if(old_area.area_flags & AREA_FLAG_INDESTRUCTIBLE_TURFS) //to prevent new areas on exoplanets being ventable
		A.area_flags |= AREA_FLAG_INDESTRUCTIBLE_TURFS
	A.power_equip = FALSE
	A.power_light = FALSE
	A.power_environ = FALSE
	A.always_unpowered = FALSE
	return A

/mob/abstract/eye/blueprints/proc/remove_area()
	var/area/A = get_area(src)
	if(!check_modification_validity())
		return
	if(!check_rights(R_ADMIN, 0, owner))
		var/list/tier = get_faction_tier(owner)
		if(tier["rank"] < 2)
			to_chat(owner, SPAN_WARNING("You need command access in a faction to remove areas."))
			return
		if(A.persistent_network && A.persistent_network != tier["uid"])
			to_chat(owner, SPAN_WARNING("This area belongs to [get_faction_name(A.persistent_network)]'s territory -- only their command staff can remove it."))
			return
	if(A.apc)
		to_chat(owner, SPAN_WARNING("You must remove the APC from this area before you can remove it from the blueprints!"))
		return
	var/background_area = world.area
	var/obj/effect/overmap/visitable/sector/sector = GLOB.map_sectors["[A.z]"]
	var/obj/effect/overmap/visitable/sector/exoplanet/exoplanet = sector
	if(istype(exoplanet))
		background_area = exoplanet.planetary_area
	if(SSodyssey.scenario && (GET_Z(owner) in SSodyssey.scenario_zlevels))
		background_area = SSodyssey.scenario.base_area
	// Iterate a copy -- change_area() reassigns each turf's loc, which
	// mutates A.contents live. Iterating the real list while it shrinks
	// skips entries, leaving stray turfs behind so the area never actually
	// empties (and thus never qdels) even though the success message
	// below used to fire unconditionally beforehand regardless.
	for(var/turf/T in A.contents.Copy())
		T.change_area(T.loc, background_area)
	if(locate(/turf) in A)
		to_chat(owner, SPAN_WARNING("Some tiles of [A.name] could not be moved off the blueprints -- area not removed."))
		return
	to_chat(owner, SPAN_NOTICE("You scrub [A.name] off the blueprints."))
	log_and_message_admins("deleted area [A.name] via station blueprints.")
	qdel(A)

/// Flood-fills outward from the eye's current position through non-dense
/// (walkable) turfs, treating any dense turf (wall, closed door, etc.) as a
/// boundary that's included in the result but not expanded through --
/// "select this enclosed room, walls included" in one action, instead of
/// several manual box-select passes for an irregular room or hallway
/// offshoot. Goes straight into create_area() once the fill succeeds
/// (prompts for a name immediately), the same as finishing a manual
/// box-select and pressing "Mark New Area" -- no separate confirmation
/// step. Doors must be closed -- an open doorway lets the fill leak into
/// whatever's beyond it, which aborts the detection (see below) rather
/// than guessing a boundary.
/mob/abstract/eye/blueprints/proc/detect_room()
	var/turf/start = get_turf(src)
	if(!start || !(start.z in valid_z_levels))
		to_chat(owner, SPAN_WARNING("The markings on this are entirely irrelevant to your whereabouts!"))
		return
	if(start.density)
		to_chat(owner, SPAN_WARNING("You're standing inside a wall -- move into the room first."))
		return

	var/list/found = list()
	var/list/pending = list(start)
	var/enclosed = TRUE

	while(LAZYLEN(pending))
		if(LAZYLEN(found) > MAX_AREA_SIZE)
			enclosed = FALSE
			break
		var/turf/T = pending[1]
		pending -= T
		if(T in found)
			continue
		found += T
		if(T.density)
			continue // boundary turf -- included, but the fill doesn't pass through it
		for(var/dir in GLOB.cardinals)
			var/turf/NT = get_step(T, dir)
			if(!istype(NT) || NT.z != start.z || (NT in found) || (NT in pending))
				continue
			pending += NT

	if(!enclosed)
		to_chat(owner, SPAN_WARNING("That room isn't fully enclosed -- check for open doors or gaps in the walls, then try again."))
		return

	selected_turfs.Cut()
	for(var/turf/T in found)
		selected_turfs[T] = TRUE
	last_selected_turf = null
	last_selected_image.loc = null
	to_chat(owner, SPAN_NOTICE("Detected an enclosed room: [length(found)] tile\s, walls included."))
	create_area()

/// Add the current selection onto the area the eye is standing in, instead
/// of creating a new one. Selection may include background tiles (claimed
/// the normal way) *and* tiles already part of the target area (a no-op
/// reassignment, so extending an odd-shaped claim doesn't require avoiding
/// your own existing tiles).
/mob/abstract/eye/blueprints/proc/add_to_area()
	if(!check_rights(R_ADMIN, 0, owner))
		var/list/tier = get_faction_tier(owner)
		if(tier["rank"] < 1)
			to_chat(owner, SPAN_WARNING("You need officer access in a faction to modify blueprint areas."))
			return

	var/area/target = get_area(src)
	if(!check_modification_validity())
		return
	if(!check_selection_validity_for_area(target))
		to_chat(owner, SPAN_WARNING("Could not add to area: [english_list(errors)]!"))
		return
	var/added = 0
	for(var/turf/T in selected_turfs)
		if(get_area(T) == target)
			continue // already part of it, nothing to do
		T.change_area(T.loc, target)
		added++
	to_chat(owner, SPAN_NOTICE("Added [added] tile\s to [target.name]."))
	remove_selection()

/// Same validity rules as check_selection_validity(), except a turf that's
/// already part of the target area is accepted alongside background turfs.
/mob/abstract/eye/blueprints/proc/check_selection_validity_for_area(area/target)
	. = TRUE
	errors.Cut()
	if(!LAZYLEN(selected_turfs))
		errors |= "no turfs are selected"
		return FALSE
	if(LAZYLEN(selected_turfs) > MAX_AREA_SIZE)
		errors |= "selection exceeds max size"
		return FALSE
	if(LAZYLEN(target.contents) + LAZYLEN(selected_turfs) > MAX_AREA_SIZE)
		errors |= "area would exceed max size"
		return FALSE
	for(var/turf/T in selected_turfs)
		var/turf_valid = check_turf_validity_for_area(T, target)
		. = min(., turf_valid)
		selected_turfs[T] = turf_valid
	if(!.) return
	. = check_contiguity()

/mob/abstract/eye/blueprints/proc/check_turf_validity_for_area(var/turf/T, area/target)
	. = TRUE
	if(!T)
		return FALSE
	if(!(T.z in valid_z_levels))
		errors |= "selection isn't marked on the blueprints"
		. = FALSE
	var/area/A = T.loc
	if(!A)
		errors |= "selection overlaps unknown location"
		return FALSE
	if(A != target && !(A.area_flags & AREA_FLAG_IS_BACKGROUND))
		errors |= "selection overlaps other area"
		. = FALSE
	if(istype(T, (A.base_turf ? A.base_turf : /turf/space)))
		errors |= "selection is exposed to the outside"
		. = FALSE

/// Briefly overlays every turf currently in the area the eye is standing in,
/// so a player can see exactly what's already claimed before expanding it.
/mob/abstract/eye/blueprints/proc/highlight_area()
	var/area/A = get_area(src)
	if(!check_modification_validity())
		return
	var/list/highlight_images = list()
	for(var/turf/T in A.contents)
		if(T.z != src.z)
			continue
		var/image/I = image('icons/effects/blueprints.dmi', T, "valid")
		I.plane = HUD_PLANE
		I.appearance_flags = NO_CLIENT_COLOR
		highlight_images += I
	if(!owner?.client)
		return
	owner.client.images += highlight_images
	addtimer(CALLBACK(src, PROC_REF(_clear_highlight), highlight_images), 3 SECONDS)
	to_chat(owner, SPAN_NOTICE("Highlighting [length(highlight_images)] tile\s of [A.name]."))

/mob/abstract/eye/blueprints/proc/_clear_highlight(list/image/images)
	if(owner?.client)
		owner.client.images -= images
	QDEL_LIST(images)

/// Removes the current selection from the area the eye is standing in,
/// reverting those tiles to background -- shrinking an existing area
/// without deleting the whole thing. Only tiles actually part of that area
/// are removed; anything else in the selection is silently skipped.
/mob/abstract/eye/blueprints/proc/modify_area()
	var/area/A = get_area(src)
	if(!check_modification_validity())
		return
	if(!LAZYLEN(selected_turfs))
		to_chat(owner, SPAN_WARNING("Select tiles within [A.name] to remove them from it first."))
		return
	var/removed = 0
	for(var/turf/T in selected_turfs)
		if(get_area(T) != A)
			continue
		T.change_area(T.loc, world.area)
		removed++
	remove_selection()
	if(!removed)
		to_chat(owner, SPAN_WARNING("None of the selected tiles were part of [A.name]."))
		return
	to_chat(owner, SPAN_NOTICE("Removed [removed] tile\s from [A.name]."))
	if(!(locate(/turf) in A))
		qdel(A)

/mob/abstract/eye/blueprints/proc/edit_area()
	var/area/A = get_area(src)
	if(!check_modification_validity())
		return
	var/prevname = A.name
	var/new_area_name = sanitizeSafe(input("Edit area name:","Area Editing", prevname), MAX_NAME_LEN)
	if(!new_area_name || !LAZYLEN(new_area_name) || new_area_name==prevname)
		return
	if(length(new_area_name) > 50)
		to_chat(owner, SPAN_WARNING("Text too long."))
		return

	// Adjusting titles in the old area.
	var/static/list/types_to_rename = list(
		/obj/structure/machinery/alarm,
		/obj/structure/machinery/power/apc,
		/obj/structure/machinery/atmospherics/unary/vent_pump,
		/obj/structure/machinery/atmospherics/unary/vent_pump,
		/obj/structure/machinery/door
	)
	for(var/obj/structure/machinery/M in A)
		if(is_type_in_list(M, types_to_rename))
			M.name = replacetext(M.name, prevname, new_area_name)
	A.name = new_area_name
	to_chat(owner, SPAN_NOTICE("You set the area '[prevname]' title to '[new_area_name]'."))

/mob/abstract/eye/blueprints/ClickOn(atom/A, params)
	params = params2list(params)
	if(!canClick())
		return
	if(params["left"])
		update_selected_turfs(get_turf(A), params)
	if(params["ctrl"]) //Shift-click to clear the selection
		remove_selection()

/mob/abstract/eye/blueprints/proc/update_selected_turfs(var/turf/next_selected_turf, var/list/params)
	if(!next_selected_turf)
		return
	if(!last_selected_turf) //The player has only placed one corner of the block
		last_selected_turf = next_selected_turf
		last_selected_image.loc = last_selected_turf
		return
	if(last_selected_turf.z != next_selected_turf.z) // No multi-Z areas. Contiguity checks this as well, but this is cheaper.
		return

	var/list/new_selection = block(last_selected_turf, next_selected_turf)
	if(params["shift"]) //Right-click to remove areas from the selection
		selected_turfs -= new_selection
	else
		selected_turfs |= new_selection

	last_selected_image.loc = null //Remove last selected turf indicator image
	check_selection_validity()
	update_images()

/mob/abstract/eye/blueprints/proc/check_selection_validity()
	. = TRUE
	errors.Cut()

	if(!LAZYLEN(selected_turfs)) //Sanity check
		errors |= "no turfs are selected"
		return FALSE
	if(LAZYLEN(selected_turfs) > MAX_AREA_SIZE)
		errors |= "selection exceeds max size"
		return FALSE
	for(var/turf/T in selected_turfs)
		var/turf_valid = check_turf_validity(T)
		. = min(., turf_valid)
		selected_turfs[T] = turf_valid
	if(!.) return
	. = check_contiguity()

/mob/abstract/eye/blueprints/proc/check_turf_validity(var/turf/T)
	. = TRUE
	if(!T)
		return FALSE
	if(!(T.z in valid_z_levels))
		errors |= "selection isn't marked on the blueprints"
		. = FALSE
	var/area/A = T.loc
	if(!A) //Safety check
		errors |= "selection overlaps unknown location"
		return FALSE
	if(!(A.area_flags & AREA_FLAG_IS_BACKGROUND)) // Cannot create new areas over old ones.
		errors |= "selection overlaps other area"
		. = FALSE
	if(istype(T, (A.base_turf ? A.base_turf : /turf/space)))
		errors |= "selection is exposed to the outside"
		. = FALSE

/mob/abstract/eye/blueprints/proc/check_contiguity()
	var/turf/start_turf = pick(selected_turfs)
	var/list/pending_turfs = list(start_turf)
	var/list/checked_turfs = list()

	while(pending_turfs.len)
		if(LAZYLEN(checked_turfs) > MAX_AREA_SIZE)
			errors |= "selection exceeds max size"
			break
		var/turf/T = pending_turfs[1]
		pending_turfs -= T
		for(var/dir in GLOB.cardinals)	// Floodfill to find all turfs contiguous with the randomly chosen start_turf.
			var/turf/NT = get_step(T, dir)
			if(!isturf(NT) || !(NT in selected_turfs) || (NT in pending_turfs) || (NT in checked_turfs))
				continue
			pending_turfs += NT

		checked_turfs += T

	var/list/incontiguous_turfs = (selected_turfs.Copy() - checked_turfs)

	if(LAZYLEN(incontiguous_turfs)) // If turfs still remain in incontiguous_turfs, there are non-contiguous turfs in the selection.
		errors |= "selection must be contiguous"
		return FALSE

	return TRUE

/mob/abstract/eye/blueprints/proc/check_modification_validity()
	. = TRUE
	var/area/A = get_area(src)
	if(!(A.z in valid_z_levels))
		to_chat(owner, SPAN_WARNING("The markings on this are entirely irrelevant to your whereabouts!"))
		return FALSE
	if(A in SSshuttle.shuttle_areas)
		to_chat(owner, SPAN_WARNING("This segment of the blueprints looks far too complex. Best not touch it!"))
		return FALSE
	if(!A || (A.area_flags & AREA_FLAG_IS_BACKGROUND))
		to_chat(owner, SPAN_WARNING("This area is not marked on the blueprints!"))
		return FALSE

/mob/abstract/eye/blueprints/proc/remove_selection()
	selected_turfs.Cut()
	last_selected_turf = null
	update_images()

/mob/abstract/eye/blueprints/proc/update_images()
	if(!owner || !owner.client)
		return

	owner.client.images -= selection_images
	selection_images.Cut()
	if(LAZYLEN(selected_turfs))
		for(var/turf/T in selected_turfs)
			var/selection_icon_state = selected_turfs[T] ? "valid" : "invalid"
			var/image/I = image('icons/effects/blueprints.dmi', T, selection_icon_state)
			I.plane = HUD_PLANE
			I.appearance_flags = NO_CLIENT_COLOR
			selection_images += I

	owner.client.images |= last_selected_image
	owner.client.images += selection_images

/mob/abstract/eye/blueprints/setLoc(T)
	. = ..()
	var/style = "font-family: 'Fixedsys'; -dm-text-outline: 1 black; font-size: 11px;"
	var/area/A = get_area(src)
	if(!A)
		return
	area_name_effect.maptext = "<span style=\"[style]\">[area_prefix], [A.name]</span>"

/mob/abstract/eye/blueprints/additional_sight_flags()
	return SEE_TURFS|BLIND

/mob/abstract/eye/blueprints/apply_visual(mob/living/M)
	M.overlay_fullscreen("blueprints", /atom/movable/screen/fullscreen/blueprints)
	M.client.screen += area_name_effect
	M.add_client_color(/datum/client_color/monochrome)

/mob/abstract/eye/blueprints/remove_visual(mob/living/M)
	M.clear_fullscreen("blueprints", 0)
	M.client.screen -= area_name_effect
	M.remove_client_color(/datum/client_color/monochrome)

//Shuttle blueprint eye
/mob/abstract/eye/blueprints/shuttle
	var/shuttle_name

/mob/abstract/eye/blueprints/shuttle/Initialize(mapload, list/valid_zs, area_p, shuttle_name)
	. = ..()
	src.shuttle_name = shuttle_name

/mob/abstract/eye/blueprints/shuttle/check_modification_validity()
	. = TRUE
	var/area/A = get_area(src)
	if(!(A.z in valid_z_levels))
		to_chat(owner, SPAN_WARNING("The markings on this are entirely irrelevant to your whereabouts!"))
		return FALSE
	var/datum/shuttle/our_shuttle = SSshuttle.shuttles[shuttle_name]
	if(!(A in our_shuttle.shuttle_area))
		to_chat(owner, SPAN_WARNING("That's not a part of the [our_shuttle.name]!"))
		return FALSE
	if(!A || (A.area_flags & AREA_FLAG_IS_BACKGROUND))
		to_chat(owner, SPAN_WARNING("This area is not marked on the blueprints!"))
		return FALSE

/mob/abstract/eye/blueprints/shuttle/remove_area()
	var/area/A = get_area(src)
	if(!check_modification_validity())
		return
	if(A.apc)
		to_chat(owner, SPAN_WARNING("You must remove the APC from this area before you can remove it from the blueprints!"))
		return
	var/datum/shuttle/our_shuttle = SSshuttle.shuttles[shuttle_name]
	if(our_shuttle.shuttle_area.len == 1) //If it's the last shuttle area, make sure that we don't break the shuttle in question.
		to_chat(owner, SPAN_WARNING("You cannot delete the last area in a shuttle!"))
		return
	to_chat(owner, SPAN_NOTICE("You scrub [A.name] off the blueprints."))
	log_and_message_admins("deleted area [A.name] from [our_shuttle.name] via shuttle blueprints.")
	var/background_area = world.area
	var/obj/effect/overmap/visitable/sector/sector = GLOB.map_sectors["[A.z]"]
	var/obj/effect/overmap/visitable/sector/exoplanet/exoplanet = sector
	if(istype(exoplanet))
		background_area = exoplanet.planetary_area
	if(SSodyssey.scenario && (GET_Z(owner) in SSodyssey.scenario_zlevels))
		background_area = SSodyssey.scenario.base_area
	for(var/turf/T in A.contents)
		T.change_area(T.loc, background_area)
	if(!(locate(/turf) in A))
		qdel(A) // uh oh, is this safe?

/mob/abstract/eye/blueprints/shuttle/finalize_area(area_name)
	var/area/A = ..(area_name)
	var/datum/shuttle/our_shuttle = SSshuttle.shuttles[shuttle_name]
	our_shuttle.shuttle_area += A
	SSshuttle.shuttle_areas += A
	RegisterSignal(A, COMSIG_QDELETING, TYPE_PROC_REF(/datum/shuttle, remove_shuttle_area))
	return A

#undef MAX_AREA_SIZE
