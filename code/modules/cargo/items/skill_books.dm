/*
 * Skill manuals -- one cargo entry per discipline, so a crate contains exactly
 * the skill that was paid for. The books themselves (and the reasons some
 * skills are deliberately not offered) live in
 * code/modules/library/skill_manual.dm.
 *
 * Priced far above the language primers on purpose. Everyone starts Trained;
 * these are the only way to reach Professional WITHOUT an already-qualified
 * teacher, which makes them the bootstrap for seeding a discipline into the
 * server population. The price is the brake on the whole progression economy --
 * teaching is meant to be the ordinary route, and this the expensive shortcut.
 */

/// Abstract for the same reason the language primer parent is -- see the note
/// there (language_books.dm). An instantiated parent registers itself into the
/// catalogue under "generic cargo item" with nothing in it.
ABSTRACT_TYPE(/singleton/cargo_item/skill_manual)
/singleton/cargo_item/skill_manual
	category = "science"
	supplier = "Hub"
	price = 150000
	access = 0
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

// ---- Everyday ----

/singleton/cargo_item/skill_manual/bartending
	name = "skill manual - Bartending"
	description = "A professional-certification manual in bartending. Covers everything from stock rotation to the sort of customer who does not know when to leave."
	items = list(/obj/item/book/skill_manual/bartending)

/singleton/cargo_item/skill_manual/cooking
	name = "skill manual - Cooking"
	description = "A professional-certification manual in commercial cookery, from knife work to running a service without setting anything alight."
	items = list(/obj/item/book/skill_manual/cooking)

/singleton/cargo_item/skill_manual/gardening
	name = "skill manual - Gardening"
	description = "A professional-certification manual in horticulture, covering soil chemistry, grafting and yield management."
	items = list(/obj/item/book/skill_manual/gardening)

/singleton/cargo_item/skill_manual/carousing
	name = "skill manual - Carousing"
	description = "A professional-certification manual in, generously, social endurance. It is mostly about pacing."
	items = list(/obj/item/book/skill_manual/carousing)

/singleton/cargo_item/skill_manual/ministry
	name = "skill manual - Ministry"
	description = "A professional-certification manual in pastoral care and comparative rites."
	items = list(/obj/item/book/skill_manual/ministry)

// ---- Combat ----

/singleton/cargo_item/skill_manual/leadership
	name = "skill manual - Leadership"
	description = "A professional-certification manual in command and small-unit leadership."
	items = list(/obj/item/book/skill_manual/leadership)

/singleton/cargo_item/skill_manual/tenacity
	name = "skill manual - Tenacity"
	description = "A professional-certification manual in stress conditioning and pain management."
	items = list(/obj/item/book/skill_manual/tenacity)

// ---- Engineering ----

/singleton/cargo_item/skill_manual/electrical_engineering
	name = "skill manual - Electrical Engineering"
	description = "A professional-certification manual in electrical engineering, covering distribution, wiring standards and fault tracing."
	items = list(/obj/item/book/skill_manual/electrical_engineering)

/singleton/cargo_item/skill_manual/mechanical_engineering
	name = "skill manual - Mechanical Engineering"
	description = "A professional-certification manual in mechanical engineering, from fabrication tolerances to structural repair."
	items = list(/obj/item/book/skill_manual/mechanical_engineering)

/singleton/cargo_item/skill_manual/atmospherics_systems
	name = "skill manual - Atmospherics Systems"
	description = "A professional-certification manual in atmospherics, covering distribution loops, scrubber tuning and emergency venting."
	items = list(/obj/item/book/skill_manual/atmospherics_systems)

/singleton/cargo_item/skill_manual/reactor_systems
	name = "skill manual - Reactor Systems"
	description = "A professional-certification manual in reactor operation. The safety chapters are longer than the rest combined."
	items = list(/obj/item/book/skill_manual/reactor_systems)

// ---- Medical ----

/singleton/cargo_item/skill_manual/medicine
	name = "skill manual - Medicine"
	description = "A professional-certification manual in clinical medicine, covering diagnosis, treatment and equipment handling."
	items = list(/obj/item/book/skill_manual/medicine)

/singleton/cargo_item/skill_manual/surgery
	name = "skill manual - Surgery"
	description = "A professional-certification manual in surgical practice. Extensively illustrated, to the regret of most readers."
	items = list(/obj/item/book/skill_manual/surgery)

/singleton/cargo_item/skill_manual/pharmacology
	name = "skill manual - Pharmacology"
	description = "A professional-certification manual in pharmacology, covering synthesis, dosage and interaction."
	items = list(/obj/item/book/skill_manual/pharmacology)

/singleton/cargo_item/skill_manual/anatomy
	name = "skill manual - Anatomy"
	description = "A professional-certification manual in comparative anatomy across the common species."
	items = list(/obj/item/book/skill_manual/anatomy)

/singleton/cargo_item/skill_manual/forensics
	name = "skill manual - Forensics"
	description = "A professional-certification manual in forensic method, from scene handling to trace analysis."
	items = list(/obj/item/book/skill_manual/forensics)

// ---- Operations ----

/singleton/cargo_item/skill_manual/robotics
	name = "skill manual - Robotics"
	description = "A professional-certification manual in robotics, covering chassis assembly, servo calibration and positronic handling."
	items = list(/obj/item/book/skill_manual/robotics)

/singleton/cargo_item/skill_manual/pilot_spacecraft
	name = "skill manual - Spacecraft Piloting"
	description = "A professional-certification manual in spacecraft handling, navigation and docking procedure."
	items = list(/obj/item/book/skill_manual/pilot_spacecraft)

// ---- Science ----

/singleton/cargo_item/skill_manual/research
	name = "skill manual - Research"
	description = "A professional-certification manual in research methodology and laboratory practice."
	items = list(/obj/item/book/skill_manual/research)

/singleton/cargo_item/skill_manual/xenobotany
	name = "skill manual - Xenobotany"
	description = "A professional-certification manual in xenobotany, covering cultivation and containment of non-terrestrial flora."
	items = list(/obj/item/book/skill_manual/xenobotany)

/singleton/cargo_item/skill_manual/archaeology
	name = "skill manual - Archaeology"
	description = "A professional-certification manual in field archaeology, covering excavation, dating and artefact handling."
	items = list(/obj/item/book/skill_manual/archaeology)

/singleton/cargo_item/skill_manual/xenobiology
	name = "skill manual - Xenobiology"
	description = "A professional-certification manual in xenobiology. The containment chapter is heavily annotated by previous owners."
	items = list(/obj/item/book/skill_manual/xenobiology)
