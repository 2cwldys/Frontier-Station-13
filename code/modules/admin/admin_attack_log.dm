/proc/log_and_message_admins(var/message as text, var/mob/user = usr, var/turf/location)
	var/turf/T = location ? location : (user ? get_turf(user) : null)
	if(T)
		message = message + " (<a href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[T.x];Y=[T.y];Z=[T.z]'>JMP</a>)"

	log_admin(user ? "[key_name(user)] [message]" : "EVENT [message]")
	message_admins(user ? "[key_name_admin(user)] [message]" : "EVENT [message]")

/proc/log_and_message_admins_many(var/list/mob/users, var/message)
	if(!users || !users.len)
		return

	var/list/user_keys = list()
	for(var/mob/user in users)
		user_keys += key_name(user)

	log_admin("[english_list(user_keys)] [message]")
	message_admins("[english_list(user_keys)] [message]")

/**
 * Log a harmful action to both parties' attack logs and admin chat, and -- in a
 * highsec zone -- escalate it to a HIGHSEC OFFENSE.
 *
 * highsec_offense: pass FALSE for actions that are logged for admin visibility but
 * are not crimes (priming a cleaner grenade, for instance). The attack-log entries
 * and admin chatter still happen; only the Hub security alert and First Responder
 * ping are suppressed.
 */
/proc/admin_attack_log(var/mob/attacker, var/mob/victim, var/attacker_message, var/victim_message, var/admin_message, var/highsec_offense = TRUE)
	var/jmp_link = ""
	if(victim)
		victim.attack_log +="\[[time_stamp()]\] <font color='orange'>[key_name(attacker)] - [victim_message]</font>"
		jmp_link = " (<A href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[victim.x];Y=[victim.y];Z=[victim.z]'>JMP</a>)"
	if(attacker)
		attacker.attack_log += "\[[time_stamp()]\] <span class='warning'>[key_name(victim)] - [attacker_message]</span>"
		jmp_link = " (<A href='byond://?_src_=holder;adminplayerobservecoodjump=1;X=[attacker.x];Y=[attacker.y];Z=[attacker.z]'>JMP</a>)"

	msg_admin_attack("[attacker ? key_name_admin(attacker) : ""] [admin_message] [victim ? key_name_admin(victim) : ""] (INTENT: [attacker? uppertext(attacker.a_intent) : "N/A"])[jmp_link]",ckey=key_name(attacker),ckey_target=key_name(victim),attack_z=(attacker ? attacker.z : (victim ? victim.z : 0)),offense_recorded=TRUE)

	// Highsec zones: combat is outlawed -- escalate unconditionally (bypasses
	// the per-admin attack-log toggle) and feed the First Responder offense
	// list. Hub-faction security personnel are exempt (they ARE the law).
	// Callers that log a non-criminal action opt out via highsec_offense = FALSE;
	// msg_admin_attack() above was already told offense_recorded = TRUE, so it
	// will not pick the escalation back up on its own.
	if(highsec_offense && (zone_security_get(attacker ? attacker.z : 0) == ZONE_HIGHSEC || zone_security_get(victim ? victim.z : 0) == ZONE_HIGHSEC))
		// Self-harm is not an offense -- it must not summon security.
		// Non-player mobs (wildlife, NPCs) can't be prosecuted and shouldn't
		// summon a response -- both sides must be actual player characters.
		if(!zone_security_exempt(attacker) && !(attacker && attacker == victim) && attacker?.ckey && (!victim || victim.ckey))
			zone_security_record_offense(attacker, victim, admin_message)
		else
			// Silent to chat by design, but auditable -- and it explains
			// "why didn't my test fire" when testing with a security char
			log_game("HIGHSEC (exempt Hub security): [key_name(attacker)] -- [admin_message] [victim ? key_name(victim) : ""]")

/proc/admin_attacker_log_many_victims(var/mob/attacker, var/list/mob/victims, var/attacker_message, var/victim_message, var/admin_message)
	if(!victims || !victims.len)
		return

	for(var/mob/victim in victims)
		admin_attack_log(attacker, victim, attacker_message, victim_message, admin_message)

/proc/admin_inject_log(mob/attacker, mob/victim, obj/item/I, reagents, temperature, amount_transferred, violent=0)
	if(violent)
		violent = "violently "
	else
		violent = ""

	var/temperature_text = "([temperature - (T0C + 20)]C)"
	admin_attack_log(
						attacker,
						victim,
						"used \the [I] to [violent]inject - [reagents] [temperature_text] - [amount_transferred]u transferred",
						"was [violent]injected with \the [I] - [reagents] [temperature_text] - [amount_transferred]u transferred",
						"used \the [I] to [violent]inject [reagents] [temperature_text] ([amount_transferred]u transferred) into"
					)
