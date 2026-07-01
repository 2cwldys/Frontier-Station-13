#define NOBAN  0
#define AGEBAN 1
#define RANBAN 2

/datum/category_item/player_setup_item/antagonism/candidacy
	name = "Candidacy"
	sort_order = 1

/datum/category_item/player_setup_item/antagonism/candidacy/load_character(var/savefile/S)
	S["be_special"]	>> pref.be_special_role

/datum/category_item/player_setup_item/antagonism/candidacy/save_character(var/savefile/S)
	S["be_special"]	<< pref.be_special_role

/datum/category_item/player_setup_item/antagonism/candidacy/gather_load_query()
	return list("ss13_characters" = list("vars" = list("be_special_role"), "args" = list("id")))

/datum/category_item/player_setup_item/antagonism/candidacy/gather_load_parameters()
	return list("id" = pref.current_character)

/datum/category_item/player_setup_item/antagonism/candidacy/gather_save_query()
	return list("ss13_characters" = list("be_special_role", "id" = 1, "ckey" = 1))

/datum/category_item/player_setup_item/antagonism/candidacy/gather_save_parameters()
	return list("be_special_role" = list2params(pref.be_special_role), "id" = pref.current_character, "ckey" = PREF_CLIENT_CKEY)

/datum/category_item/player_setup_item/antagonism/candidacy/sanitize_character(var/sql_load = 0)
	if (sql_load)
		if (istext(pref.be_special_role))
			pref.be_special_role = params2list(pref.be_special_role)

	if (!istype(pref.be_special_role))
		pref.be_special_role = list()

	for (var/role in pref.be_special_role)
		if (!(role in valid_special_roles()))
			pref.be_special_role -= role

/datum/category_item/player_setup_item/antagonism/candidacy/content(var/mob/user)
	return "<center><br><b>Roles are disabled on this server.</b></center>"


/datum/category_item/player_setup_item/antagonism/candidacy/OnTopic(var/href,var/list/href_list, var/mob/user)
	if(href_list["add_special"])
		if(!(href_list["add_special"] in valid_special_roles()))
			return TOPIC_HANDLED
		pref.be_special_role |= href_list["add_special"]
		return TOPIC_REFRESH

	if(href_list["del_special"])
		pref.be_special_role -= href_list["del_special"]
		return TOPIC_REFRESH

	return ..()

/datum/category_item/player_setup_item/antagonism/candidacy/proc/valid_special_roles()
	var/list/private_valid_special_roles = list()
	for(var/antag_type in GLOB.all_antag_types)
		var/datum/antagonist/antag = GLOB.all_antag_types[antag_type]
		private_valid_special_roles += antag.role_type

	return private_valid_special_roles

#undef AGEBAN
#undef RANBAN
#undef NOBAN
