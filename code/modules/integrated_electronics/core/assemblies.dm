/obj/item/electronic_assembly
	name = "electronic assembly"
	desc = "It's a case, for building small electronics with."
	w_class = WEIGHT_CLASS_SMALL
	icon = 'icons/obj/assemblies/electronic_setups.dmi'
	icon_state = "setup_small"
	item_flags = ITEM_FLAG_NO_BLUDGEON
	light_system = MOVABLE_LIGHT

	var/max_components = IC_COMPONENTS_BASE
	var/max_complexity = IC_COMPLEXITY_BASE
	var/opened = 0
	var/can_anchor = FALSE // If true, wrenching it will anchor it.
	var/obj/item/cell/device/battery // Internal cell which most circuits need to work.
	var/detail_color = COLOR_ASSEMBLY_BLACK
	var/obj/item/card/id/access_card

/obj/item/electronic_assembly/implant
	name = "electronic implant"
	icon_state = "setup_implant"
	desc = "It's a case, for building very tiny electronics with."
	w_class = WEIGHT_CLASS_TINY
	max_components = IC_COMPONENTS_BASE * 3/4
	max_complexity = IC_COMPLEXITY_BASE * 3/4
	var/obj/item/implant/integrated_circuit/implant = null

/obj/item/electronic_assembly/Initialize(mapload, printed = FALSE)
	. = ..()
	if (!printed)
		battery = new(src)
	START_PROCESSING(SSelectronics, src)
	access_card = new /obj/item/card/id(src)

/obj/item/electronic_assembly/Destroy()
	QDEL_NULL(battery)
	STOP_PROCESSING(SSelectronics, src)
	QDEL_NULL(access_card)
	return ..()

/obj/item/electronic_assembly/Collide(atom/AM)
	var/collw = AM
	.=..()
	if((istype(collw, /obj/structure/machinery/door/airlock) ||  istype(collw, /obj/structure/machinery/door/window)) && (!isnull(access_card)))
		var/obj/structure/machinery/door/D = collw
		if(D.check_access(access_card))
			D.open()

/obj/item/electronic_assembly/process()
	handle_idle_power()

/obj/item/electronic_assembly/proc/handle_idle_power()
	// First we generate power.
	for(var/obj/item/integrated_circuit/passive/power/P in contents)
		P.make_energy()

	// Now spend it.
	for(var/obj/item/integrated_circuit/IC in contents)
		if(IC.power_draw_idle && !draw_power(IC.power_draw_idle))
			IC.power_fail()

/obj/item/electronic_assembly/implant/update_icon()
	..()
	implant.icon_state = icon_state

/obj/item/electronic_assembly/implant/ui_host()
	return implant

/obj/item/electronic_assembly/proc/resolve_ui_host()
	return src

/obj/item/electronic_assembly/implant/resolve_ui_host()
	return implant

/obj/item/electronic_assembly/proc/check_interactivity(mob/user)
	if(!CanInteract(user, GLOB.physical_state))
		return 0
	return 1

/obj/item/electronic_assembly/interact(mob/user)
	if(!check_interactivity(user))
		return

	var/total_parts = 0
	var/total_complexity = 0
	for(var/obj/item/integrated_circuit/part in contents)
		total_parts += part.size
		total_complexity = total_complexity + part.complexity
	var/list/HTML = list()

	HTML += "<br><a href='byond://?src=[REF(src)]'>Refresh</a>  |  "
	HTML += "<a href='byond://?src=[REF(src)];rename=1'>Rename</a><br>"
	HTML += "[total_parts]/[max_components] ([round((total_parts / max_components) * 100, 0.1)]%) space taken up in the assembly.<br>"
	HTML += "[total_complexity]/[max_complexity] ([round((total_complexity / max_complexity) * 100, 0.1)]%) maximum complexity.<br>"
	if(battery)
		HTML += "[round(battery.charge, 0.1)]/[battery.maxcharge] ([round(battery.percent(), 0.1)]%) cell charge. <a href='byond://?src=[REF(src)];remove_cell=1'>Remove</a>"
	else
		HTML += SPAN_DANGER("No powercell detected!")
	HTML += "<br><br>"
	HTML += "Components:<hr>"
	HTML += "Built in:<br>"


//Put removable circuits in separate categories from non-removable
	for(var/obj/item/integrated_circuit/circuit in contents)
		if(!circuit.removable)
			HTML += "<a href='byond://?src=[REF(circuit)];examine=1;from_assembly=1'>'[circuit.displayed_name]</a> | "
			HTML += "<a href='byond://?src=[REF(circuit)];rename=1;from_assembly=1'>Rename</a> | "
			HTML += "<a href='byond://?src=[REF(circuit)];scan=1;from_assembly=1'>Scan with Debugger</a> | "
			HTML += "<a href='byond://?src=[REF(circuit)];bottom=[REF(circuit)];from_assembly=1'>Move to Bottom</a>"
			HTML += "<br>"

	HTML += "<hr>"
	HTML += "Removable:<br>"

	for(var/obj/item/integrated_circuit/circuit in contents)
		if(circuit.removable)
			HTML += "<a href='byond://?src=[REF(circuit)];examine=1;from_assembly=1'>[circuit.displayed_name]</a> | "
			HTML += "<a href='byond://?src=[REF(circuit)];rename=1;from_assembly=1'>Rename</a> | "
			HTML += "<a href='byond://?src=[REF(circuit)];scan=1;from_assembly=1'>Scan with Debugger</a> | "
			HTML += "<a href='byond://?src=[REF(circuit)];remove=1;from_assembly=1'>Remove</a> | "
			HTML += "<a href='byond://?src=[REF(circuit)];bottom=[REF(circuit)];from_assembly=1'>Move to Bottom</a>"
			HTML += "<br>"

	var/datum/browser/B = new(user, "assembly-[REF(src)]", name, 600, 400)
	B.set_content(HTML.Join())
	B.open(FALSE)

/obj/item/electronic_assembly/Topic(href, href_list[])
	if(..())
		return 1
	if(!opened)
		to_chat(usr, SPAN_WARNING("\The [src] is not open!"))
		return

	if(href_list["rename"])
		rename(usr)

	if(href_list["remove_cell"])
		if(!battery)
			to_chat(usr, SPAN_WARNING("There's no power cell to remove from \the [src]."))
		else
			var/turf/T = get_turf(src)
			battery.forceMove(T)
			playsound(T, 'sound/items/crowbar_pry.ogg', 50, 1)
			to_chat(usr, SPAN_NOTICE("You pull \the [battery] out of \the [src]'s power supply."))
			battery = null

	interact(usr) // To refresh the UI.

/obj/item/electronic_assembly/verb/rename()
	set name = "Rename Circuit"
	set category = "Object"
	set desc = "Rename your circuit, useful to stay organized."
	set src in usr

	var/mob/M = usr
	if(!check_interactivity(M))
		return null

	var/input = sanitizeSafe(input("What do you want to name this?", "Rename", src.name) as null|text, MAX_NAME_LEN)
	if(src && input)
		to_chat(M, SPAN_NOTICE("The machine now has a label reading '[input]'."))
		name = input
		return input
	return null

/obj/item/electronic_assembly/proc/can_move()
	return FALSE

/obj/item/electronic_assembly/update_icon()
	if(opened)
		icon_state = "[initial(icon_state)]-open"
	else
		icon_state = initial(icon_state)
	ClearOverlays()
	if(detail_color == COLOR_ASSEMBLY_BLACK) //Black colored overlay looks almost but not exactly like the base sprite, so just cut the overlay and avoid it looking kinda off.
		return
	var/image/detail_overlay = image('icons/obj/assemblies/electronic_setups.dmi', "[icon_state]-color")
	detail_overlay.color = detail_color
	AddOverlays(detail_overlay)

/obj/item/electronic_assembly/GetAccess()
	. = list()
	for(var/obj/item/integrated_circuit/part in contents)
		. |= part.GetAccess()

/obj/item/electronic_assembly/feedback_hints(mob/user, distance, is_adjacent)
	. = ..()
	if(opened && is_adjacent)
		for(var/obj/item/integrated_circuit/IC in contents)
			. += SPAN_NOTICE("It contains \a [IC].")

/obj/item/electronic_assembly/proc/get_part_complexity()
	. = 0
	for(var/obj/item/integrated_circuit/part in contents)
		. += part.complexity

/obj/item/electronic_assembly/proc/get_part_size()
	. = 0
	for(var/obj/item/integrated_circuit/part in contents)
		. += part.size

// Returns true if the circuit made it inside.
/obj/item/electronic_assembly/proc/add_circuit(obj/item/integrated_circuit/IC, mob/user)
	if(!opened)
		to_chat(user, SPAN_WARNING("\The [src] isn't opened, so you can't put anything inside.  Try using a crowbar."))
		return FALSE

	if(IC.w_class > w_class)
		to_chat(user, SPAN_WARNING("\The [IC] is way too big to fit into \the [src]."))
		return FALSE

	var/total_part_size = get_part_size()
	var/total_complexity = get_part_complexity()

	if((total_part_size + IC.size) > max_components)
		to_chat(user, SPAN_WARNING("You can't seem to add the '[IC.name]', as there's insufficient space."))
		return FALSE
	if((total_complexity + IC.complexity) > max_complexity)
		to_chat(user, SPAN_WARNING("You can't seem to add the '[IC.name]', since this setup's too complicated for the case."))
		return FALSE

	if(!IC.forceMove(src))
		return FALSE

	IC.assembly = src

	return TRUE

// Non-interactive version of above that always succeeds, intended for build-in circuits that get added on assembly initialization.
/obj/item/electronic_assembly/proc/force_add_circuit(var/obj/item/integrated_circuit/IC)
	IC.forceMove(src)
	IC.assembly = src

/obj/item/electronic_assembly/afterattack(atom/target, mob/user, proximity)
	for(var/obj/item/integrated_circuit/input/sensor/S in contents)
		S.sense(target, user)

/obj/item/electronic_assembly/attackby(obj/item/attacking_item, mob/user)
	if(istype(attacking_item, /obj/item/integrated_circuit))
		if(!user.unEquip(attacking_item))
			return FALSE

		if(add_circuit(attacking_item, user))
			to_chat(user, SPAN_NOTICE("You slide \the [attacking_item] inside \the [src]."))
			playsound(get_turf(src), 'sound/items/Deconstruct.ogg', 50, 1)
			interact(user)
			return TRUE

	else if(attacking_item.tool_behaviour == TOOL_WRENCH && can_anchor)
		attacking_item.play_tool_sound(get_turf(src), 50)
		anchored = !anchored
		if(anchored)
			on_anchored()
		else
			on_unanchored()
		user.visible_message("[user] has wrenched [src]'s anchoring bolts [anchored ? "into" : "out of"] place.", "You wrench [src]'s anchoring bolts [anchored ? "into" : "out of"] place.", "You hear the sound of a ratcheting wrench turning.")
		return TRUE

	else if(attacking_item.tool_behaviour == TOOL_CROWBAR)
		attacking_item.play_tool_sound(get_turf(src), 50)
		opened = !opened
		to_chat(user, SPAN_NOTICE("You [opened ? "open" : "close"] \the [src]."))
		update_icon()
		return TRUE

	else if(istype(attacking_item, /obj/item/integrated_electronics/wirer) || istype(attacking_item, /obj/item/integrated_electronics/debugger) || attacking_item.tool_behaviour == TOOL_MULTITOOL || attacking_item.tool_behaviour == TOOL_SCREWDRIVER)
		if(opened)
			interact(user)
		else
			to_chat(user, SPAN_WARNING("\The [src] isn't open, so you can't fiddle with the internal components.  \
			Try using a crowbar."))

		return TRUE

	else if(istype(attacking_item, /obj/item/cell/device))
		if(!opened)
			to_chat(user, SPAN_WARNING("\The [src] isn't open, so you can't put anything inside.  Try using a crowbar."))
			for(var/obj/item/integrated_circuit/input/S in contents)
				S.attackby_react(attacking_item,user,user.a_intent)
			return FALSE

		if(battery)
			to_chat(user, SPAN_WARNING("\The [src] already has \a [battery] inside.  Remove it first if you want to replace it."))
			for(var/obj/item/integrated_circuit/input/S in contents)
				S.attackby_react(attacking_item,user,user.a_intent)
			return FALSE

		var/obj/item/cell/device/cell = attacking_item
		user.drop_from_inventory(cell,src)
		battery = cell
		playsound(get_turf(src), 'sound/items/Deconstruct.ogg', 50, 1)
		to_chat(user, SPAN_NOTICE("You slot \the [cell] inside \the [src]'s power supply."))
		interact(user)
		return TRUE
	else if(istype(attacking_item, /obj/item/integrated_electronics/detailer))
		var/obj/item/integrated_electronics/detailer/D = attacking_item
		detail_color = D.detail_color
		update_icon()
		return TRUE

	else
		// Reload an installed circuit's consumable in place -- bluespace crystals,
		// a gun, a grenade. Without this the only way to reload was to pop the
		// circuit out, which runs disconnect_all() and wipes all of its wiring.
		//
		// MUST come before the scanner pass below: obj_scanner's attackby_react()
		// accepts ANY atom on help intent and returns TRUE, so a reload placed
		// after it would be unreachable in any assembly containing a scanner.
		// Reload implementations type-check strictly, so they can't steal items
		// intended for a scanner or an insert_slot.
		for(var/obj/item/integrated_circuit/S in contents)
			if(S.try_reload(attacking_item, user))
				return TRUE
		for(var/obj/item/integrated_circuit/insert_slot/S in contents)  //Attempt to insert the item into any contained insert_slots
			if(S.insert(attacking_item, user))
				return TRUE
		for(var/obj/item/integrated_circuit/input/S in contents) // Attempt to swipe on scanners
			if(S.attackby_react(attacking_item,user,user.a_intent))
				return TRUE
		return ..()

/obj/item/electronic_assembly/attack_self(mob/user)
	if(!check_interactivity(user))
		return
	if(opened)
		interact(user)

	var/list/input_selection = list()
	var/list/available_inputs = list()
	for(var/obj/item/integrated_circuit/input/input in contents)
		if(input.can_be_asked_input)
			available_inputs.Add(input)
			var/i = 0
			for(var/obj/item/integrated_circuit/s in available_inputs)
				if(s.name == input.name && s.displayed_name == input.displayed_name && s != input)
					i++
			var/disp_name= "[input.displayed_name] \[[input.name]\]"
			if(i)
				disp_name += " ([i+1])"
			input_selection.Add(disp_name)

	var/obj/item/integrated_circuit/input/choice
	if(available_inputs)
		var/selection = tgui_input_list(user, "What do you want to interact with?", "Interaction", input_selection)
		if(selection)
			var/index = input_selection.Find(selection)
			choice = available_inputs[index]

	if(choice)
		choice.ask_for_input(user)

/obj/item/electronic_assembly/emp_act(severity)
	. = ..()

	for(var/atom/movable/AM in contents)
		AM.emp_act(severity)

// Returns true if power was successfully drawn.
/obj/item/electronic_assembly/proc/draw_power(amount)
	if(battery && battery.checked_use(amount * CELLRATE))
		return TRUE
	return FALSE

// Ditto for giving.
/obj/item/electronic_assembly/proc/give_power(amount)
	if(battery && battery.give(amount * CELLRATE))
		return TRUE
	return FALSE

/obj/item/electronic_assembly/proc/on_anchored()
	for(var/obj/item/integrated_circuit/IC in contents)
		IC.on_anchored()

/obj/item/electronic_assembly/proc/on_unanchored()
	for(var/obj/item/integrated_circuit/IC in contents)
		IC.on_unanchored()

// ------- Persistence -------
//
// Routes through the same generic /obj persistent_objects_get_content()/
// apply_content() passthrough persistence_mobs.dm's serializePersistentItem()/
// deserializePersistentItem() already use for any non-ID-card item (see
// their "obj_content" branch) -- no changes needed there, this is a
// self-contained override.
//
// Each integrated_circuit's own type/state is captured recursively via
// serializePersistentItem() (same as rig components), so this only needs to
// additionally capture what a fresh new() can't reconstruct: the assembly's
// own cosmetic/config vars, and the wiring graph between circuits, which is
// pure live object references (/datum/integrated_io.linked) that don't
// survive a save. Since a circuit type's inputs/outputs/activators lists are
// always rebuilt in the same fixed order (setup_io(), helpers.dm), a pin's
// identity is stable as (circuit's index in contents, which io list, index
// within that list) -- no persistent ID vars needed anywhere.
/obj/item/electronic_assembly/persistent_objects_get_content()
	var/list/content = ..()
	content["detail_color"] = detail_color
	content["opened"] = opened
	if(battery)
		content["battery"] = serializePersistentItem(battery)

	var/list/all_circuits = list()
	var/list/circuit_data = list()
	for(var/obj/item/integrated_circuit/circuit in contents)
		all_circuits += circuit
		circuit_data += list(serializePersistentItem(circuit))
	content["circuits"] = circuit_data

	// pin_data: player-set constant values (text/number/list only -- a
	// weakref'd object reference can't meaningfully survive a reboot, so
	// those pins just come back empty, same as any other dropped object ref
	// elsewhere in this persistence system).
	var/list/pin_data = list()
	// links: every (from -> to) pin pair, recorded once per direction --
	// linked is bidirectional (pins.dm's wirer/disconnect() keep both sides
	// in sync), so this naturally records each link twice; restore below is
	// idempotent (|=) so that's harmless.
	var/list/link_data = list()
	for(var/c_index = 1, c_index <= length(all_circuits), c_index++)
		var/obj/item/integrated_circuit/circuit = all_circuits[c_index]
		for(var/list_name in list("inputs", "outputs", "activators"))
			var/list/io_list = circuit.vars[list_name]
			for(var/p_index = 1, p_index <= length(io_list), p_index++)
				var/datum/integrated_io/pin = io_list[p_index]
				if(isnum(pin.data) || istext(pin.data) || islist(pin.data))
					pin_data += list(list("c" = c_index, "l" = list_name, "p" = p_index, "v" = pin.data))
				for(var/datum/integrated_io/linked_pin in pin.linked)
					var/to_c_index = all_circuits.Find(linked_pin.holder)
					if(!to_c_index)
						continue // linked to a circuit outside this assembly -- can't resolve, skip
					var/to_list_name = (linked_pin in linked_pin.holder.inputs) ? "inputs" : ((linked_pin in linked_pin.holder.outputs) ? "outputs" : "activators")
					var/to_p_index = linked_pin.holder.vars[to_list_name].Find(linked_pin)
					if(!to_p_index)
						continue
					link_data += list(list("c" = c_index, "l" = list_name, "p" = p_index, "tc" = to_c_index, "tl" = to_list_name, "tp" = to_p_index))
	content["pin_data"] = pin_data
	content["links"] = link_data
	return content

/obj/item/electronic_assembly/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	if(!isnull(content["detail_color"]))
		detail_color = content["detail_color"]
	if(!isnull(content["opened"]))
		opened = content["opened"]
	if(content["battery"])
		if(battery)
			qdel(battery)
		battery = deserializePersistentItem(content["battery"], src)

	if(!islist(content["circuits"]))
		update_icon()
		return

	// Construct the full replacement set before deleting anything already in
	// contents (a printed/pre-built assembly can arrive with circuits
	// already installed) -- same "construct before destroying" caution as
	// the rig component restore above: a failed restore should never cost
	// more than it has to.
	var/list/old_circuits = list()
	for(var/obj/item/integrated_circuit/old in contents)
		old_circuits += old

	var/list/all_circuits = list()
	for(var/list/circuit_data in content["circuits"])
		var/obj/item/integrated_circuit/restored = deserializePersistentItem(circuit_data, src)
		if(istype(restored))
			restored.assembly = src
		all_circuits += restored

	if(islist(content["pin_data"]))
		for(var/list/entry in content["pin_data"])
			var/obj/item/integrated_circuit/circuit = (entry["c"] >= 1 && entry["c"] <= length(all_circuits)) ? all_circuits[entry["c"]] : null
			if(!istype(circuit))
				continue
			var/list/io_list = circuit.vars[entry["l"]]
			if(entry["p"] >= 1 && entry["p"] <= length(io_list))
				var/datum/integrated_io/pin = io_list[entry["p"]]
				pin.data = entry["v"]

	if(islist(content["links"]))
		for(var/list/entry in content["links"])
			var/obj/item/integrated_circuit/from_circuit = (entry["c"] >= 1 && entry["c"] <= length(all_circuits)) ? all_circuits[entry["c"]] : null
			var/obj/item/integrated_circuit/to_circuit = (entry["tc"] >= 1 && entry["tc"] <= length(all_circuits)) ? all_circuits[entry["tc"]] : null
			if(!istype(from_circuit) || !istype(to_circuit))
				continue
			var/list/from_list = from_circuit.vars[entry["l"]]
			var/list/to_list = to_circuit.vars[entry["tl"]]
			if(entry["p"] < 1 || entry["p"] > length(from_list) || entry["tp"] < 1 || entry["tp"] > length(to_list))
				continue
			var/datum/integrated_io/from_pin = from_list[entry["p"]]
			var/datum/integrated_io/to_pin = to_list[entry["tp"]]
			from_pin.linked |= to_pin

	for(var/obj/item/integrated_circuit/old in old_circuits)
		qdel(old)

	update_icon()
