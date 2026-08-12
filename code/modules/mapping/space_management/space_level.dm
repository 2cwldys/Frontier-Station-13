/datum/space_level
	var/name = "NAME MISSING"
	var/list/neigbours = list()
	var/list/traits
	var/z_value = 1 //actual z placement
	var/linkage = SELFLOOPING
	var/xi
	var/yi   //imaginary placements on the grid

/datum/space_level/New(new_z, new_name, list/new_traits = list())
	z_value = new_z
	name = new_name
	traits = new_traits

	if (islist(new_traits))
		for (var/trait in new_traits)
			SSmapping.z_trait_levels[trait] += list(new_z)
	else // in case a single trait is passed in
		SSmapping.z_trait_levels[new_traits] += list(new_z)


	set_linkage(new_traits[ZTRAIT_LINKAGE])

/// Replaces this level's traits after creation -- used when a template loads
/// onto an already-existing Z (load_into_z(), map_template.dm's Z-reuse
/// pool) instead of allocating a fresh one, so the Z reflects the CURRENT
/// template's traits rather than stale leftovers from whatever last occupied
/// it. Mirrors New()'s own trait-registration bookkeeping, plus unregisters
/// the old traits first (New() never has old traits to clean up).
/datum/space_level/proc/set_traits(list/new_traits = list())
	if (islist(traits))
		for (var/trait in traits)
			SSmapping.z_trait_levels[trait] -= z_value
	else if (!isnull(traits))
		SSmapping.z_trait_levels[traits] -= z_value

	traits = new_traits

	if (islist(new_traits))
		for (var/trait in new_traits)
			SSmapping.z_trait_levels[trait] += list(z_value)
	else
		SSmapping.z_trait_levels[new_traits] += list(z_value)

	set_linkage(new_traits[ZTRAIT_LINKAGE])
