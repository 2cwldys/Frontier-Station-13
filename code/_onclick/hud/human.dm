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

		// ── Autosave countdown (top-center, same blue styling) ────────────────
		target.save_timer = new /atom/movable/screen/text/save_timer()
		hud_elements |= target.save_timer

		// ── Security zone shield (top-right, recolors by zone) ────────────────
		target.zone_indicator = new /atom/movable/screen/zone_security_indicator(null, target)
		hud_elements |= target.zone_indicator

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

		// Slot frame colors handled at source in screen/dark.dmi via recolor script

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

	// ── Movement intent (WALK/RUN toggle) ────────────────────────────────────
	if(hud_data.has_m_intent)
		using = new /atom/movable/screen/movement_intent()
		using.icon = ui_style
		using.icon_state = (mymob.m_intent == M_RUN ? "running" : "walking")
		src.adding += using
		move_intent = using

	// ── Freelook (face-the-mouse toggle) ─────────────────────────────────────
	using = new /atom/movable/screen/freelook_toggle()
	using.icon = target.freelook_active ? 'icons/hud/mob/screen/look_active.png' : 'icons/hud/mob/screen/look_inactive.png'
	src.adding += using
	freelook_toggle = using

	// ── Attack intent — uses dark_original.dmi to preserve green/yellow/red colors ──
	if(hud_data.has_a_intent)
		using = new /atom/movable/screen()
		using.name = "act_intent"
		using.icon = 'icons/hud/mob/screen/dark_original.dmi'
		using.icon_state = "intent_"+mymob.a_intent
		using.screen_loc = ui_acti
		using.color = ui_color
		using.alpha = ui_alpha
		src.adding += using
		action_intent = using
		hud_elements |= using

	// ── Drop / throw / resist ────────────────────────────────────────────────
	if(hud_data.has_drop)
		using = new /atom/movable/screen()
		using.name = "drop"
		using.icon = ui_style
		using.icon_state = "act_drop"
		using.screen_loc = ui_drop
		src.hotkeybuttons += using
		hud_elements |= using

	if(hud_data.has_throw)
		mymob.throw_icon = new /atom/movable/screen()
		mymob.throw_icon.name = "throw"
		mymob.throw_icon.icon = ui_style
		mymob.throw_icon.icon_state = "act_throw_off"
		mymob.throw_icon.screen_loc = ui_throw
		src.hotkeybuttons += mymob.throw_icon
		hud_elements |= mymob.throw_icon

	if(hud_data.has_resist)
		using = new /atom/movable/screen()
		using.name = "resist"
		using.icon = ui_style
		using.icon_state = "act_resist"
		using.screen_loc = ui_pull_resist
		src.hotkeybuttons += using
		hud_elements |= using

	// ── REST button
	mymob.rest_icon = new /atom/movable/screen()
	mymob.rest_icon.name = "rest"
	mymob.rest_icon.icon = ui_style
	mymob.rest_icon.icon_state = "rest0"
	mymob.rest_icon.screen_loc = ui_rest
	src.hotkeybuttons += mymob.rest_icon
	hud_elements |= mymob.rest_icon

	// ── Health figure (G↔B swap turns green→blue while keeping white "100" text) ─
	if(hud_data.has_warnings)
		mymob.healths = new /atom/movable/screen()
		mymob.healths.icon = ui_style
		// Start blank: the human Life() hud update draws the real by-limb display
		// ("blank" + overlays); starting on "health0" flashes the raw dark.dmi
		// sprite for the first tick or two after login.
		mymob.healths.icon_state = "blank"
		mymob.healths.screen_loc = ui_health
		mymob.healths.color = list(1,0,0,0, 0,0,1,0, 0,1,0,0, 0,0,0,1, 0,0,0,0)
		hud_elements |= mymob.healths

		mymob.oxygen = new /atom/movable/screen/oxygen()
		mymob.oxygen.icon = 'icons/hud/mob/status_indicators.dmi'
		mymob.oxygen.icon_state = "oxy0"
		mymob.oxygen.screen_loc = ui_oxygen
		hud_elements |= mymob.oxygen

		mymob.internals = new /atom/movable/screen/internals()
		hud_elements |= mymob.internals

	// ── Hunger/thirst (status_hunger.dmi -- dark.dmi never got matching
	// sprites ported for these during the Serenity rework, so this keeps the
	// old icon file rather than the new unified one) ─────────────────────────
	if(hud_data.has_nutrition)
		mymob.nutrition_icon = new /atom/movable/screen/food()
		mymob.nutrition_icon.icon = 'icons/hud/mob/status_hunger.dmi'
		mymob.nutrition_icon.pixel_w = 8
		mymob.nutrition_icon.icon_state = "nutrition0"
		mymob.nutrition_icon.name = "nutrition"
		mymob.nutrition_icon.screen_loc = ui_nutrition
		hud_elements |= mymob.nutrition_icon

	if(hud_data.has_hydration)
		mymob.hydration_icon = new /atom/movable/screen/thirst()
		mymob.hydration_icon.icon = 'icons/hud/mob/status_hunger.dmi'
		mymob.hydration_icon.icon_state = "thirst0"
		mymob.hydration_icon.name = "thirst"
		mymob.hydration_icon.screen_loc = ui_nutrition
		hud_elements |= mymob.hydration_icon

	// ── Character doll (zone selector) — visible with puppet_new.dmi ─────────
	mymob.zone_sel = new /atom/movable/screen/zone_sel(null)
	mymob.zone_sel.icon = 'icons/hud/mob/puppet_new.dmi'
	mymob.zone_sel.ClearOverlays()
	mymob.zone_sel.AddOverlays(image('icons/hud/mob/zone_sel_newer.dmi', "[mymob.zone_sel.selecting]"))
	hud_elements |= mymob.zone_sel

	// ── Gun mode icons (Aurora's own icon files) ──────────────────────────────
	mymob.gun_setting_icon = new /atom/movable/screen/gun/mode(null)
	mymob.item_use_icon    = new /atom/movable/screen/gun/item(null)
	mymob.gun_move_icon    = new /atom/movable/screen/gun/move(null)
	mymob.radio_use_icon   = new /atom/movable/screen/gun/radio(null)
	mymob.toggle_firing_mode = new /atom/movable/screen/gun/burstfire(null)
	mymob.unique_action_icon = new /atom/movable/screen/gun/uniqueaction(null)
	// Gun cluster — EAST-2 column, tightly stacked above intent wheel, 20px steps
	mymob.gun_setting_icon.color = "#aaccff"
	mymob.gun_setting_icon.screen_loc = "EAST-2:26,SOUTH+1:5"
	mymob.toggle_firing_mode.color = "#aaccff"
	mymob.toggle_firing_mode.screen_loc = "EAST-2:26,SOUTH+2:5"
	mymob.unique_action_icon.color = "#aaccff"
	mymob.unique_action_icon.screen_loc = "EAST-2:26,SOUTH+2:13"
	// Aiming-only (shown when aiming gun): EAST-3 column, same rows
	mymob.item_use_icon.color = "#aaccff"
	mymob.item_use_icon.screen_loc = "EAST-3:24,SOUTH+1:5"
	mymob.gun_move_icon.color = "#aaccff"
	mymob.gun_move_icon.screen_loc = "EAST-3:24,SOUTH+1:25"
	mymob.radio_use_icon.color = "#aaccff"
	mymob.radio_use_icon.screen_loc = "EAST-3:24,SOUTH+2:13"
	hud_elements |= mymob.gun_setting_icon
	hud_elements |= mymob.toggle_firing_mode
	hud_elements |= mymob.unique_action_icon

	// ── Apply to screen ───────────────────────────────────────────────────────
	mymob.client.screen = list()
	mymob.client.screen += hud_elements
	mymob.client.screen += src.adding + src.hotkeybuttons
	inventory_shown = 0

	// Honor the per-client autosave countdown preference (Toggle Save Timer verb)
	if(target?.save_timer && !mymob.client.show_save_timer)
		mymob.client.screen -= target.save_timer

	// Honor the saved security-shield preference (Toggle Security Level Shield verb)
	if(target?.zone_indicator && (mymob.client.prefs.toggles & HIDE_ZONE_SHIELD))
		mymob.client.screen -= target.zone_indicator

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

		if(H.client.prefs.toggles_secondary & VIGNETTE)
			H.apply_vignette()

		if(H.client.prefs.toggles_secondary & CRT_SCANLINES)
			H.apply_crt_scanlines()


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
