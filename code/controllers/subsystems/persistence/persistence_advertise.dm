/*
 * Persistence - Advertise To Players
 *
 * "Advertise to Players" admin verb: pings the Discord that a session is
 * running and could use more people, naming the admin asking and the current
 * player count.
 *
 * This verb does NOT post to Discord itself, and cannot. DM has no bot token,
 * so SSdiscord can only post to webhook URLs -- never to a channel ID. The
 * channel this lands in (milestone_channel_id, config/discord_status_bot.json)
 * belongs to the Python status bot, which is the only side holding a token.
 *
 * So the verb records a pending advert and the bot posts it on its next poll,
 * reusing the channel and credentials already working for milestone
 * announcements -- no new Discord setup at all. get_serverstatus
 * (server_query.dm) is the handoff.
 *
 * The consequence, which the verb tells the admin rather than hiding: if the
 * bot is not running, nothing is posted.
 */

/// Unique per advert, "" when none is pending. The bot posts an id it has not
/// posted before, so this doubles as the de-duplication key.
GLOBAL_VAR_INIT(advert_id, "")
/// Who asked -- ckey, since a Discord audience recognises that, not a
/// character name.
GLOBAL_VAR_INIT(advert_by, "")
/// Player count captured WHEN THE VERB RAN, so the embed reports what the
/// admin actually saw rather than whatever it happens to be when the bot
/// next polls.
GLOBAL_VAR_INIT(advert_players, 0)
/// world.time after which a pending advert stops being offered. Without this a
/// pending advert could sit around and be posted by a bot that starts much
/// later, long after it stopped being true.
GLOBAL_VAR_INIT(advert_expires_at, 0)
/// world.time of the last advert, for the shared cooldown.
GLOBAL_VAR_INIT(advert_last_sent, 0)

/// Minutes between adverts, from config. Clamped at 0 (no cooldown).
/proc/_advertise_cooldown_minutes()
	return max(0, GLOB.config?.advertise_cooldown_minutes || 0)

/// TRUE while a pending advert is still worth offering to the bot.
/proc/advert_pending()
	return GLOB.advert_id && world.time < GLOB.advert_expires_at

/datum/admins/proc/advertise_to_players()
	set name = "Advertise to Players"
	set category = "Persistence.Misc"
	set desc = "Pings the Discord that the server could use more players."

	if(!check_rights(R_ADMIN))
		return

	// Cooldown BEFORE the prompt. Asking someone to confirm and only then
	// telling them they were never allowed is a rude order to do things in.
	var/cooldown = _advertise_cooldown_minutes()
	if(cooldown && GLOB.advert_last_sent)
		var/ready_at = GLOB.advert_last_sent + (cooldown MINUTES)
		if(world.time < ready_at)
			var/mins_left = CEILING((ready_at - world.time) / (1 MINUTES), 1)
			to_chat(usr, SPAN_WARNING("Advertising is on cooldown -- [mins_left] minute\s left. (ADVERTISE_COOLDOWN_MINUTES is [cooldown].)"))
			return

	var/players = GLOB.clients.len

	// An @here reaches everyone currently on that Discord. That is not
	// something to fire on a misclick, so state exactly what will be sent.
	if(tgui_alert(usr, "Post to Discord that the server needs players? This pings @here.\n\nIt will say: \"[usr.ckey] is looking for more players -- [players] online right now.\"", "Advertise to Players", list("Post It", "Cancel")) != "Post It")
		return

	GLOB.advert_id = "[GLOB.round_id]-[world.time]"
	GLOB.advert_by = usr.ckey
	GLOB.advert_players = players
	GLOB.advert_expires_at = world.time + 2 MINUTES
	GLOB.advert_last_sent = world.time

	// Delivery depends on the bot being alive to see it. Say so plainly --
	// reporting an unqualified success for something that may never leave the
	// building would be worse than not having the verb.
	to_chat(usr, SPAN_NOTICE("Advert queued. The status bot will post it to Discord within its next poll (usually a few seconds). If the bot is not running, nothing will be posted."))
	log_and_message_admins("queued a Discord advert for more players ([players] online).", usr)
