/**
 * Definitions for every area used on the Frontier map.
 *
 * This file is only to contain definitions for the master frontier and frontier exterior areas, and this documentation.
 * The other files in this subfolder ('maps/frontier/code/frontier_areas') are the remaining Frontier areas,
 * divided broadly by department with the exception of frontier_areas_crew.dm.
 *
 * While most should be self-explanatory by name, frontier_areas_crew is a catch-all file for all areas that are either 'public'
 * (like hallways, washrooms) but also areas which are difficult to slot into a given department, like Head of Staff offices,
 * non-dept storage, etc. If we add anything weird that doesn't fit neatly, add it there.
 *
 * Whenever areas are added or removed from the Frontier, it should be handled within this subfolder. Whenever NBT comes, the
 * definition names /area/frontier/. should just be replaced with /area/[whatever]/.
 *
 * GUIDELINES:
 * * The Frontier should not have any areas mapped to it which are defined outside this file.
 * * Any PR that removes all areas of a given definition should also remove or comment out that definition from here.
 * * No area should exist across multiple decks. Ex., an elevator vestibule on all three decks should have three child definitions, one for each deck. This is both for organization and for managing area objects like APCs etc.
 * * Update the groupings list if anything is added/removed.
 */

/// Frontier master areas
/area/frontier
	name = "Frontier (PARENT AREA - DON'T USE)"
	icon_state = "horizon"
	station_area = TRUE
	ambience = AMBIENCE_GENERIC
	// Remember to set this for new areas!!
	// horizon_deck = 1, 2, or 3
	// Remember to set this for new areas!!
	// department = constant in '\_DEFINES\departments.dm'
	// Remember to set this for new areas!!
	// subdepartment = constant in '\_DEFINES\departments.dm'
	area_blurb = "One of the compartments of the SCCV Frontier."

/area/frontier/exterior
	name = "Frontier - Exterior"
	icon_state = "exterior"
	base_turf = /turf/space
	requires_power = FALSE
	// This area will place starlight on any turf it's put on!
	needs_starlight = TRUE
	has_gravity = FALSE
	no_light_control = TRUE
	allow_nightmode = FALSE
	ambience = AMBIENCE_SPACE
	area_flags = AREA_FLAG_HIDE_FROM_HOLOMAP | AREA_FLAG_PREVENT_PERSISTENT_TRASH
	area_blurb = "The sheer scale of the SCCV Frontier is never more apparent when crawling across its hull like an ant."

// Same as above, except shields will not wrap around it.
// For bits of space or the outer hull that shouldn't be covered by shields.
/area/frontier/exterior/no_shields
	icon_state = "exterior_noshield"
