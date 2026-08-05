//Insert slots allow items to be inserted into assemblies from outside
//These items can then be used by other components
/obj/item/integrated_circuit/insert_slot
	category_text = "Insert slot"
	var/capacity = 0
	var/list/allowed_types = list()
	var/list/items_contained = list()
	activators = list("eject contents" = IC_PINTYPE_PULSE_IN)
	outputs = list("has item" = IC_PINTYPE_BOOLEAN)
	power_draw_per_use = 10
	w_class = WEIGHT_CLASS_NORMAL
	size = 5
	complexity = 1

//call this function from components that want to get items from this component
//set remove to FALSE if you dont want the item removed from the component and just want a reference to it
//(e.g. for beakers)
/obj/item/integrated_circuit/insert_slot/proc/get_item(var/remove = FALSE)
	if(items_contained.len > 0)
		var/itemToReturn = items_contained[1]
		if(remove)
			items_contained -= itemToReturn
			if(items_contained.len <= 0)
				set_pin_data(IC_OUTPUT, 1, FALSE)
				push_data()
		return itemToReturn
	return null

/obj/item/integrated_circuit/insert_slot/do_work()
	for(var/obj/item/O in items_contained)
		O.forceMove(get_turf(src))
		visible_message(SPAN_NOTICE("\The [src] drops [O] on the ground."))
		items_contained -= O
	set_pin_data(IC_OUTPUT, 1, FALSE)
	push_data()
	return TRUE

/obj/item/integrated_circuit/insert_slot/proc/insert(var/obj/item/O, var/mob/user)
	if(is_type_in_list(O, allowed_types))
		if(items_contained.len >= capacity)
			to_chat(user, SPAN_WARNING("\The [src] is too full to add [O]."))
			return FALSE
		items_contained += O
		user.drop_from_inventory(O,src)
		to_chat(user, SPAN_NOTICE("You add [O] to \the [src]."))
		set_pin_data(IC_OUTPUT, 1, TRUE)
		return TRUE

// items_contained sits in `contents`, same as any inserted item, but this
// isn't a /obj/item/storage subtype -- the generic storage-contents
// recursion in serializePersistentItem() (persistence_mobs.dm) never
// reaches it without this override, so an inserted paper/beaker would
// otherwise vanish and items_contained come back empty on restore.
/obj/item/integrated_circuit/insert_slot/persistent_objects_get_content()
	var/list/content = ..()
	var/list/item_data = list()
	for(var/obj/item/O in items_contained)
		var/list/serialized = serializePersistentItem(O)
		if(serialized)
			item_data += list(serialized)
	content["slot_items"] = item_data
	return content

/obj/item/integrated_circuit/insert_slot/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content) || !islist(content["slot_items"]))
		return
	for(var/obj/item/old in items_contained)
		qdel(old)
	items_contained = list()
	for(var/list/item_entry in content["slot_items"])
		var/obj/item/restored = deserializePersistentItem(item_entry, src)
		if(restored)
			items_contained += restored
	set_pin_data(IC_OUTPUT, 1, length(items_contained) > 0)

/obj/item/integrated_circuit/insert_slot/paper_tray
	name = "paper tray"
	desc = "A simple paper tray similar to one from a printer."
	extended_desc = "A simple paper tray, paper can be inserted and used by other components. \
	Paper can be inserted through a slot in the casing. Holds 10 sheets"
	capacity = 10
	size = 8
	power_draw_per_use = 30
	allowed_types = list(/obj/item/paper)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	origin_tech = list(TECH_ENGINEERING = 2, TECH_MATERIAL = 2)

/obj/item/integrated_circuit/insert_slot/beaker_holder
	name = "beaker holder"
	desc = "A slot for holding a beaker"
	extended_desc = "A slot for holding a beaker with reagents. \
	It has a bracket to hold the beaker in place and a lid to prevent spillage. \
	There is an extraction tube built into the lid"
	capacity = 1
	allowed_types = list(/obj/item/reagent_containers/glass/beaker)
	spawn_flags = IC_SPAWN_DEFAULT|IC_SPAWN_RESEARCH
	origin_tech = list(TECH_ENGINEERING = 2, TECH_BIO = 2, TECH_MATERIAL = 2)
