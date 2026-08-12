/// Deterministic per-turf pick from a list of icon variants -- shared by
/// anything that wants "not every wall looks byte-identical" without a real
/// per-instance rendering mechanism: /turf/simulated/wall/update_material()
/// (below) and the CentCom wall turfs (walls.dm) both call this rather than
/// each keeping their own copy of the hash, so there is exactly one place
/// this logic can drift.
///
/// Must return the same variant every time a given turf's icon is rebuilt
/// (damage, save/load, admin edits, mapload) -- hence a hash of position, not
/// random(). Small multipliers, then an xor-shift mixing step, rather than one
/// big multiply-and-xor: DM numbers are 32-bit floats, exact only up to
/// 2**24 -- x/y/z run through coordinates in the hundreds, and large
/// multipliers like 73856093 would blow past that exact range before the
/// bitwise op even ran, at which point the "hash" is really just float
/// rounding error. Every value here stays under a few million, well inside
/// exact-integer range, and the shift-xor step keeps the result from being a
/// simple linear (and therefore visibly striped) function of x/y/z.
///
/// Returns null if variants is empty, so callers can tell "no pool" apart
/// from "picked the one entry in a 1-length pool".
/proc/pick_wall_icon_variant(x, y, z, list/variants)
	if(!length(variants))
		return null
	var/wall_hash = x * 12 + y * 197 + z * 51
	wall_hash = wall_hash ^ (wall_hash << 5)
	wall_hash = wall_hash ^ (wall_hash >> 3)
	var/variant_index = 1 + (abs(wall_hash) % length(variants))
	var/picked = variants[variant_index]
#ifdef WALL_RESTORE_DIAGNOSTICS
	// /icon objects built via new()+Blend() (every entry here, post-New())
	// stringify to the generic word "icon" -- useless for telling two
	// variants apart. REF() gives each one's real identity instead, so this
	// is the only way to confirm from a log alone whether two different
	// tiles actually picked two different objects.
	log_subsystem_persistence_info("pick_wall_icon_variant: pos=([x],[y],[z]) pool_size=[length(variants)] index=[variant_index] picked=[REF(picked)]")
#endif
	return picked

/turf/simulated/wall/proc/update_material()
	if(!material)
		return

	if(reinf_material)
		construction_stage = 6
	else
		construction_stage = null
	if(!material)
		material = SSmaterials.get_material_by_name(DEFAULT_WALL_MATERIAL)
	if(material)
		explosion_resistance = material.explosion_resistance
		var/picked_variant = pick_wall_icon_variant(x, y, z, material.wall_icon_variants)
		if(picked_variant)
			icon = picked_variant
		else if (material.wall_icon)
			icon = material.wall_icon

	if(reinf_material && reinf_material.explosion_resistance > explosion_resistance)
		explosion_resistance = reinf_material.explosion_resistance

	if(reinf_material)
		name = "reinforced [material.display_name] wall"
		if(material.display_name == reinf_material.display_name)
			desc = "It seems to be a section of hull reinforced and plated with [material.display_name]."
		else
			desc = "It seems to be a section of hull reinforced with [reinf_material.display_name] and plated with [material.display_name]."
	else
		name = "[material.display_name] wall"
		desc = "It seems to be a section of hull plated with [material.display_name]."

	if(material.opacity < 0.5)
		opacity = FALSE
		alpha = 125

	if(!opacity)
		var/turf/under_floor = under_turf
		var/image/under_image = image(initial(under_floor.icon), icon_state = initial(under_floor.icon_state))
		under_image.alpha = 255
		underlays += under_image

	update_icon()

/turf/simulated/wall/proc/set_material(var/material/newmaterial, var/material/newrmaterial)
	material = newmaterial
	reinf_material = newrmaterial
	update_material()

/turf/simulated/wall/update_icon()
	if(!material)
		return

	if(!damage_overlays[1]) //list hasn't been populated
		generate_overlays()

	if (LAZYLEN(reinforcement_images))
		CutOverlays(reinforcement_images, ATOM_ICON_CACHE_PROTECTED)
	if (damage_image)
		CutOverlays(damage_image, ATOM_ICON_CACHE_PROTECTED)

	LAZYCLEARLIST(reinforcement_images)
	damage_image = null

	var/list/overlays_to_add = list()

	if (!density)	// We're a fake and we're open.
		clear_smooth_overlays()
		fake_wall_image = image('icons/turf/wall_masks.dmi', "[material.icon_base]fwall_open")
		fake_wall_image.color = material.icon_colour
		AddOverlays(fake_wall_image)
		smoothing_flags = SMOOTH_FALSE
		return
	else if (fake_wall_image)
		CutOverlays(fake_wall_image)
		fake_wall_image = null
		smoothing_flags = initial(smoothing_flags)

	calculate_adjacencies()	// Update cached_adjacency

	if(reinf_material)
		var/image/I
		// wall_colour, not icon_colour: icon_colour is the shared "every product
		// of this material" tint (sheets, tables, stacks...) -- reinf_icon is a
		// wall-only overlay, so it should follow the same walls-only knob the
		// base wall_icon already blends with in /material/New(). Falls back to
		// icon_colour for any material that never set wall_colour, so nothing
		// existing changes unless it opts in.
		var/reinf_colour = reinf_material.wall_colour || reinf_material.icon_colour
		if(construction_stage != null && construction_stage < 6)
			I = image('icons/turf/wall_masks.dmi', "reinf_construct-[construction_stage]")
			I.color = reinf_colour
			LAZYADD(reinforcement_images, I)
		else
			if (reinf_material.multipart_reinf_icon)
				LAZYADD(reinforcement_images, cardinal_smooth_fromicon(reinf_material.multipart_reinf_icon, cached_adjacency))
			else
				I = image('icons/turf/wall_masks.dmi', reinf_material.reinf_icon)
				I.color = reinf_colour
				LAZYADD(reinforcement_images, I)

		if (reinforcement_images)
			overlays_to_add += reinforcement_images

	if(health < maxhealth)
		var/integrity = material.integrity
		if(reinf_material)
			integrity += reinf_material.integrity

		var/overlay = round(abs(health - maxhealth) / integrity * damage_overlays.len) + 1
		if(overlay > damage_overlays.len)
			overlay = damage_overlays.len

		damage_image = damage_overlays[overlay]
		overlays_to_add += damage_image

	// Remove the existing damage overlay entirely and replace it with the newly-calculated one.
	CutOverlays(damage_overlays)

	AddOverlays(overlays_to_add)
	UNSETEMPTY(reinforcement_images)
	QUEUE_SMOOTH(src)
	if(smoothing_flags & SMOOTH_UNDERLAYS)
		get_underlays(cached_adjacency)

/turf/simulated/wall/proc/generate_overlays()
	for(var/damage_level = 1; damage_level <= damage_overlays.len; damage_level++) // Generate damage overlay for each placeholder (16 in array)
		var/image/damage_overlay = image(icon = 'icons/turf/walls.dmi', icon_state = "overlay_damage")
		damage_overlay.blend_mode = BLEND_MULTIPLY

		// The actual difference in each damage overlay is represented with a different alpha value, higher alpha = higher visible damage
		damage_overlay.alpha = damage_level * 18 + 32; // Linear scale with inital offset

		damage_overlays[damage_level] = damage_overlay
