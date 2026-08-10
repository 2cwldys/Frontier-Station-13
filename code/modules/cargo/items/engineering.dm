// ---- Shuttle Construction ----

/singleton/cargo_item/ntnet_relay
	category = "engineering"
	name = "NTNet quantum relay"
	supplier = "Hub"
	description = "A quantum relay for NTNet coverage. Wrench to secure after placement. At least one powered, undamaged relay must exist for any NTNet-dependent PDA or console program to function."
	price = 25000
	items = list(
		/obj/structure/machinery/ntnet_relay/crate
	)
	access = 0
	container_type = "crate"

/singleton/cargo_item/drydock_boarding_pad
	category = "engineering"
	name = "drydock boarding pad"
	supplier = "Hub"
	description = "Boards you onto one of your currently deployed drydock ships, at its navigation console. A retrieved ship has no walkable connection to anywhere -- this is the only way aboard (disembarking, once docked at a beacon, is a verb usable from anywhere on the ship, no pad needed)."
	price = 1500
	items = list(
		/obj/structure/machinery/telepad_cargo/drydock_boarding
	)
	access = 0
	container_type = "crate"

// ---- End Shuttle Construction ----

/singleton/cargo_item/travel_pad
	category = "engineering"
	name = "travel pad"
	supplier = "Hub"
	description = "A tuned telepad that links to any other travel pad sharing its access code, letting you step directly between them. Click it after placement to set an access code -- no faction or officer access needed."
	price = 1500
	items = list(
		/obj/structure/machinery/telepad_cargo/travel
	)
	access = 0
	container_type = "crate"
	groupable = TRUE

/singleton/cargo_item/umbilical_pad
	category = "engineering"
	name = "umbilical pad"
	supplier = "Hub"
	description = "A tuned telepad that opens a standing, walk-through bluespace conduit to any other umbilical pad sharing its access code -- ideal for a permanent docked-ship-to-mooring connection. Wrench to secure after placement, then click it to set an access code -- no faction or officer access needed."
	price = 1500
	items = list(
		/obj/structure/machinery/telepad_cargo/umbilical
	)
	access = 0
	container_type = "crate"
	groupable = TRUE

/singleton/cargo_item/glasssheets
	category = "engineering"
	name = "glass sheets"
	supplier = "Hub"
	description = "50 sheets of glass."
	price = 55
	items = list(
		/obj/item/stack/material/glass/full
	)
	access = 0
	container_type = "crate"
	groupable = TRUE

/singleton/cargo_item/plasteelsheets
	category = "engineering"
	name = "plasteel sheets"
	supplier = "Hub"
	description = "50 sheets of plasteel."
	price = 120
	items = list(
		/obj/item/stack/material/plasteel/full
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/plasticsheets
	category = "engineering"
	name = "plastic sheets"
	supplier = "Hub"
	description = "50 sheets of plastic."
	price = 45
	items = list(
		/obj/item/stack/material/plastic/full
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/steelsheets
	category = "engineering"
	name = "steel sheets"
	supplier = "Hub"
	description = "50 sheets of steel."
	price = 75
	items = list(
		/obj/item/stack/material/steel/full
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/woodplanks
	category = "engineering"
	name = "wood planks"
	supplier = "Hub"
	description = "50 planks of wood."
	price = 65
	items = list(
		/obj/item/stack/material/wood/full
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/phoronsheets
	category = "engineering"
	name = "phoron crystals"
	supplier = "Hub"
	description = "A bunch of 50 phoron crystals. Highly valuable."
	price = 2250
	items = list(
		/obj/item/stack/material/phoron/full
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE

/singleton/cargo_item/cardboardsheets
	category = "engineering"
	name = "cardboard sheets"
	supplier = "Hub"
	description = "50 sheets of cardboard."
	price = 10
	items = list(
		/obj/item/stack/material/cardboard/full
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/carpet
	category = "engineering"
	name = "carpet (x10)"
	supplier = "Hub"
	description = "Ten carpet sheets. It is the same size as a normal floor tile!"
	price = 60
	items = list(
		/obj/item/stack/tile/carpet
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 10

/singleton/cargo_item/antifuelgrenade
	category = "engineering"
	name = "antifuel grenade"
	supplier = "Hub"
	description = "This grenade is loaded with a foaming antifuel compound -- the twenty-fifth century standard for eliminating industrial spills."
	price = 45
	items = list(
		/obj/item/grenade/chem_grenade/antifuel
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/brownwebbingvest
	category = "engineering"
	name = "brown webbing vest"
	supplier = "Hub"
	description = "Worn brownish synthcotton vest with lots of pockets to unload your hands."
	price = 15
	items = list(
		/obj/item/clothing/accessory/storage/brown_vest
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/circuitboard_bubbleshield
	category = "engineering"
	name = T_BOARD("bubble shield generator")
	supplier = "Hub"
	description = "Looks like a circuit. Probably is."
	price = 250
	items = list(
		/obj/item/circuitboard/shield_gen
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/circuitboard_hullshield
	category = "engineering"
	name = T_BOARD("hull shield generator")
	supplier = "Hub"
	description = "Looks like a circuit. Probably is."
	price = 250
	items = list(
		/obj/item/circuitboard/shield_gen_ex
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/circuitboard_shieldcapacitor
	category = "engineering"
	name = T_BOARD("shield capacitor")
	supplier = "Hub"
	description = "Looks like a circuit. Probably is."
	price = 250
	items = list(
		/obj/item/circuitboard/shield_cap
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/circuitboard_solarcontrol
	category = "engineering"
	name = T_BOARD("solar control console")
	supplier = "Hub"
	description = "Looks like a circuit. Probably is."
	price = 250
	items = list(
		/obj/item/circuitboard/solar_control
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/coolanttank
	category = "engineering"
	name = "coolant tank"
	supplier = "Hub"
	description = "A tank of industrial coolant."
	price = 10
	items = list(
		/obj/structure/reagent_dispensers/coolanttank
	)
	access = ACCESS_ENGINE
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/disposalpipedispenser
	category = "engineering"
	name = "Disposal Pipe Dispenser"
	supplier = "Hub"
	description = "It dispenses bigger pipes for things to travel through. No, the pipes aren't green."
	price = 30
	items = list(
		/obj/structure/machinery/pipedispenser/disposal/orderable
	)
	access = ACCESS_ENGINE
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/toolbox
	category = "engineering"
	name = "mechanical toolbox"
	supplier = "Hub"
	description = "Danger. Very robust."
	price = 45
	items = list(
		/obj/item/storage/toolbox/mechanical
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/electricaltoolbox
	category = "engineering"
	name = "electrical toolbox"
	supplier = "Hub"
	description = "Danger. Very robust."
	price = 45
	items = list(
		/obj/item/storage/toolbox/electrical
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/emergencytoolbox
	category = "engineering"
	name = "emergency toolbox"
	supplier = "Hub"
	description = "Danger. Very robust."
	price = 42
	items = list(
		/obj/item/storage/toolbox/emergency
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/emaccelerationchamber
	category = "engineering"
	name = "EM Acceleration Chamber"
	supplier = "Hub"
	description = "Part of a Particle Accelerator."
	price = 1550
	items = list(
		/obj/structure/particle_accelerator/fuel_chamber
	)
	access = ACCESS_CE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/emcontainmentgridcenter
	category = "engineering"
	name = "EM Containment Grid Center"
	supplier = "Hub"
	description = "Part of a Particle Accelerator."
	price = 1550
	items = list(
		/obj/structure/particle_accelerator/particle_emitter/center
	)
	access = ACCESS_CE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/emcontainmentgridleft
	category = "engineering"
	name = "EM Containment Grid Left"
	supplier = "Hub"
	description = "Part of a Particle Accelerator."
	price = 1550
	items = list(
		/obj/structure/particle_accelerator/particle_emitter/left
	)
	access = ACCESS_CE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/emcontainmentgridright
	category = "engineering"
	name = "EM Containment Grid Right"
	supplier = "Hub"
	description = "Part of a Particle Accelerator."
	price = 1550
	items = list(
		/obj/structure/particle_accelerator/particle_emitter/right
	)
	access = ACCESS_CE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/emergencybluespacerelaycircuit
	category = "engineering"
	name = "emergency bluespace relay circuit"
	supplier = "Hub"
	description = "Looks like a circuit. Probably is."
	price = 620
	items = list(
		/obj/item/circuitboard/bluespacerelay
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/emitter
	category = "engineering"
	name = "emitter"
	supplier = "Hub"
	description = "It is a heavy duty industrial laser."
	price = 1850
	items = list(
		/obj/structure/machinery/power/emitter
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/doorlock_engineering
	category = "engineering"
	name = "magnetic door lock - engineering"
	supplier = "Hub"
	description = "A large, ID locked device used for completely locking down airlocks. It is painted with Engineering colors."
	price = 48
	items = list(
		/obj/item/magnetic_lock/engineering
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/engineeringvoidsuit
	category = "engineering"
	name = "engineering voidsuit"
	supplier = "Hub"
	description = "A special suit that protects against hazardous, low pressure environments. Has radiation shielding."
	price = 800
	items = list(
		/obj/item/clothing/suit/space/void/engineering
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/engineeringvoidsuithelmet
	category = "engineering"
	name = "engineering voidsuit helmet"
	supplier = "Hub"
	description = "A special helmet designed for work in a hazardous, low-pressure environment. Has radiation shielding."
	price = 500
	items = list(
		/obj/item/clothing/head/helmet/space/void/engineering
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/fieldgenerator
	category = "engineering"
	name = "Field Generator"
	supplier = "Hub"
	description = "A large thermal battery that projects a high amount of energy when powered."
	price = 250
	items = list(
		/obj/structure/machinery/field_generator
	)
	access = ACCESS_ARMORY
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/fireaxe
	category = "engineering"
	name = "fireaxe"
	supplier = "Hub"
	description = "The fire axe is a wooden handled axe with a heavy steel head intended for firefighting use."
	price = 25
	items = list(
		/obj/item/material/twohanded/fireaxe
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/fueltank
	category = "engineering"
	name = "fuel tank"
	supplier = "Hub"
	description = "A tank filled with welding fuel."
	price = 500
	items = list(
		/obj/structure/reagent_dispensers/fueltank
	)
	access = ACCESS_ENGINE
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/gasmask
	category = "engineering"
	name = "gas mask"
	supplier = "Hub"
	description = "A face-covering mask that can be connected to an air supply. Filters harmful gases from the air."
	price = 15
	items = list(
		/obj/item/clothing/mask/gas
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

	spawn_amount = 1

/singleton/cargo_item/hardhat
	category = "engineering"
	name = "hard hat"
	supplier = "Hub"
	description = "A piece of headgear used in dangerous working conditions to protect the head. Comes with a built-in flashlight."
	price = 7
	items = list(
		/obj/item/clothing/head/hardhat
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/hazardvest
	category = "engineering"
	name = "hazard vest"
	supplier = "Hub"
	description = "A high-visibility vest used in work zones."
	price = 5
	items = list(
		/obj/item/clothing/suit/storage/hazardvest
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/toolbelt
	category = "engineering"
	name = "full toolbelt"
	supplier = "Hub"
	description = "A toolbelt, filled with basic mechanics' tools."
	price = 80
	items = list(
		/obj/item/storage/belt/utility/full
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/highcapacitypowercell
	category = "engineering"
	name = "high-capacity power cell"
	supplier = "Hub"
	description = "A high-capacity rechargable electrochemical power cell."
	price = 45
	items = list(
		/obj/item/cell/high
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/infinitepowercell
	category = "engineering"
	name = "infinite-capacity power cell"
	supplier = "Hub"
	description = "A theoretically impossible power cell that never depletes. Use with extreme discretion."
	price = 50000
	items = list(
		/obj/item/cell/infinite
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/powercell
	category = "engineering"
	name = "power cell"
	supplier = "Hub"
	description = "A rechargable electrochemical power cell."
	price = 20
	items = list(
		/obj/item/cell
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/hoistkit
	category = "engineering"
	name = "hoist kit"
	supplier = "Hub"
	description = "A setup kit for a hoist that can be used to lift things. The hoist will deploy in the direction you're facing."
	price = 40
	items = list(
		/obj/item/hoist_kit
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/inflatablebarrierbox
	category = "engineering"
	name = "inflatable barrier box"
	supplier = "Hub"
	description = "Contains inflatable walls and doors."
	price = 65
	items = list(
		/obj/item/storage/bag/inflatable
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/insulatedgloves
	category = "engineering"
	name = "insulated gloves"
	supplier = "Hub"
	description = "These gloves will protect the wearer from electric shock."
	price = 72
	items = list(
		/obj/item/clothing/gloves/yellow
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/tajaranelectricalgloves
	category = "engineering"
	name = "tajaran electrical gloves"
	supplier = "Hub"
	description = "These gloves will protect the wearer from electric shock. Made special for Tajaran use."
	price = 74
	items = list(
		/obj/item/clothing/gloves/yellow/specialt
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/unathielectricalgloves
	category = "engineering"
	name = "unathi electrical gloves"
	supplier = "Hub"
	description = "These gloves will protect the wearer from electric shock. Made special for Unathi use."
	price = 74
	items = list(
		/obj/item/clothing/gloves/yellow/specialu
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/debugger
	category = "engineering"
	name = "debugger"
	supplier = "Hub"
	description = "Used to debug electronic equipment."
	price = 12
	items = list(
		/obj/item/debugger
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 2

/singleton/cargo_item/powerdrill
	category = "engineering"
	name = "impact wrench"
	supplier = "Hub"
	description = "Wrenches and screws things. Faster."
	price = 12
	items = list(
		/obj/item/powerdrill
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/paintgun
	category = "engineering"
	name = "paint gun"
	supplier = "Hub"
	description = "Useful for designating areas and pissing off coworkers."
	price = 25
	items = list(
		/obj/item/paint_sprayer
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/particleacceleratorcontrolcomputer
	category = "engineering"
	name = "Particle Accelerator Control Computer"
	supplier = "Hub"
	description = "This controls the density of the particles."
	price = 2250
	items = list(
		/obj/structure/machinery/particle_accelerator/control_box
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/particlefocusingemlens
	category = "engineering"
	name = "Particle Focusing EM Lens"
	supplier = "Hub"
	description = "Part of a Particle Accelerator."
	price = 1250
	items = list(
		/obj/structure/particle_accelerator/power_box
	)
	access = ACCESS_CE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/portableladder
	category = "engineering"
	name = "portable ladder"
	supplier = "Hub"
	description = "A lightweight deployable ladder, which you can use to move up or down. Or alternatively, you can bash some faces in."
	price = 40
	items = list(
		/obj/item/ladder_mobile
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/radiationhood
	category = "engineering"
	name = "radiation Hood"
	supplier = "Hub"
	description = "A hood with radiation protective properties. Label: Made with lead, do not eat insulation."
	price = 70
	items = list(
		/obj/item/clothing/head/radiation
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/radiationsuit
	category = "engineering"
	name = "radiation suit"
	supplier = "Hub"
	description = "A suit that protects against radiation. Label: Made with lead, do not eat insulation."
	price = 120
	items = list(
		/obj/item/clothing/suit/radiation
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/researchshuttleconsoleboard
	category = "engineering"
	name = "research shuttle console board"
	supplier = "Hub"
	description = "A replacement board for the research shuttle console, in case the original console is destroyed."
	price = 125
	items = list(
		/obj/item/circuitboard/research_shuttle
	)
	access = ACCESS_SECURITY
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/singularitygenerator
	category = "engineering"
	name = "singularity generator"
	supplier = "Hub"
	description = "Used to generate a Singularity. It is not adviced to use this on the asteroid."
	price = 17000
	items = list(
		/obj/structure/machinery/the_singularitygen
	)
	access = ACCESS_HEADS
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/superconductivemagneticcoil
	category = "engineering"
	name = "superconductive magnetic coil"
	supplier = "Hub"
	description = "Standard superconductive magnetic coil with average capacity and I/O rating."
	price = 800
	items = list(
		/obj/item/smes_coil
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/supermattercore
	category = "engineering"
	name = "supermatter crystal"
	supplier = "Hub"
	description = "An unstable, radioactive crystal that forms the power source of several experimental ships and stations. Extremely dangerous."
	price = 18500
	items = list(
		/obj/structure/machinery/power/supermatter
	)
	access = ACCESS_CAPTAIN
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/thermoelectricgenerator
	category = "engineering"
	name = "thermoelectric generator kit"
	supplier = "Hub"
	description = "A kit that comes with a thermoelectric generator and two circulators that attach to it. For usage in high-power energy generation."
	price = 1200
	items = list(
		/obj/structure/machinery/power/generator,
		/obj/structure/machinery/atmospherics/binary/circulator,
		/obj/structure/machinery/atmospherics/binary/circulator
	)
	access = ACCESS_ENGINE
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/hyperspanner
	category = "engineering"
	name = "hyperspanner"
	supplier = "Hub"
	description = "A heavy-duty multi-tool for rapid structural repairs to walls, windows, machinery, and floors. Requires a power cell (sold separately)."
	price = 100000
	items = list(
		/obj/item/hyperspanner
	)
	access = ACCESS_ENGINE
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/solarpanelassembly
	category = "engineering"
	name = "solar panel assembly"
	supplier = "Hub"
	description = "A solar panel assembly kit, allows constructions of a solar panel, or with a tracking circuit board, a solar tracker."
	price = 350
	items = list(
		/obj/item/solar_assembly
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 5

/singleton/cargo_item/trackerelectronics
	category = "engineering"
	name = "tracker electronics"
	supplier = "Hub"
	description = "Electronic guidance systems for a solar array."
	price = 100
	items = list(
		/obj/item/tracker_electronics
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/watertank
	category = "engineering"
	name = "watertank"
	supplier = "Hub"
	description = "A tank filled with water."
	price = 10
	items = list(
		/obj/structure/reagent_dispensers/watertank
	)
	access = ACCESS_ENGINE
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/weldinghelmet
	category = "engineering"
	name = "welding helmet"
	supplier = "Hub"
	description = "A head-mounted face cover designed to protect the wearer completely from space-arc eye."
	price = 20
	items = list(
		/obj/item/clothing/head/welding
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/alphaparticlegenerationarray
	category = "engineering"
	name = "Alpha Particle Generation Array"
	supplier = "Hub"
	description = "Part of a Particle Accelerator."
	price = 1550
	items = list(
		/obj/structure/particle_accelerator/end_cap
	)
	access = ACCESS_CE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/rad_collector
	category = "engineering"
	name = "radiation collector array"
	supplier = "Hub"
	description = "A radiation collector array. Used to augment the power generation of a generator that emits ionising radiation."
	price = 650
	items = list(
		/obj/structure/machinery/power/rad_collector
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/engineeringcart
	category = "engineering"
	name = "engineering cart"
	supplier = "Hub"
	description = "A cart for your engineering-related storage needs."
	price = 100
	items = list(
		/obj/structure/cart/storage/engineeringcart
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/smesconstructioncrate
	category = "engineering"
	name = "SMES construction crate"
	supplier = "Hub"
	description = "Everything needed to build a superconducting magnetic energy storage (SMES) unit from scratch: steel for the frame, cable, a circuit board, and a magnetic coil."
	price = 1200
	items = list(
		/obj/item/stack/material/steel/full,
		/obj/item/stack/cable_coil,
		/obj/item/stack/cable_coil,
		/obj/item/circuitboard/smes,
		/obj/item/smes_coil
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/telecommunications_crate
	category = "engineering"
	name = "Telecommunications Crate"
	supplier = "Hub"
	description = "A crate of circuit boards and subspace components for constructing or repairing telecommunications machinery."
	price = 3500
	items = list(
		/obj/item/circuitboard/telecomms/receiver,
		/obj/item/circuitboard/telecomms/hub,
		/obj/item/circuitboard/telecomms/bus,
		/obj/item/circuitboard/telecomms/processor,
		/obj/item/circuitboard/telecomms/server,
		/obj/item/circuitboard/telecomms/broadcaster,
		/obj/item/stack/cable_coil,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/manipulator,
		/obj/item/stock_parts/scanning_module,
		/obj/item/stock_parts/micro_laser/high,
		/obj/item/stock_parts/micro_laser/high,
		/obj/item/stock_parts/micro_laser/high,
		/obj/item/stock_parts/subspace/filter,
		/obj/item/stock_parts/subspace/filter,
		/obj/item/stock_parts/subspace/filter,
		/obj/item/stock_parts/subspace/filter,
		/obj/item/stock_parts/subspace/filter,
		/obj/item/stock_parts/subspace/filter,
		/obj/item/stock_parts/subspace/filter,
		/obj/item/stock_parts/subspace/ansible,
		/obj/item/stock_parts/subspace/ansible,
		/obj/item/stock_parts/subspace/ansible,
		/obj/item/stock_parts/subspace/crystal,
		/obj/item/stock_parts/subspace/analyzer,
		/obj/item/stock_parts/subspace/amplifier,
		/obj/item/stock_parts/subspace/treatment,
		/obj/item/stock_parts/subspace/treatment
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/airlock_cycler_crate
	category = "engineering"
	name = "Airlock Cycler Crate"
	supplier = "Hub"
	description = "Wall frames, circuit boards, and cable for building a complete airlock cycler control setup: one controller, one interior and one exterior access button, and chamber, interior and exterior pressure sensors. Mount the chamber sensor inside the airlock itself. Does not include the airlock -- build that from a standard airlock assembly."
	price = 1200
	items = list(
		/obj/item/frame/airlock_controller,
		/obj/item/airlock_cycler_electronics/airlock_controller,
		/obj/item/frame/access_button/airlock_interior,
		/obj/item/airlock_cycler_electronics/access_button,
		/obj/item/frame/access_button/airlock_exterior,
		/obj/item/airlock_cycler_electronics/access_button,
		/obj/item/frame/airlock_sensor,
		/obj/item/airlock_cycler_electronics/airlock_sensor,
		/obj/item/frame/airlock_sensor/airlock_interior,
		/obj/item/airlock_cycler_electronics/airlock_sensor,
		/obj/item/frame/airlock_sensor/airlock_exterior,
		/obj/item/airlock_cycler_electronics/airlock_sensor,
		/obj/item/stack/cable_coil
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/ship_commissioning_console_crate
	category = "engineering"
	name = "Ship Commissioning Console Crate"
	supplier = "Hub"
	description = "A ready-to-place commissioning console for turning a self-built hull into a real, independently-owned shuttle. Wrench it down near an active docking beacon -- the console previews the buildable envelope and files the commission once the hull inside it is complete. Reusable for as many hulls as you build there."
	price = 5000
	items = list(/obj/structure/machinery/computer/ship_commissioning)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/shuttle_control_console_crate
	category = "engineering"
	name = "Shuttle Control Console Crate"
	supplier = "Hub"
	description = "A ready-to-place shuttle control console -- the minimum a self-built hull needs to actually fly once commissioned. Wrench it down inside your build envelope before commissioning."
	price = 3000
	items = list(/obj/structure/machinery/computer/shuttle_control/explore/terminal/drydock_ship/buildable)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/docking_transponder_crate
	category = "engineering"
	name = "Docking Transponder Crate"
	supplier = "Hub"
	description = "A ready-to-place docking transponder. Mount it at a shuttle's own airlock/exit tile and rotate it to declare which way that airlock faces -- a docking beacon facing the opposite direction will recognize it as a compatible dock. Purely optional: a shuttle with no transponder docks anywhere it always could."
	price = 800
	items = list(/obj/structure/machinery/docking_transponder)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/propulsion_engine_crate
	category = "engineering"
	name = "Propulsion Engine Crate"
	supplier = "Hub"
	description = "A ready-to-place propulsion engine unit for a self-built hull. Wrench it down anywhere inside your build envelope -- a commissioned hull needs at least four of these somewhere inside it."
	price = 10000
	items = list(/obj/structure/shuttle/engine/propulsion/buildable)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/helm_console_crate
	category = "engineering"
	name = "Helm Console Crate"
	supplier = "Hub"
	description = "A ready-to-place helm console -- required to actually pilot a self-built hull on the overmap once commissioned. The shuttle control console alone only ever offers point-to-point docking, not real flight. Wrench it down inside your build envelope before commissioning."
	price = 15000
	items = list(/obj/structure/machinery/computer/ship/helm/terminal/buildable)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/navigation_console_crate
	category = "engineering"
	name = "Navigation Console Crate"
	supplier = "Hub"
	description = "A ready-to-place navigation console -- a display-only companion to the helm console, showing live position, speed, and heading. Entirely optional, not required to commission a hull."
	price = 15000
	items = list(/obj/structure/machinery/computer/ship/navigation/terminal/buildable)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/fuel_port_crate
	category = "engineering"
	name = "Fuel Port Crate"
	supplier = "Hub"
	description = "A ready-to-place fuel port, pre-loaded with a starter tank of phoron. Attach it to a wall inside your hull, then wrench and weld it in place -- a commissioned hull needs at least one of these to actually launch under its own power."
	price = 2000
	items = list(/obj/item/fuel_port, /obj/item/tank/phoron/shuttle)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/shuttle_phoron_tank_crate
	category = "engineering"
	name = "Shuttle Phoron Tank Crate"
	supplier = "Hub"
	description = "A replacement phoron tank, sized for a shuttle's own fuel port. Order more of these to refuel or top off your hull once its starter tank runs low -- no need to buy another whole fuel port just for the fuel."
	price = 500
	items = list(/obj/item/tank/phoron/shuttle)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/engine_control_crate
	category = "engineering"
	name = "Engine Control Terminal Crate"
	supplier = "Hub"
	description = "A ready-to-place engine control terminal -- required to actually turn a commissioned hull's engines on. Fuel, a helm console, and propulsion engines alone aren't enough without this. Wrench it down inside your build envelope before commissioning."
	price = 15000
	items = list(/obj/structure/machinery/computer/ship/engines/terminal/buildable)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/ship_nozzle_engine_crate
	category = "engineering"
	name = "Ship Nozzle Engine Crate"
	supplier = "Hub"
	description = "A ready-to-place rocket nozzle engine -- the real thing that actually burns fuel gas for thrust, required alongside the decorative propulsion units for a commissioned hull to move under its own power. Wrench it down and pipe it into a fuel-gas network before commissioning."
	price = 15000
	items = list(/obj/structure/machinery/atmospherics/unary/engine/buildable)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/targeting_computer_crate
	category = "engineering"
	name = "Targeting Computer Crate"
	supplier = "Hub"
	description = "A ready-to-place targeting systems console for a ship's weaponry. Wrench it down anywhere aboard, then multitool it to buffer it for hooking up to ship weapons. Entirely optional -- a hull commissions and flies perfectly well without one."
	price = 15000
	items = list(/obj/structure/machinery/computer/ship/targeting/buildable)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/ion_engine_crate
	category = "engineering"
	name = "Ion Engine Crate"
	supplier = "Hub"
	description = "A ready-to-place ion propulsion device -- a self-contained alternative to the rocket nozzle engine, converting stored electrical charge directly into thrust with no piped fuel gas or fuel port needed. Wrench it down and wire it to power. Either this or a piped nozzle engine satisfies a commissioned hull's engine requirement -- not both."
	price = 20000
	items = list(/obj/structure/machinery/ion_engine/buildable)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/fusion_reactor_crate
	category = "engineering"
	name = "Fusion Reactor Crate"
	supplier = "Hub"
	description = "A ready-to-place miniature fusion reactor -- rated for 500 kW max safe output, runs on tritium sheets and needs a coolant top-up to run efficiently. Gives a self-built hull local electrical power without needing a full station-style grid. Not required to commission a hull, purely optional infrastructure. Handle with care -- overloading or emagging it can cause a serious explosion."
	price = 50000
	items = list(/obj/structure/machinery/power/portgen/basic/fusion/buildable)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/sensors_terminal_crate
	category = "engineering"
	name = "Sensors Terminal Crate"
	supplier = "Hub"
	description = "A ready-to-place sensors terminal -- required to see anything outside a commissioned hull and to set its sensor array's range. Wrench it down anywhere inside the hull; needs a Ship Sensor Array Crate too."
	price = 15000
	items = list(/obj/structure/machinery/computer/ship/sensors/terminal/buildable)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/ship_sensor_array_crate
	category = "engineering"
	name = "Ship Sensor Array Crate"
	supplier = "Hub"
	description = "A ready-to-place sensor array -- the actual hardware a sensors terminal reads from and commands. Wrench it down anywhere inside the hull; needs a Sensors Terminal Crate too."
	price = 15000
	items = list(/obj/structure/machinery/shipsensors/weak/buildable)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/cablecoil
	category = "engineering"
	name = "cable coil"
	supplier = "Hub"
	description = "A full coil of power cable."
	price = 60
	items = list(
		/obj/item/stack/cable_coil
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/powercontrolmodule
	category = "engineering"
	name = "power control module"
	supplier = "Hub"
	description = "Looks like a circuit. Probably is."
	price = 150
	items = list(
		/obj/item/module/power_control
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/airalarmcircuit
	category = "engineering"
	name = "air alarm circuit"
	supplier = "Hub"
	description = "Looks like a circuit. Probably is."
	price = 60
	items = list(
		/obj/item/airalarm_electronics
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/airlockcircuit
	category = "engineering"
	name = "airlock circuit"
	supplier = "Hub"
	description = "Looks like a circuit. Probably is."
	price = 60
	items = list(
		/obj/item/airlock_electronics
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/firealarmcircuit
	category = "engineering"
	name = "fire alarm circuit"
	supplier = "Hub"
	description = "Looks like a circuit. Probably is."
	price = 60
	items = list(
		/obj/item/firealarm_electronics
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/rfd_construction
	category = "engineering"
	name = "Rapid Fabrication Device C-Class"
	supplier = "Hub"
	description = "A RFD, modified to construct walls and floors."
	price = 45
	items = list(
		/obj/item/rfd/construction
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/rfd_ammo
	category = "engineering"
	name = "compressed matter cartridge"
	supplier = "Hub"
	description = "Highly compressed matter for the RFD."
	price = 15
	items = list(
		/obj/item/rfd_ammo
	)
	access = ACCESS_ENGINE
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1
