/singleton/cargo_item/autakhlimbs
	category = "operations"
	name = "autakh limbs"
	supplier = "Hub"
	description = "A box with various autakh limbs."
	price = 1000
	items = list(
		/obj/item/organ/external/hand/right/autakh/tool,
		/obj/item/organ/external/hand/right/autakh/tool/mining,
		/obj/item/organ/external/hand/right/autakh/medical
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 2

/singleton/cargo_item/factiontagger
	category = "operations"
	name = "faction tagger"
	supplier = "Hub"
	description = "A configurator for tagging station infrastructure to a faction network."
	price = 1000
	items = list(
		/obj/item/faction_tagger
	)
	access = 0
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/factionbeacon
	category = "operations"
	name = "faction beacon"
	supplier = "Hub"
	description = "An anchor beacon that ties nearby infrastructure to a faction network."
	price = 100000
	items = list(
		/obj/structure/machinery/faction_beacon
	)
	access = 0
	container_type = "crate"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/shipcloakingdevice
	category = "operations"
	name = "cloaking device"
	supplier = "Hub"
	description = "A hulking device that renders a ship completely undetectable to sensors once installed, anchored, and powered. Requires a steady supply of phoron crystals to operate."
	price = 1000000
	items = list(
		/obj/structure/machinery/ship_cloaking_device
	)
	access = 0
	container_type = "crate"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/colonyradio
	category = "operations"
	name = "colony radio"
	supplier = "Hub"
	description = "A transponder for requesting a new colonial station claim from Central Command. Subject to admin approval."
	price = 100000
	items = list(
		/obj/item/colony_radio
	)
	access = 0
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/syndicateuplink
	category = "operations"
	name = "syndicate uplink terminal"
	supplier = "Hub"
	description = "A modified radio that conceals a black-market purchasing terminal. Requires local piracy infrastructure to source."
	price = 250000
	items = list(
		/obj/item/radio/uplink
	)
	access = 0
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1
	requires_piracy_beacon = TRUE

/singleton/cargo_item/cargotraintrolley
	category = "operations"
	name = "cargo train trolley"
	supplier = "Hub"
	description = "A cargo trolley for carrying cargo, NOT people."
	price = 800
	items = list(
		/obj/vehicle/train/cargo/trolley
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/cargotraintug
	category = "operations"
	name = "cargo train tug"
	supplier = "Hub"
	description = "A ridable electric car designed for pulling cargo trolleys."
	price = 350
	items = list(
		/obj/vehicle/train/cargo/engine
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/coathanger
	category = "operations"
	name = "Coat Hanger"
	supplier = "Hub"
	description = "To hang your coat."
	price = 12
	items = list(
		/obj/structure/coatrack
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/eftposscanner
	category = "operations"
	name = "EFTPOS scanner"
	supplier = "Hub"
	description = "Swipe your ID card to make purchases electronically."
	price = 35
	items = list(
		/obj/item/eftpos
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/emptyspraybottle
	category = "operations"
	name = "empty spray bottle"
	supplier = "Hub"
	description = "A empty spray bottle."
	price = 5
	items = list(
		/obj/item/reagent_containers/spray
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/faxmachine
	category = "operations"
	name = "fax machine"
	supplier = "Hub"
	description = "Needed office equipment for any space based corporation to function."
	price = 300
	items = list(
		/obj/structure/machinery/photocopier/faxmachine
	)
	access = 0
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/flare
	category = "operations"
	name = "flare"
	supplier = "Hub"
	description = "Good for illuminating dark areas or burning someones face off."
	price = 8
	items = list(
		/obj/item/flashlight/flare
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/formalwearcrate
	category = "operations"
	name = "formal wear crate"
	supplier = "Hub"
	description = "Formalwear for the best occasions."
	price = 350
	items = list(
		/obj/item/clothing/head/bowler,
		/obj/item/clothing/head/that,
		/obj/item/clothing/under/suit_jacket,
		/obj/item/clothing/under/suit_jacket/really_black,
		/obj/item/clothing/under/suit_jacket/red,
		/obj/item/clothing/under/suit_jacket/navy,
		/obj/item/clothing/under/suit_jacket/burgundy,
		/obj/item/clothing/shoes/sneakers/black,
		/obj/item/clothing/shoes/laceup,
		/obj/item/clothing/shoes/laceup/grey,
		/obj/item/clothing/suit/wcoat
	)
	access = 0
	container_type = "crate"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/giftwrappingpaper
	category = "operations"
	name = "gift wrapping paper"
	supplier = "Hub"
	description = "You can use this to wrap items in."
	price = 8
	items = list(
		/obj/item/stack/wrapping_paper
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/janitorialresupplyset
	category = "operations"
	name = "janitorial resupply set"
	supplier = "Hub"
	description = "A set of items to restock the janitors closet."
	price = 2000
	items = list(
		/obj/structure/cart/storage/janitorialcart,
		/obj/structure/mopbucket,
		/obj/item/mop,
		/obj/item/storage/bag/trash,
		/obj/item/reagent_containers/spray/cleaner,
		/obj/item/reagent_containers/glass/rag,
		/obj/item/clothing/suit/caution,
		/obj/item/clothing/suit/caution,
		/obj/item/clothing/suit/caution,
		/obj/item/grenade/chem_grenade/cleaner,
		/obj/item/grenade/chem_grenade/cleaner,
		/obj/item/grenade/chem_grenade/cleaner,
		/obj/item/soap/nanotrasen
	)
	access = 0
	container_type = "crate"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/loadbearingequipment
	category = "operations"
	name = "load bearing equipment"
	supplier = "Hub"
	description = "Used to hold things when you don't have enough hands."
	price = 83
	items = list(
		/obj/item/clothing/accessory/storage
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/packagewrapper
	category = "operations"
	name = "package wrapper"
	supplier = "Hub"
	description = "A roll of paper used to enclose an object for delivery."
	price = 8
	items = list(
		/obj/item/stack/packageWrap
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/pda
	category = "operations"
	name = "PDA"
	supplier = "Hub"
	description = "The latest in portable microcomputer solutions from Thinktronic Systems, LTD."
	price = 90
	items = list(
		/obj/item/modular_computer/handheld/pda
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/photoalbum
	category = "operations"
	name = "Photo album"
	supplier = "Hub"
	description = "A place to store fond memories you made in space."
	price = 45
	items = list(
		/obj/item/storage/photo_album
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/photocopier
	category = "operations"
	name = "photo copier"
	supplier = "Hub"
	description = "When you're too lazy to write a copy yourself."
	price = 300
	items = list(
		/obj/structure/machinery/photocopier
	)
	access = 0
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/poster19
	category = "operations"
	name = "random poster"
	supplier = "Hub"
	description = "The poster comes with its own automatic adhesive mechanism, for easy pinning to any vertical surface."
	price = 3.50
	items = list(
		/obj/item/contraband/poster
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/shoulderholster
	category = "operations"
	name = "shoulder holster"
	supplier = "Hub"
	description = "A handgun holster."
	price = 15
	items = list(
		/obj/item/clothing/accessory/holster
	)
	access = ACCESS_SECURITY
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/space_bike
	category = "operations"
	name = "space-bike"
	supplier = "Hub"
	description = "Space wheelies! Woo!"
	price = 800
	items = list(
		/obj/vehicle/bike
	)
	access = 0
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/*
 * Space pod parts, DIY build kit, and fully-built hulls -- see
 * code/modules/vehicles/pods/. Individual components let a buyer equip a
 * pod they built (or bought bare) piece by piece; the pod crate is the
 * from-scratch path (bundles the frame kit + enough raw material to finish
 * all 7 construction stages, code/modules/vehicles/pods/ships.dm, plus an
 * engine since that recipe can't finish without one); the 9 hull packs are
 * the fully-built path, each delivering a /stocked variant (ships.dm) with a
 * bare, unfueled engine already installed.
 */
/singleton/cargo_item/podengine
	category = "operations"
	name = "pod engine"
	supplier = "Hub"
	description = "A compact phoron-fed drive engine for a space pod."
	price = 2500
	items = list(
		/obj/item/podcomponent/engine
	)
	access = 0
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/podwarpengine
	category = "operations"
	name = "pod warp engine"
	supplier = "Hub"
	description = "A pod drive engine fitted with a bluespace warp coil for sector-to-sector jumps."
	price = 6000
	items = list(
		/obj/item/podcomponent/engine/warp
	)
	access = ACCESS_CARGO
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/podphaser
	category = "operations"
	name = "pod phaser"
	supplier = "Hub"
	description = "A light energy weapon mount for a space pod."
	price = 4000
	items = list(
		/obj/item/podcomponent/mainweapon
	)
	access = ACCESS_CARGO
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/podcargohold
	category = "operations"
	name = "pod cargo hold"
	supplier = "Hub"
	description = "A small cargo module for a space pod."
	price = 1500
	items = list(
		/obj/item/podcomponent/secondary/cargo
	)
	access = 0
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/podshielding
	category = "operations"
	name = "pod shielding"
	supplier = "Hub"
	description = "A short-lived deflector shield system for a space pod."
	price = 3500
	items = list(
		/obj/item/podcomponent/secondary/shielding
	)
	access = 0
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/podhatchlock
	category = "operations"
	name = "pod hatch lock"
	supplier = "Hub"
	description = "A passcode-locked hatch control for a space pod."
	price = 500
	items = list(
		/obj/item/podcomponent/lock
	)
	access = 0
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/podcommsarray
	category = "operations"
	name = "pod comms array"
	supplier = "Hub"
	description = "A short-range communications and navigation-network transceiver for a space pod."
	price = 1000
	items = list(
		/obj/item/podcomponent/comms
	)
	access = 0
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/podsensorarray
	category = "operations"
	name = "pod sensor array"
	supplier = "Hub"
	description = "A short-range sensor suite for a space pod."
	price = 1500
	items = list(
		/obj/item/podcomponent/sensors
	)
	access = 0
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/podlights
	category = "operations"
	name = "pod running lights"
	supplier = "Hub"
	description = "An exterior light fixture for a space pod."
	price = 300
	items = list(
		/obj/item/podcomponent/lights
	)
	access = 0
	container_type = "box"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/podcrate
	category = "operations"
	name = "pod crate"
	supplier = "Hub"
	description = "Everything needed to build a space pod from scratch: a frame kit, raw materials, and an engine."
	price = 3000
	items = list(
		/obj/item/pod_frame_kit,
		/obj/item/stack/cable_coil,
		/obj/item/stack/material/steel/full,
		/obj/item/stack/material/glass/reinforced/full,
		/obj/item/podcomponent/engine
	)
	access = 0
	container_type = "crate"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/podhullescape
	category = "operations"
	name = "escape pod (fully built)"
	supplier = "Hub"
	description = "A minimal, cheaply-built pod meant to get one person out of danger, not into it. Arrives with a bare engine installed -- no fuel tank."
	price = 15000
	items = list(
		/obj/vehicle/bike/pod/escape/stocked
	)
	access = ACCESS_HEADS
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/podhullindependent
	category = "operations"
	name = "independent pod (fully built)"
	supplier = "Hub"
	description = "A no-frills civilian space pod, cheap and easy to build. Arrives with a bare engine installed -- no fuel tank."
	price = 16000
	items = list(
		/obj/vehicle/bike/pod/independent/stocked
	)
	access = ACCESS_HEADS
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/podhullrecon
	category = "operations"
	name = "recon pod (fully built)"
	supplier = "Hub"
	description = "A stripped-down space pod built for speed over survivability. Arrives with a bare engine installed -- no fuel tank."
	price = 17000
	items = list(
		/obj/vehicle/bike/pod/recon/stocked
	)
	access = ACCESS_HEADS
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/podhullslick
	category = "operations"
	name = "slick pod (fully built)"
	supplier = "Hub"
	description = "A sleek, fast space pod that trades armor plating for a sharper hull. Arrives with a bare engine installed -- no fuel tank."
	price = 17500
	items = list(
		/obj/vehicle/bike/pod/slick/stocked
	)
	access = ACCESS_HEADS
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/podhullmini
	category = "operations"
	name = "mini pod (fully built)"
	supplier = "Hub"
	description = "A small, single-seat space pod. Arrives with a bare engine installed -- no fuel tank."
	price = 18000
	items = list(
		/obj/vehicle/bike/pod/mini/stocked
	)
	access = ACCESS_HEADS
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/podhullsaucer
	category = "operations"
	name = "saucer pod (fully built)"
	supplier = "Hub"
	description = "A space pod built in an unmistakable saucer shape. Arrives with a bare engine installed -- no fuel tank."
	price = 18000
	items = list(
		/obj/vehicle/bike/pod/saucer/stocked
	)
	access = ACCESS_HEADS
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/podhullcargo
	category = "operations"
	name = "cargo pod (fully built)"
	supplier = "Hub"
	description = "A space pod with a built-in cargo hold. Arrives with a bare engine installed -- no fuel tank."
	price = 19000
	items = list(
		/obj/vehicle/bike/pod/cargo/stocked
	)
	access = ACCESS_HEADS
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/podhullcorporate
	category = "operations"
	name = "corporate pod (fully built)"
	supplier = "Hub"
	description = "A space pod finished in corporate livery. Arrives with a bare engine installed -- no fuel tank."
	price = 19500
	items = list(
		/obj/vehicle/bike/pod/corporate/stocked
	)
	access = ACCESS_HEADS
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/podhullheg
	category = "operations"
	name = "Hegemony-pattern pod (fully built)"
	supplier = "Hub"
	description = "A space pod built to a Hegemony maintenance pattern. Arrives with a bare engine installed -- no fuel tank."
	price = 20000
	items = list(
		/obj/vehicle/bike/pod/heg/stocked
	)
	access = ACCESS_HEADS
	container_type = "box"
	groupable = FALSE
	spawn_amount = 1

/singleton/cargo_item/webbing
	category = "operations"
	name = "webbing"
	supplier = "Hub"
	description = "Sturdy mess of synthcotton belts and buckles, ready to share your burden."
	price = 43
	items = list(
		/obj/item/clothing/accessory/storage/webbing
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/blackpaint
	category = "operations"
	name = "black paint"
	supplier = "Hub"
	description = "Black paint, the color of space."
	price = 10
	items = list(
		/obj/item/reagent_containers/glass/paint/black
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bluepaint
	category = "operations"
	name = "blue paint"
	supplier = "Hub"
	description = "Blue paint, for when you're on a mission from god."
	price = 10
	items = list(
		/obj/item/reagent_containers/glass/paint/blue
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/whitepaint
	category = "operations"
	name = "white paint"
	supplier = "Hub"
	description = "White paint, perfect for sterile boring lab environments."
	price = 10
	items = list(
		/obj/item/reagent_containers/glass/paint/white
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/yellowpaint
	category = "operations"
	name = "yellow paint"
	supplier = "Hub"
	description = "Yellow paint, for when you need to make eyes sore."
	price = 10
	items = list(
		/obj/item/reagent_containers/glass/paint/yellow
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/purplepaint
	category = "operations"
	name = "purple paint"
	supplier = "Hub"
	description = "Purple paint, it makes you feel like royalty."
	price = 10
	items = list(
		/obj/item/reagent_containers/glass/paint/purple
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/redpaint
	category = "operations"
	name = "red paint"
	supplier = "Hub"
	description = "Red paint, its not blood we promise."
	price = 10
	items = list(
		/obj/item/reagent_containers/glass/paint/red
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/greenpaint
	category = "operations"
	name = "green paint"
	supplier = "Hub"
	description = "Green paint, a aesthetic replacement for grass."
	price = 10
	items = list(
		/obj/item/reagent_containers/glass/paint/green
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/battlemonstersresupplycanister
	category = "operations"
	name = "battlemonsters resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 2250
	items = list(
		/obj/item/vending_refill/battlemonsters
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/boozeresupplycanister
	category = "operations"
	name = "booze resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 4500
	items = list(
		/obj/item/vending_refill/booze
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/zorasodaresupplycanister
	category = "operations"
	name = "zora soda resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 1255
	items = list(
		/obj/item/vending_refill/zora
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/toolsresupplycanister
	category = "operations"
	name = "tools resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 2450
	items = list(
		/obj/item/vending_refill/tools
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/smokesresupplycanister
	category = "operations"
	name = "smokes resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 2250
	items = list(
		/obj/item/vending_refill/smokes
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/snacksresupplycanister
	category = "operations"
	name = "snacks resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 1255
	items = list(
		/obj/item/vending_refill/snack
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/robotoolsresupplycanister
	category = "operations"
	name = "robo-tools resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 2500
	items = list(
		/obj/item/vending_refill/robo
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/securityresupplycanister
	category = "operations"
	name = "security resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 4500
	items = list(
		/obj/item/vending_refill/robust
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/medsresupplycanister
	category = "operations"
	name = "meds resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 5500
	items = list(
		/obj/item/vending_refill/meds
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/hydroresupplycanister
	category = "operations"
	name = "hydro resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 2500
	items = list(
		/obj/item/vending_refill/hydro
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/coffeeresupplycanister
	category = "operations"
	name = "coffee resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 1350
	items = list(
		/obj/item/vending_refill/coffee
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/colaresupplycanister
	category = "operations"
	name = "cola resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 1250
	items = list(
		/obj/item/vending_refill/cola
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/cutleryresupplycanister
	category = "operations"
	name = "cutlery resupply canister"
	supplier = "Hub"
	description = "A vending machine restock cart."
	price = 850
	items = list(
		/obj/item/vending_refill/cutlery
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/cigarette_restock
	category = "operations"
	name = "commissary cigarette restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 240
	items = list(
		/obj/item/storage/box/fancy/commissary_restock
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/rollable_restock
	category = "operations"
	name = "commissary tobacco leaves restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 100
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/rollable
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/chewable_restock
	category = "operations"
	name = "commissary chewing tobacco restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 240
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/chewable
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/smoking_accessory_restock
	category = "operations"
	name = "commissary smoking accessories restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 140
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/smoking_accessory
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/electric_cig_restock
	category = "operations"
	name = "commissary electronic cigarette restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 80
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/electronic_cig
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/snack_restock
	category = "operations"
	name = "commissary snack restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 100
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/food
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/xeno_restock
	category = "operations"
	name = "commissary xeno snack restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 60
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/food/xeno
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/candy_restock
	category = "operations"
	name = "commissary candy restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 65
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/food/candy
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/microwave_restock
	category = "operations"
	name = "commissary microwave meal restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 220
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/food/microwave
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/drink_restock
	category = "operations"
	name = "commissary drink restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 150
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/drink
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/cheap_booze_restock
	category = "operations"
	name = "commissary beer restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 100
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/drink/booze_cheap
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/toys_restock
	category = "operations"
	name = "commissary toy restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 110
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/toy
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/dice_cards_restock
	category = "operations"
	name = "commissary dice and card restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 120
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/toy/cards_dice
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/toy_mech_restock
	category = "operations"
	name = "commissary toy mech restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 200
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/toy/mech
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/comic_restock
	category = "operations"
	name = "commissary comic restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 25
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/toy/comic
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/nka_comic_restock
	category = "operations"
	name = "commissary az'marian comic series restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 50
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/toy/comic/nka
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/music_restock
	category = "operations"
	name = "commissary music restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	price = 50
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/music
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/tea_restock
	category = "operations"
	name = "commissary tea restock"
	supplier = "Hub"
	description = "A box full of stock for the commissary."
	// Bulk commissary orders are at a discount, so cheaper per tin of tea than regularly ordering tea
	price = 75
	items = list(
		/obj/item/storage/box/fancy/commissary_restock/tea
	)
	access = ACCESS_CARGO
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1
