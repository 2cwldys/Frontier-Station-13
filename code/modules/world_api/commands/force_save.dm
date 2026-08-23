/**
 * Triggers an immediate full persistence save over the Topic API -- built
 * for the shard idle-watchdog (scripts/central/shard_watchdog.py), which
 * has no in-game admin mob to run the "Force Persistence Save" verb with.
 * Reuses forceSaveAll() (persistence.dm), the exact same proc the periodic
 * autosave (SSpersistence.fire()) already calls -- no separate/duplicated
 * save logic.
 *
 * Deliberately NOT no_auth -- unlike get_serverstatus (a read), this is a
 * write action that blocks joining/drydock while it runs, so it must never
 * be publicly callable. Requires a real ss13_api_tokens entry scoped to
 * this exact command (see check_auth(), api_command.dm) -- each shard gets
 * its own token, provisioned by db_central_add_shard.ps1/.sh at creation.
 *
 * Starts the save and returns immediately (INVOKE_ASYNC) rather than
 * blocking the Topic response for the several seconds a full save takes --
 * the caller polls get_serverstatus's existing "saving"/"saved_ago" fields
 * to know when it's actually done, same as any other external tool
 * already does to detect a save in progress.
 */
/datum/topic_command/force_persistence_save
	name = "force_persistence_save"
	description = "Triggers an immediate full persistence save. Requires an API token authorized for this specific command."
	params = list()

/datum/topic_command/force_persistence_save/run_command(queryparams)
	if(!GLOB.config.sql_enabled)
		statuscode = 400
		response = "SQL not enabled on this server."
		return TRUE

	if(SSpersistence.save_in_progress)
		statuscode = 409
		response = "A save is already in progress."
		return TRUE

	// Same deferral fire()/the admin verb both use -- a stash/retrieve
	// mid-flight is a multi-second window where finalizing that scope
	// concurrently would interleave two save passes over it.
	if(GLOB.drydock_op_active || length(GLOB.drydock_op_queue))
		statuscode = 409
		response = "A ship stash/retrieve is in progress -- try again shortly."
		return TRUE

	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(_topic_force_persistence_save))

	statuscode = 202
	response = "Save started."
	return TRUE

/// Split out from run_command() so the try/catch + flag bookkeeping isn't
/// sitting inside a proc that already returned its Topic response by the
/// time this actually runs. Mirrors the admin verb's own
/// try/finally-shaped flag handling (persistence.dm force_persistence_save()).
/proc/_topic_force_persistence_save()
	set waitfor = FALSE
	SSpersistence.save_in_progress = TRUE
	log_and_message_admins("EVENT persistence save triggered via API token (shard watchdog or similar).")
	try
		SSpersistence.forceSaveAll()
	catch(var/exception/e)
		log_subsystem_persistence_panic("Unhandled exception during API-triggered persistence save: [e]")
	SSpersistence.save_in_progress = FALSE
	SSpersistence.last_save_completed = world.realtime
	SSpersistence._drydockProcessNextQueued()
