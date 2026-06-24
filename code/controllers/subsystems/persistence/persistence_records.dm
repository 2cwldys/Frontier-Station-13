/*
 * Persistence - Crew Records
 * Saves and restores crew record data (criminal status, CCIA notes, medical/security notes)
 * across rounds via SQL. Character appearance and employment data is already saved in
 * ss13_characters; this file covers in-round record changes only.
 *
 * Hooked into SSpersistence Initialize() and Shutdown(), and SSrecords.build_records().
 */

/// Cached record data loaded at round start, keyed by "[ckey]|[char_name]"
GLOBAL_LIST_EMPTY(persistence_records_cache)

/**
 * Load saved crew record data from the database into the in-memory cache.
 * Called from SSpersistence.Initialize() before build_records() runs.
 */
/datum/controller/subsystem/persistence/proc/recordsInitialize()
	PRIVATE_PROC(TRUE)
	GLOB.persistence_records_cache = list()

	if(!databaseCheckConnection("recordsInitialize"))
		return

	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT ckey, char_name, rank, criminal_status, crimes, ccia_notes, medical_notes, security_notes, fingerprint, blood_dna \
		 FROM ss13_crew_records"
	)
	query.Execute()

	if(!databaseCheckQueryResult(query, "recordsInitialize"))
		qdel(query)
		return

	var/loaded = 0
	while(query.NextRow())
		var/list/entry = list(
			"ckey"           = query.item[1],
			"char_name"      = query.item[2],
			"rank"           = query.item[3],
			"criminal"       = query.item[4],
			"crimes"         = query.item[5],
			"ccia_notes"     = query.item[6],
			"medical_notes"  = query.item[7],
			"security_notes" = query.item[8],
			"fingerprint"    = query.item[9],
			"blood_dna"      = query.item[10]
		)
		var/cache_key = "[query.item[1]]|[query.item[2]]"
		GLOB.persistence_records_cache[cache_key] = entry
		loaded++

	qdel(query)
	log_subsystem_persistence_info("Records: Loaded [loaded] saved crew records.")

/**
 * Apply persistent record data on top of a freshly generated record.
 * Called from SSrecords.generate_record() after the record is created.
 */
/datum/controller/subsystem/records/proc/applyPersistentRecordData(var/datum/record/general/record, var/ckey)
	if(!GLOB.config.sql_enabled || !GLOB.persistence_records_cache)
		return

	var/cache_key = "[ckey]|[record.name]"
	var/list/saved = GLOB.persistence_records_cache[cache_key]
	if(!saved)
		return

	if(saved["criminal"] && saved["criminal"] != "None")
		record.security.criminal = saved["criminal"]
	if(saved["crimes"] && saved["crimes"] != "No criminal record.")
		record.security.crimes = saved["crimes"]
	if(saved["ccia_notes"] && saved["ccia_notes"] != "No CCIA records found")
		record.ccia_record = saved["ccia_notes"]
	if(saved["medical_notes"] && saved["medical_notes"] != "No notes found.")
		record.medical.notes = saved["medical_notes"]
	if(saved["security_notes"] && saved["security_notes"] != "No notes found.")
		record.security.notes = saved["security_notes"]
	if(saved["fingerprint"] && saved["fingerprint"] != "Unknown")
		record.fingerprint = saved["fingerprint"]
	if(saved["blood_dna"] && record.medical)
		record.medical.blood_dna = saved["blood_dna"]

	log_subsystem_persistence_info("Records: Applied persistent data for [ckey] ([record.name]): criminal=[saved["criminal"]]")

/**
 * Save all player crew records to the database.
 * Called from SSpersistence.Shutdown() at round end.
 */
/datum/controller/subsystem/persistence/proc/recordsFinalize()
	PRIVATE_PROC(TRUE)

	if(!databaseCheckConnection("recordsFinalize"))
		return

	var/saved = 0
	for(var/datum/record/general/record in SSrecords.records)
		CHECK_TICK
		// Only save records that have a ckey (player records, not NPC/ghost records)
		if(!record.ckey)
			continue

		var/datum/db_query/upsert = SSdbcore.NewQuery(
			"INSERT INTO ss13_crew_records \
			 (ckey, char_name, rank, fingerprint, blood_dna, criminal_status, crimes, ccia_notes, medical_notes, security_notes, saved_at) \
			 VALUES (:ckey, :char_name, :rank, :fingerprint, :blood_dna, :criminal, :crimes, :ccia_notes, :medical_notes, :security_notes, NOW()) \
			 ON DUPLICATE KEY UPDATE \
			 rank=VALUES(rank), fingerprint=VALUES(fingerprint), blood_dna=VALUES(blood_dna), \
			 criminal_status=VALUES(criminal_status), crimes=VALUES(crimes), \
			 ccia_notes=VALUES(ccia_notes), medical_notes=VALUES(medical_notes), \
			 security_notes=VALUES(security_notes), saved_at=NOW()",
			list(
				"ckey"           = record.ckey,
				"char_name"      = record.name,
				"rank"           = record.rank,
				"fingerprint"    = record.fingerprint,
				"blood_dna"      = record.medical ? record.medical.blood_dna : null,
				"criminal"       = record.security ? record.security.criminal : "None",
				"crimes"         = record.security ? record.security.crimes : "No criminal record.",
				"ccia_notes"     = record.ccia_record,
				"medical_notes"  = record.medical ? record.medical.notes : "No notes found.",
				"security_notes" = record.security ? record.security.notes : "No notes found."
			)
		)
		upsert.Execute()
		databaseCheckQueryResult(upsert, "recordsFinalize upsert for [record.ckey]/[record.name]")
		qdel(upsert)
		saved++

	log_subsystem_persistence_info("Records: Saved [saved] crew records.")
