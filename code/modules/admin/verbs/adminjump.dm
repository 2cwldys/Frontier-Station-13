/mob/proc/on_mob_jump()
	return

/mob/abstract/ghost/on_mob_jump()
	QDEL_NULL(orbiting)

/client/proc/Jump(var/area/A in get_sorted_areas())
	set name = "Jump to Area"
	set desc = "Area to jump to"
	set category = "Admin.Jump"

	if(check_rights(R_ADMIN|R_MOD|R_DEBUG|R_DEV) || isstoryteller(src.mob))
		if(istype(usr, /mob/abstract/new_player))
			return

		if(GLOB.config.allow_admin_jump)
			usr.on_mob_jump()
			usr.forceMove(pick(get_area_turfs(A)))

			log_admin("[key_name(usr)] jumped to [A]")
			message_admins("[key_name_admin(usr)] jumped to [A]", 1)
			feedback_add_details("admin_verb","JA") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		else
			alert("Admin jumping disabled")

/client/proc/jumptoturf(var/turf/T in world)
	set name = "Jump to Turf"
	set category = "Admin.Jump"

	if(check_rights(R_ADMIN|R_MOD|R_DEBUG|R_DEV) || isstoryteller(src.mob))
		if(isnewplayer(usr))
			return

		if(GLOB.config.allow_admin_jump)
			log_admin("[key_name(usr)] jumped to [T.x],[T.y],[T.z] in [T.loc]")
			message_admins("[key_name_admin(usr)] jumped to [T.x],[T.y],[T.z] in [T.loc]", 1)
			usr.on_mob_jump()
			usr.forceMove(T)
			feedback_add_details("admin_verb","JT") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		else
			alert("Admin jumping disabled")
		return

/client/proc/jump_to_neural_lace()
	set name = "Jump to Neural Lace"
	set category = "Admin.Jump"
	set desc = "Lists every neural lace in the world (vaulted, installed, or loose) and jumps to the one you pick."

	if(!(check_rights(R_ADMIN|R_MOD|R_DEBUG|R_DEV) || isstoryteller(src.mob)))
		return
	if(isnewplayer(usr))
		return
	if(!GLOB.config.allow_admin_jump)
		alert("Admin jumping disabled")
		return

	var/list/options = list()
	for(var/obj/item/organ/internal/neural_lace/L in world)
		if(QDELETED(L))
			continue
		var/turf/T = get_turf(L)
		if(!T)
			continue
		var/status
		if(istype(L.loc, /obj/structure/machinery/lace_storage))
			status = "(Vaulted)"
		else if(L.owner)
			status = (L.owner.stat == DEAD) ? "(Installed, corpse)" : "(Installed, alive)"
		else if(L.lace_occupied)
			status = "(Consciousness, unvaulted)"
		else
			status = "(Loose)"
		options["[L.registered_name || "unregistered"] ([L.registered_ckey || "no ckey"]) [status] -- ([T.x],[T.y],[T.z])"] = L

	if(!length(options))
		to_chat(usr, SPAN_WARNING("No neural laces found in the world."))
		return

	var/chosen = tgui_input_list(usr, "Select a neural lace to jump to:", "Jump to Neural Lace", options)
	if(!chosen)
		return
	var/obj/item/organ/internal/neural_lace/target = options[chosen]
	if(QDELETED(target))
		to_chat(usr, SPAN_WARNING("That lace no longer exists."))
		return

	var/turf/T = get_turf(target)
	if(!T)
		to_chat(usr, SPAN_WARNING("Could not resolve a location for that lace."))
		return

	log_admin("[key_name(usr)] jumped to [target.registered_name]'s neural lace at [T.x],[T.y],[T.z] in [T.loc]")
	message_admins("[key_name_admin(usr)] jumped to [target.registered_name]'s neural lace", 1)
	usr.on_mob_jump()
	usr.forceMove(T)
	feedback_add_details("admin_verb","JNL")

	// Offer to vault AFTER the jump, once the admin can actually see the
	// lace/scene for themselves before deciding. Same eligibility
	// vaultAllLaces() (persistence.dm) already enforces for its own bulk
	// sweep -- never rip an installed lace out of someone who's still alive
	// and playing. A vaulted lace has nothing to do either.
	var/already_vaulted = istype(target.loc, /obj/structure/machinery/lace_storage)
	var/installed_alive = target.owner && target.owner.stat != DEAD
	if(already_vaulted || installed_alive || QDELETED(target))
		return
	var/vault_choice = tgui_alert(usr, "[target.registered_name]'s lace isn't vaulted. Vault it now?", "Jump to Neural Lace", list("Vault It", "Leave It"))
	if(vault_choice != "Vault It" || QDELETED(target))
		return

	target._auto_transfer_to_storage()
	if(QDELETED(target))
		to_chat(usr, SPAN_WARNING("The lace was lost during vaulting."))
		return
	// A lace still installed (even on a dead body) only gets as far as
	// surgical extraction on the first call -- _auto_transfer_to_storage()
	// ejects it via removed() and returns, scheduling a fresh 4-hour timer
	// rather than continuing on to the vault itself (see that proc's own
	// "removed() will call this again indirectly" comment: that's the NEW
	// timer, not an immediate re-invocation). Finish the job now, exactly
	// mirroring vaultAllLaces()'s (persistence.dm) own double-call handling
	// of this same case.
	if(!istype(target.loc, /obj/structure/machinery/lace_storage) && !target.owner)
		target._auto_transfer_to_storage()
	if(istype(target.loc, /obj/structure/machinery/lace_storage))
		to_chat(usr, SPAN_GOOD("Vaulted [target.registered_name]'s neural lace."))
		log_and_message_admins("vaulted [target.registered_name] ([target.registered_ckey])'s neural lace via Jump to Neural Lace", usr)
	else
		to_chat(usr, SPAN_WARNING("No available lace storage vault found -- [target.registered_name]'s lace could not be vaulted."))

/client/proc/jumptolobby()
	set category = "Admin.Jump"
	set name = "Jump to Lobby"

	if(check_rights(R_ADMIN|R_MOD|R_DEBUG|R_DEV) || isstoryteller(src.mob))
		if(isnewplayer(usr))
			return

		if(GLOB.config.allow_admin_jump)
			if(!GLOB.lobby_mobs_location)
				to_chat(usr, SPAN_WARNING("No lobby location is set."))
				return
			log_admin("[key_name(usr)] jumped to the lobby")
			message_admins("[key_name_admin(usr)] jumped to the lobby", 1)
			usr.on_mob_jump()
			usr.forceMove(GLOB.lobby_mobs_location)
			feedback_add_details("admin_verb","JL") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		else
			alert("Admin jumping disabled")

/client/proc/jumptomob(var/mob/M in GLOB.mob_list)
	set category = "Admin.Jump"
	set name = "Jump to Mob Admin"

	if(check_rights(R_ADMIN|R_MOD|R_DEBUG|R_DEV) || isstoryteller(src.mob))
		if(isnewplayer(usr))
			return

		if(GLOB.config.allow_admin_jump)
			log_admin("[key_name(usr)] jumped to [key_name(M)]")
			message_admins("[key_name_admin(usr)] jumped to [key_name_admin(M)]", 1)
			if(src.mob)
				var/mob/A = src.mob
				var/turf/T = get_turf(M)
				if(isturf(T))
					feedback_add_details("admin_verb","JM") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
					A.on_mob_jump()
					A.forceMove(T)
				else
					to_chat(A, "This mob is not located in the game world.")
		else
			alert("Admin jumping disabled")

/client/proc/jumptocoord(tx as num, ty as num, tz as num)
	set category = "Admin.Jump"
	set name = "Jump to Coordinate"

	if(!check_rights(R_ADMIN|R_MOD|R_DEBUG|R_DEV))
		return

	if (GLOB.config.allow_admin_jump)
		if(src.mob)
			var/mob/A = src.mob
			A.on_mob_jump()
			A.x = tx
			A.y = ty
			A.z = tz
			feedback_add_details("admin_verb","JC") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		message_admins("[key_name_admin(usr)] jumped to coordinates [tx], [ty], [tz]")

	else
		alert("Admin jumping disabled")

/client/proc/jumptozlevel()
	set category = "Admin.Jump"
	set name = "Jump to Z-Level"

	if(check_rights(R_ADMIN|R_MOD|R_DEBUG|R_DEV) || isstoryteller(src.mob))
		if(GLOB.config.allow_admin_jump)
			var/list/zlevels = list()
			for(var/z=0, z<world.maxz, z++)
				zlevels += z
			var/selection = input("Select z-level to jump to.", "Admin Jumping", null, null) as null|anything in zlevels
			if(!selection)
				to_chat(src, "No z-level selected.")
				return
			if(src && src.mob)
				var/mob/A = src.mob
				A.on_mob_jump()
				A.x = world.maxx/2
				A.y = world.maxy/2
				A.z = selection
				message_admins("[key_name_admin(usr)] jumped to z-level [selection]", 1)
				feedback_add_details("admin_verb","JZ") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		else
			alert("Admin jumping disabled")

/client/proc/jumptoshuttle()
	set category = "Admin.Jump"
	set name = "Jump to Shuttle"

	if(check_rights(R_ADMIN|R_MOD|R_DEBUG|R_DEV) || isstoryteller(src.mob))
		if(GLOB.config.allow_admin_jump)
			var/list/shuttles = list()
			for(var/shuttle_tag in SSshuttle.shuttles)
				shuttles += shuttle_tag
			var/selection = input("Select shuttle to jump to.", "Admin Jumping", null, null) as null|anything in shuttles
			if(!selection)
				to_chat(src, "No shuttle selected.")
				return
			var/datum/shuttle/shuttle = SSshuttle.shuttles[selection]
			if(src && src.mob && shuttle && shuttle.current_location && shuttle.current_location.loc)
				usr.on_mob_jump()
				usr.forceMove(shuttle.current_location.loc)
				message_admins("[key_name_admin(usr)] jumped to shuttle [selection]", 1)
				feedback_add_details("admin_verb","JSHU") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		else
			alert("Admin jumping disabled")

/client/proc/jumptoship()
	set category = "Admin.Jump"
	set name = "Jump to Ship"

	if(check_rights(R_ADMIN|R_MOD|R_DEBUG|R_DEV) || isstoryteller(src.mob))
		if(GLOB.config.allow_admin_jump)
			var/list/ships = list()
			for(var/ship in SSshuttle.ships)
				ships += ship
			var/selection = input("Select ship to jump to.", "Admin Jumping", null, null) as null|anything in ships
			if(!selection)
				to_chat(src, "No ship selected.")
				return
			var/obj/effect/overmap/visitable/ship/ship = selection
			if(src && src.mob && ship && ship.entry_points && ship.entry_points[1])
				usr.on_mob_jump()
				usr.forceMove(ship.entry_points[1].loc)
				message_admins("[key_name_admin(usr)] jumped to ship [selection]", 1)
				feedback_add_details("admin_verb","JSHI") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		else
			alert("Admin jumping disabled")

/client/proc/jumptosector()
	set category = "Admin.Jump"
	set name = "Jump to Sector"

	if(check_rights(R_ADMIN|R_MOD|R_DEBUG|R_DEV) || isstoryteller(src.mob))
		if(GLOB.config.allow_admin_jump)
			var/list/sectors = list()
			for(var/sector in SSshuttle.initialized_sectors)
				sectors += sector
			var/selection = input("Select sector to jump to.", "Admin Jumping", null, null) as null|anything in sectors
			if(!selection)
				to_chat(src, "No sector selected.")
				return
			var/obj/effect/overmap/visitable/sector/sector = selection
			if(src && src.mob && sector && sector.map_z && sector.map_z[1])
				var/mob/A = src.mob
				A.on_mob_jump()
				A.x = world.maxx/2
				A.y = world.maxy/2
				A.z = sector.map_z[1]
				message_admins("[key_name_admin(usr)] jumped to sector [selection]", 1)
				feedback_add_details("admin_verb","JSEC") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		else
			alert("Admin jumping disabled")

/client/proc/jumptokey()
	set category = "Admin.Jump"
	set name = "Jump to Key"

	if(!check_rights(R_ADMIN|R_MOD|R_DEBUG|R_DEV))
		return

	if(GLOB.config.allow_admin_jump)
		var/list/keys = list()
		for(var/mob/M in GLOB.player_list)
			keys += M.client
		var/client/selection = input("Please, select a player!", "Admin Jumping", null, null) as null|anything in sortKey(keys)
		if(!selection)
			to_chat(src, "No keys found.")
			return
		var/mob/M = selection.mob
		log_admin("[key_name(usr)] jumped to [key_name(M)]")
		message_admins("[key_name_admin(usr)] jumped to [key_name_admin(M)]", 1)
		usr.on_mob_jump()
		usr.forceMove(M.loc)
		feedback_add_details("admin_verb","JK") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	else
		alert("Admin jumping disabled")

/client/proc/Getmob(var/mob/M in GLOB.mob_list)
	set category = "Admin.Jump"
	set name = "Get Mob to Teleport"
	set desc = "Mob to teleport"
	if(check_rights(R_ADMIN|R_MOD|R_DEBUG) || isstoryteller(src.mob))
		if(GLOB.config.allow_admin_jump)
			log_admin("[key_name(usr)] teleported [key_name(M)]")
			message_admins("[key_name_admin(usr)] teleported [key_name_admin(M)]", 1)
			M.on_mob_jump()
			M.forceMove(get_turf(usr))
			feedback_add_details("admin_verb","GM") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
		else
			alert("Admin jumping disabled")

/client/proc/Getkey()
	set category = "Admin.Jump"
	set name = "Get Key to Teleport"
	set desc = "Key to teleport"

	if(!check_rights(R_ADMIN|R_MOD|R_DEBUG))
		return

	if(GLOB.config.allow_admin_jump)
		var/list/keys = list()
		for(var/mob/M in GLOB.player_list)
			keys += M.client
		var/client/selection = input("Please, select a player!", "Admin Jumping", null, null) as null|anything in sortKey(keys)
		if(!selection)
			return
		var/mob/M = selection.mob

		if(!M)
			return
		log_admin("[key_name(usr)] teleported [key_name(M)]")
		message_admins("[key_name_admin(usr)] teleported [key_name(M)]", 1)
		if(M)
			M.on_mob_jump()
			M.forceMove(get_turf(usr))
			feedback_add_details("admin_verb","GK") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!
	else
		alert("Admin jumping disabled")

/client/proc/sendmob(var/mob/M in sortmobs())
	set category = "Admin.Jump"
	set name = "Send Mob"
	if(!check_rights(R_ADMIN|R_MOD|R_DEBUG))
		return
	var/area/A = input(usr, "Pick an area.", "Pick an area") in get_sorted_areas()
	if(A)
		if(GLOB.config.allow_admin_jump)
			M.on_mob_jump()
			M.forceMove(pick(get_area_turfs(A)))
			feedback_add_details("admin_verb","SMOB") //If you are copy-pasting this, ensure the 2nd parameter is unique to the new proc!

			log_admin("[key_name(usr)] teleported [key_name(M)] to [A]")
			message_admins("[key_name_admin(usr)] teleported [key_name_admin(M)] to [A]", 1)
		else
			alert("Admin jumping disabled")
