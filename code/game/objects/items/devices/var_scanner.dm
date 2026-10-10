/**
 * Variable scanner -- debug tool. Point it at a floor tile to list that
 * turf's current vars in the existing admin "Extended List Viewer" TGUI
 * panel (view_extended_list(), viewlist.dm) -- a ready-made key/value table
 * you can select and copy text out of, so there's no need for a new UI here.
 * make_variable_list() (view_variables.dm) already knows which vars are
 * worth showing (filters out BYOND-internal noise), so this is just wiring
 * those two existing pieces together on a turf click.
 */
/obj/item/var_scanner
	name = "variable scanner"
	desc = "A debug tool. Point it at a floor tile to list its current vars."
	icon = 'icons/obj/item/multitool.dmi'
	icon_state = "multitool"
	item_state = "multitool"
	contained_sprite = TRUE
	w_class = WEIGHT_CLASS_SMALL

/obj/item/var_scanner/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	if(!proximity_flag)
		return
	if(!isturf(target))
		to_chat(user, SPAN_WARNING("\The [src] only works on floor tiles."))
		return
	if(!check_rights(R_VAREDIT|R_DEV, FALSE, user))
		to_chat(user, SPAN_WARNING("You don't have the access to use \the [src]."))
		return
	var/turf/T = target
	var/list/dump = list()
	for(var/v in T.make_variable_list())
		dump[v] = T.vars[v]
	user.client.view_extended_list(dump, T)
