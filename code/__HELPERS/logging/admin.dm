/* Items with ADMINPRIVATE prefixed are stripped from public logs. */

/// General logging for admin actions
/proc/log_admin(text)
	GLOB.admin_log.Add(text)
	if (GLOB.config.logsettings["log_admin"])
		WRITE_LOG(GLOB.config.logfiles["world_game_log"], "ADMIN: [text]")
#ifdef EXPORT_ADMIN_LOG_TO_DISCORD
	// GLOB.admin_log/the world log file/the in-game log viewer all want the
	// original HTML (JMP links, SPAN_* color tags) intact -- only strip it
	// for the Discord copy, which can't render any of that and would
	// otherwise show the raw <a href='...'>JMP</a> markup as literal text.
	// strip_html_properly() (text.dm) removes just the tag markup and keeps
	// the inner text (e.g. "JMP"), unlike strip_html_full()/STRIP_HTML_FULL
	// which re-encodes the result back into HTML entities afterward.
	SSdiscord.post_webhook_event(WEBHOOK_ADMIN_LOG, list("message" = SSdiscord.discord_escape(strip_html_properly(text))))
#endif

/**
 * Mirrors a security event to the law-enforcement Discord channel
 * (WEBHOOK_LAW_ENFORCEMENT, __DEFINES/webhook.dm).
 *
 * Deliberately separate from log_admin()'s admin_log mirror: this carries the
 * things a security team actually acts on -- highsec offenses and distress
 * calls as they hit responders' PDAs, plus First Responder enforcement
 * actions -- without handing that channel the entire admin log. Callers do
 * their own message_admins()/log_admin() as before; this only adds a
 * destination.
 *
 * Free when unconfigured: post_webhook_event() only delivers to webhooks
 * explicitly carrying the tag (discord.dm), so with no "law_enforcement"
 * webhook set up this is a no-op. Text is stripped/escaped the same way the
 * admin-log mirror above does it, since Discord can't render the SPAN_ colour
 * tags or JMP links these strings carry.
 *
 * category is an OPTIONAL short label ("Highsec offense", "Distress call")
 * rendered as a bold heading in front of the message. It exists because
 * discord_escape() escapes "*" -- so markdown written into `text` by a caller
 * arrives as literal \*\*asterisks\*\* rather than bold. Escaping `text` is
 * not negotiable (it carries player-supplied character names, area names and
 * admin sentences), so the emphasis is applied AFTER escaping instead, and
 * only around this trusted caller-supplied label.
 */
/proc/log_law_enforcement(text, category)
#ifdef EXPORT_LAW_ENFORCEMENT_TO_DISCORD
	var/body = SSdiscord.discord_escape(strip_html_properly(text))
	if(category)
		// The ** is deliberately outside discord_escape() -- see above.
		body = "**[SSdiscord.discord_escape(category)]** -- [body]"
	SSdiscord.post_webhook_event(WEBHOOK_LAW_ENFORCEMENT, list("message" = body))
#endif
	return

/// Logging for admin actions on or with circuits
/proc/log_admin_circuit(text)
	GLOB.admin_log.Add(text)
	if(GLOB.config.logsettings["log_admin"])
		WRITE_LOG(GLOB.config.logfiles["world_game_log"], "ADMIN: CIRCUIT: [text]")

/// General logging for admin actions
/proc/log_admin_private(text)
	GLOB.admin_log.Add(text)
	if (GLOB.config.logsettings["log_admin"])
		WRITE_LOG(GLOB.config.logfiles["world_game_log"], "ADMINPRIVATE: [text]")

/// Logging for AdminSay (ASAY) messages
/proc/log_adminsay(text)
	GLOB.admin_log.Add(text)
	if (GLOB.config.logsettings["log_adminchat"])
		WRITE_LOG(GLOB.config.logfiles["world_game_log"], "ADMINPRIVATE: ASAY: [text]")

/// Logging for DeachatSay (DSAY) messages
/proc/log_dsay(text)
	if (GLOB.config.logsettings["log_adminchat"])
		WRITE_LOG(GLOB.config.logfiles["world_game_log"], "ADMIN: DSAY: [text]")

/**
 * Writes to a special log file if the log_suspicious_login config flag is set,
 * which is intended to contain all logins that failed under suspicious circumstances.
 *
 * Mirrors this log entry to log_access when access_log_mirror is TRUE, so this proc
 * doesn't need to be used alongside log_access and can replace it where appropriate.
 */
/proc/log_suspicious_login(text, access_log_mirror = TRUE)
	if (GLOB.config.logsettings["log_suspicious_login"])
		WRITE_LOG(GLOB.config.logfiles["world_suspicious_login_log"], "SUSPICIOUS_ACCESS: [text]")
	if(access_log_mirror)
		log_access(text)
