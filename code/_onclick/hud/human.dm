/mob/living/carbon/human/instantiate_hud(datum/hud/HUD, ui_style, ui_color, ui_alpha)
	HUD.human_hud(ui_style, ui_color, ui_alpha, src)

// Complete Serenity HUD port — screen/dark.dmi icons (blue recolored), puppet_new.dmi (silver)
/datum/hud/proc/human_hud(var/ui_style='icons/hud/mob/screen/dark.dmi', var/ui_color = "#ffffff", var/ui_alpha = 255, var/mob/living/carbon/human/target)
	var/datum/hud_data/hud_data
	if(!istype(target))
		hud_data = new()
	else
		hud_data = target.species.hud

	// Serenity forces screen/dark.dmi for all HUD elements regardless of species
	ui_style = 'icons/hud/mob/screen/dark.dmi'

	src.adding = list()
	src.other = list()
	src.hotkeybuttons = list()

	var/list/hud_elements = list()
	var/atom/movable/screen/using
	var/atom/movable/screen/inventory/inv_box

	// ── Hovertext (blue glow on mouseover) ────────────────────────────────────
	if(istype(target))
		target.hovertext = new /atom/movable/screen/text()
		target.hovertext.maptext = ""
		target.hovertext.maptext_height = 100
		target.hovertext.maptext_width = 480
		target.hovertext.screen_loc = ui_hovertext
		hud_elements |= target.hovertext

	// ── Gear slots ────────────────────────────────────────────────────────────
	var/has_hidden_gear
	for(var/gear_slot in hud_data.gear)
		var/list/slot_data = hud_data.gear[gear_slot]
		var/hud_type = /atom/movable/screen/inventory
		if(slot_data["slot_type"])
			hud_type = slot_data["slot_type"]
		inv_box = new hud_type()
		inv_box.icon = ui_style
		inv_box.color = ui_color
		inv_box.alpha = ui_alpha
		inv_box.hud = src

		inv_box.name =        slot_data["name"]
		inv_box.screen_loc =  slot_data["loc"]
		inv_box.slot_id =     slot_data["slot"]
		inv_box.icon_state =  slot_data["state"]

		if(slot_data["dir"])
			inv_box.set_dir(slot_data["dir"])

		if(slot_data["toggle"])
			src.other += inv_box
			has_hidden_gear = 1
		else
			src.adding += inv_box

	if(has_hidden_gear)
		using = new /atom/movable/screen()
		using.name = "toggle"
		using.icon = ui_style
		using.icon_state = "other"
		using.screen_loc = ui_inventory
		using.color = ui_color
		using.alpha = ui_alpha
		src.adding += using

	// ── Hands — R/L inventory slots + swap button ────────────────────────────
	if(hud_data.has_hands)
		inv_box = new /atom/movable/screen/inventory/hand()
		inv_box.hud = src
		inv_box.name = "right hand"
		inv_box.icon = ui_style
		inv_box.icon_state = "r_hand_inactive"
		if(mymob && !mymob.hand)
			inv_box.icon_state = "r_hand_active"
		inv_box.screen_loc = ui_rhand
		inv_box.slot_id = slot_r_hand
		inv_box.color = ui_color
		inv_box.alpha = ui_alpha
		src.r_hand_hud_object = inv_box
		src.adding += inv_box

		inv_box = new /atom/movable/screen/inventory/hand()
		inv_box.hud = src
		inv_box.name = "left hand"
		inv_box.icon = ui_style
		inv_box.icon_state = "l_hand_inactive"
		if(mymob && mymob.hand)
			inv_box.icon_state = "l_hand_active"
		inv_box.screen_loc = ui_lhand
		inv_box.slot_id = slot_l_hand
		inv_box.color = ui_color
		inv_box.alpha = ui_alpha
		src.l_hand_hud_object = inv_box
		src.adding += inv_box

		target.update_hud_hands()

	// ── Gun mode icons (Aurora's own icon files) ──────────────────────────────
	mymob.gun_setting_icon = new /atom/movable/screen/gun/mode(null)
	mymob.item_use_icon    = new /atom/movable/screen/gun/item(null)
	mymob.gun_move_icon    = new /atom/movable/screen/gun/move(null)
	mymob.radio_use_icon   = new /atom/movable/screen/gun/radio(null)
	mymob.toggle_firing_mode = new /atom/movable/screen/gun/burstfire(null)
	mymob.unique_action_icon = new /atom/movable/screen/gun/uniqueaction(null)
	hud_elements |= mymob.gun_setting_icon
	hud_elements |= mymob.toggle_firing_mode
	hud_elements |= mymob.unique_action_icon

	// ── Apply to screen ───────────────────────────────────────────────────────
	mymob.client.screen = list()
	mymob.client.screen += hud_elements
	mymob.client.screen += src.adding + src.hotkeybuttons
	inventory_shown = 0

	// ── Aurora: vision cone + film grain ─────────────────────────────────────
	var/mob/living/carbon/human/H = mymob
	if(istype(H))
		H.fov          = new /atom/movable/screen/fov()
		H.fov_mask     = new /atom/movable/screen/fov_mask()
		H.fov_mask_two = new /atom/movable/screen/fov_mask_two()
		H.client.screen += H.fov
		H.client.screen += H.fov_mask
		H.client.screen += H.fov_mask_two
		H.update_vision_cone()

		H.film_grain = new /atom/movable/screen/film_grain()
		H.film_grain.icon_state = "[rand(1,9)] moderate"
		H.client.screen += H.film_grain


/mob/living/carbon/human/verb/toggle_hotkey_verbs()
	set category = "OOC"
	set name = "Toggle hotkey buttons"
	set desc = "This disables or enables the user interface buttons which can be used with hotkeys."

	if(hud_used.hotkey_ui_hidden)
		client.screen += hud_used.hotkeybuttons
		hud_used.hotkey_ui_hidden = 0
	else
		client.screen -= hud_used.hotkeybuttons
		hud_used.hotkey_ui_hidden = 1

//Used for new human mobs created by cloning/goleming/etc.
/mob/living/carbon/human/proc/set_cloned_appearance()
	f_style = "Shaved"
	if(dna.species == SPECIES_HUMAN) //no more xenos losing ears/tentacles
		h_style = pick("Bedhead", "Bedhead 2", "Bedhead 3")
	all_underwear.Cut()
	regenerate_icons()

// Yes, these use icon state. Yes, these are terrible. The alternative is duplicating
// a bunch of fairly blobby logic for every click override on these objects.

/atom/movable/screen/food/Click(var/location, var/control, var/params)
	if(istype(usr) && usr.nutrition_icon == src)
		switch(icon_state)
			if("nutrition0")
				to_chat(usr, SPAN_WARNING("You are completely stuffed."))
			if("nutrition1")
				to_chat(usr, SPAN_NOTICE("You are not hungry."))
			if("nutrition2")
				to_chat(usr, SPAN_NOTICE("You are a bit peckish."))
			if("nutrition3")
				to_chat(usr, SPAN_WARNING("You are quite hungry."))
			if("nutrition4")
				to_chat(usr, SPAN_WARNING("You are really hungry."))
			if("nutrition5")
				to_chat(usr, SPAN_DANGER("You are starving!"))
			if("charge0")
				to_chat(usr, SPAN_GOOD("You are fully charged."))
			if("charge1")
				to_chat(usr, SPAN_NOTICE("You're almost topped up."))
			if("charge2")
				to_chat(usr, SPAN_NOTICE("You could go for a recharge."))
			if("charge3")
				to_chat(usr, SPAN_WARNING("You're running a bit low."))
			if("charge4")
				to_chat(usr, SPAN_WARNING("You're getting close to running out."))
			if("charge5")
				to_chat(usr, SPAN_DANGER("You have almost no charge left!"))

/atom/movable/screen/thirst/Click(var/location, var/control, var/params)
	if(istype(usr) && usr.hydration_icon == src)
		switch(icon_state)
			if("thirst0")
				to_chat(usr, SPAN_WARNING("You are completely hydrated."))
			if("thirst1")
				to_chat(usr, SPAN_NOTICE("You are not thirsty"))
			if("thirst2")
				to_chat(usr, SPAN_NOTICE("You are a bit thirsty."))
			if("thirst3")
				to_chat(usr, SPAN_WARNING("You are quite thirsty."))
			if("thirst4")
				to_chat(usr, SPAN_DANGER("You are entirely dehydrated!"))

/atom/movable/screen/bodytemp/Click(var/location, var/control, var/params)
	if(istype(usr) && usr.bodytemp == src)
		switch(icon_state)
			if("temp4")
				to_chat(usr, SPAN_DANGER("You are being cooked alive!"))
			if("temp3")
				to_chat(usr, SPAN_DANGER("Your body is burning up!"))
			if("temp2")
				to_chat(usr, SPAN_DANGER("You are overheating."))
			if("temp1")
				to_chat(usr, SPAN_WARNING("You are uncomfortably hot."))
			if("temp-4")
				to_chat(usr, SPAN_DANGER("You are being frozen solid!"))
			if("temp-3")
				to_chat(usr, SPAN_DANGER("You are freezing cold!"))
			if("temp-2")
				to_chat(usr, SPAN_WARNING("You are dangerously chilled"))
			if("temp-1")
				to_chat(usr, SPAN_NOTICE("You are uncomfortably cold."))
			else
				to_chat(usr, SPAN_NOTICE("Your body is at a comfortable temperature."))

/atom/movable/screen/pressure/Click(var/location, var/control, var/params)
	if(istype(usr) && usr.pressure == src)
		switch(icon_state)
			if("pressure2")
				to_chat(usr, SPAN_DANGER("The air pressure here is crushing!"))
			if("pressure1")
				to_chat(usr, SPAN_WARNING("The air pressure here is dangerously high."))
			if("pressure-1")
				to_chat(usr, SPAN_WARNING("The air pressure here is dangerously low."))
			if("pressure-2")
				to_chat(usr, SPAN_DANGER("There is nearly no air pressure here!"))
			else
				to_chat(usr, SPAN_NOTICE("The local air pressure is comfortable."))

/atom/movable/screen/toxins/Click(var/location, var/control, var/params)
	if(istype(usr) && usr.toxin == src)
		if(icon_state == "tox0")
			to_chat(usr, SPAN_NOTICE("The air is clear of toxins."))
		else
			to_chat(usr, SPAN_DANGER("The air is eating away at your skin!"))

/atom/movable/screen/oxygen/Click(var/location, var/control, var/params)
	if(istype(usr) && usr.oxygen == src)
		if(icon_state == "oxy0")
			to_chat(usr, SPAN_NOTICE("You are breathing easy."))
		else
			to_chat(usr, SPAN_DANGER("You cannot breathe!"))

/atom/movable/screen/paralysis/Click(var/location, var/control, var/params)
	if(istype(usr) && usr.paralysis_indicator == src)
		if(usr.paralysis)
			to_chat(usr, SPAN_WARNING("You are completely paralyzed and cannot move!"))
		else
			to_chat(usr, SPAN_NOTICE("You are walking around completely fine."))

/atom/movable/screen/instability
	name = "instability"
	icon = 'icons/hud/mob/screen_gen.dmi'
	icon_state = "instability-1"
	invisibility = 101

/atom/movable/screen/energy
	name = "energy"
	icon = 'icons/hud/mob/screen_gen.dmi'
	icon_state = "wiz_energy"
	invisibility = 101

/atom/movable/screen/status
	icon = 'icons/hud/mob/midnight.dmi'
	icon_state = "status_template"
	var/status_message

/atom/movable/screen/status/Initialize(mapload, var/set_icon, var/set_overlay, var/set_status_message)
	icon = set_icon
	var/image/status_overlay = image('icons/hud/mob/hud_status.dmi', null, set_overlay)
	status_overlay.appearance_flags = RESET_COLOR
	AddOverlays(status_overlay)
	status_message = set_status_message
	return ..()

/atom/movable/screen/status/Click(var/location, var/control, var/params)
	var/list/modifiers = params2list(params)
	if(status_message && modifiers["shift"])
		to_chat(usr, status_message)
