/obj/item/modular_computer/handheld/pda
	name = "\improper PDA"
	lexical_name = "tablet"
	desc = "A personal data assistant. The latest in portable microcomputer solutions from Thinktronic Systems LTD."
	icon = 'icons/obj/modular_computers/pda.dmi'
	icon_state = "pda"
	item_state = "electronic"
	contained_sprite = TRUE
	icon_state_screensaver = "off"
	icon_state_unpowered = "pda"
	var/icon_add // this is the "bar" part in "pda-bar"
	enrolled = DEVICE_PRIVATE
	// PDAs otherwise inherit the base modular_computer rate (50W active /
	// 5W idle, same as a full console) -- far too fast for a tiny handheld
	// meant to sit in a pocket running off a small internal cell for a
	// whole shift. Cut to a fifth of that.
	base_active_power_usage = 10
	base_idle_power_usage = 1

/obj/item/modular_computer/handheld/pda/set_icon()
	if(icon_add)
		icon_state += "-[icon_add]"
	icon_state_unpowered = icon_state
	icon_state_broken = icon_state

/obj/item/modular_computer/handheld/pda/old
	icon = 'icons/obj/modular_computers/pda_old.dmi'

/obj/item/modular_computer/handheld/pda/rugged
	icon = 'icons/obj/modular_computers/pda_rugged.dmi'

/obj/item/modular_computer/handheld/pda/slate
	icon = 'icons/obj/modular_computers/pda_slate.dmi'

/obj/item/modular_computer/handheld/pda/smart
	icon = 'icons/obj/modular_computers/pda_smart.dmi'
