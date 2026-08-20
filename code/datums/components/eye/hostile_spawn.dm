/datum/component/eye/hostile_spawn
	eye_type = /mob/abstract/eye/hostile_spawn
	action_type = /datum/action/eye/hostile_spawn

/datum/action/eye/hostile_spawn
	eye_type = /mob/abstract/eye/hostile_spawn

/datum/action/eye/hostile_spawn/help
	name = "Help"
	procname = "help"
	button_icon_state = "help"
	target_type = COMPONENT_TARGET

/datum/component/eye/hostile_spawn/proc/help()
	if(!current_looker)
		return
	to_chat(current_looker, SPAN_NOTICE("***********************************************************"))
	to_chat(current_looker, SPAN_NOTICE("Left Click  = Spawn a hostile at the clicked tile"))
	to_chat(current_looker, SPAN_NOTICE("Right Click = Remove an admin-spawned hostile at the clicked tile"))
	to_chat(current_looker, SPAN_NOTICE("***********************************************************"))
