/*
 * Cargo listings for every orderable backpack, satchel, duffel, messenger bag and
 * rucksack. Split into its own file rather than appended to operations.dm, which is
 * already ~1,160 lines.
 *
 * All entries are category "operations" -- that is where clothing and worn kit live
 * (webbing, load bearing equipment, shoulder holster, formalwear crate). There is no
 * dedicated clothing category.
 *
 * NAMES MUST BE UNIQUE. SScargo.cargo_items is keyed by cargo_item.name
 * (controllers/subsystems/cargo.dm), so two entries sharing a name silently overwrite
 * each other and one item quietly disappears from the console. Two upstream quirks are
 * worked around below: /obj/item/storage/backpack/satchel/pmcg is misnamed "PMCG
 * backpack" (colliding with the real PMCG backpack), and the three recolorable variants
 * inherit their parent's name.
 *
 * Deliberately NOT listed: antag gear (syndicate, ERT), event/admin items (Santa bag,
 * bluespace pocket, cult trophy rack, chameleon), Vaurca breeder wings and tunnel cloaks
 * (species equipment), prefilled locker/marooning bags, custom player items, and the
 * faction military bags (Legion, TCAF, Hegemony, Dominian, Golden Deep).
 */

// ---------------------------------------------------------------------------
// BACKPACKS
// ---------------------------------------------------------------------------

/singleton/cargo_item/bag_backpack
	category = "operations"
	name = "backpack"
	supplier = "Hub"
	description = "A standard-issue backpack. Holds things on your back."
	price = 25
	items = list(
		/obj/item/storage/backpack
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_medic
	category = "operations"
	name = "medical backpack"
	supplier = "Hub"
	description = "A backpack in sterile medical white."
	price = 25
	items = list(
		/obj/item/storage/backpack/medic
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_security
	category = "operations"
	name = "security backpack"
	supplier = "Hub"
	description = "A robust backpack in security black and red."
	price = 25
	items = list(
		/obj/item/storage/backpack/security
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_industrial
	category = "operations"
	name = "industrial backpack"
	supplier = "Hub"
	description = "A hard-wearing backpack for engineering work."
	price = 25
	items = list(
		/obj/item/storage/backpack/industrial
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_toxins
	category = "operations"
	name = "laboratory backpack"
	supplier = "Hub"
	description = "A backpack designed for laboratory use."
	price = 25
	items = list(
		/obj/item/storage/backpack/toxins
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_hydroponics
	category = "operations"
	name = "herbalist's backpack"
	supplier = "Hub"
	description = "A backpack for the discerning botanist."
	price = 25
	items = list(
		/obj/item/storage/backpack/hydroponics
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_pharmacy
	category = "operations"
	name = "pharmacy backpack"
	supplier = "Hub"
	description = "A backpack for carrying pharmaceutical supplies."
	price = 25
	items = list(
		/obj/item/storage/backpack/pharmacy
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_psychiatrist
	category = "operations"
	name = "psychiatrist backpack"
	supplier = "Hub"
	description = "A discreet backpack for psychiatric staff."
	price = 25
	items = list(
		/obj/item/storage/backpack/psychiatrist
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_emt
	category = "operations"
	name = "EMT's backpack"
	supplier = "Hub"
	description = "A high-visibility backpack for emergency medical response."
	price = 25
	items = list(
		/obj/item/storage/backpack/emt
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_captain
	category = "operations"
	name = "captain's backpack"
	supplier = "Hub"
	description = "A luxurious backpack befitting a ship's captain."
	price = 45
	items = list(
		/obj/item/storage/backpack/captain
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_cmo
	category = "operations"
	name = "CMO's backpack"
	supplier = "Hub"
	description = "A backpack for the Chief Medical Officer."
	price = 45
	items = list(
		/obj/item/storage/backpack/cmo
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_hos
	category = "operations"
	name = "HOS' backpack"
	supplier = "Hub"
	description = "A backpack for the Head of Security."
	price = 45
	items = list(
		/obj/item/storage/backpack/hos
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_ce
	category = "operations"
	name = "CE's backpack"
	supplier = "Hub"
	description = "A backpack for the Chief Engineer."
	price = 45
	items = list(
		/obj/item/storage/backpack/ce
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_rd
	category = "operations"
	name = "RD's backpack"
	supplier = "Hub"
	description = "A backpack for the Research Director."
	price = 45
	items = list(
		/obj/item/storage/backpack/rd
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_om
	category = "operations"
	name = "OM's backpack"
	supplier = "Hub"
	description = "A backpack for the Operations Manager."
	price = 45
	items = list(
		/obj/item/storage/backpack/om
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_zavod
	category = "operations"
	name = "zavodskoi backpack"
	supplier = "Hub"
	description = "A backpack in Zavodskoi Interstellar livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/zavod
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_nt
	category = "operations"
	name = "nanotrasen backpack"
	supplier = "Hub"
	description = "A backpack in NanoTrasen livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/nt
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_zeng
	category = "operations"
	name = "zeng-hu backpack"
	supplier = "Hub"
	description = "A backpack in Zeng-Hu Pharmaceuticals livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/zeng
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_heph
	category = "operations"
	name = "hephaestus backpack"
	supplier = "Hub"
	description = "A backpack in Hephaestus Industries livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/heph
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_idris
	category = "operations"
	name = "idris backpack"
	supplier = "Hub"
	description = "A backpack in Idris Incorporated livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/idris
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_orion
	category = "operations"
	name = "orion backpack"
	supplier = "Hub"
	description = "A backpack in Orion Express livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/orion
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_backpack_pmcg
	category = "operations"
	name = "PMCG backpack"
	supplier = "Hub"
	description = "A backpack in Private Military Contracting Group livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/pmcg
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

// ---------------------------------------------------------------------------
// SATCHELS
// ---------------------------------------------------------------------------

/singleton/cargo_item/bag_satchel
	category = "operations"
	name = "satchel"
	supplier = "Hub"
	description = "A simple shoulder satchel."
	price = 25
	items = list(
		/obj/item/storage/backpack/satchel
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_eng
	category = "operations"
	name = "industrial satchel"
	supplier = "Hub"
	description = "A tough satchel for engineering work."
	price = 25
	items = list(
		/obj/item/storage/backpack/satchel/eng
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_med
	category = "operations"
	name = "medical satchel"
	supplier = "Hub"
	description = "A satchel in sterile medical white."
	price = 25
	items = list(
		/obj/item/storage/backpack/satchel/med
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_pharm
	category = "operations"
	name = "pharmacist satchel"
	supplier = "Hub"
	description = "A satchel for carrying pharmaceutical supplies."
	price = 25
	items = list(
		/obj/item/storage/backpack/satchel/pharm
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_psych
	category = "operations"
	name = "psychiatrist satchel"
	supplier = "Hub"
	description = "A discreet satchel for psychiatric staff."
	price = 25
	items = list(
		/obj/item/storage/backpack/satchel/psych
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_emt
	category = "operations"
	name = "EMT's satchel"
	supplier = "Hub"
	description = "A high-visibility satchel for emergency medical response."
	price = 25
	items = list(
		/obj/item/storage/backpack/satchel/emt
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_tox
	category = "operations"
	name = "scientist satchel"
	supplier = "Hub"
	description = "A satchel designed for laboratory use."
	price = 25
	items = list(
		/obj/item/storage/backpack/satchel/tox
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_sec
	category = "operations"
	name = "security satchel"
	supplier = "Hub"
	description = "A robust satchel in security black and red."
	price = 25
	items = list(
		/obj/item/storage/backpack/satchel/sec
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_hyd
	category = "operations"
	name = "hydroponics satchel"
	supplier = "Hub"
	description = "A satchel for the discerning botanist."
	price = 25
	items = list(
		/obj/item/storage/backpack/satchel/hyd
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_cap
	category = "operations"
	name = "captain's satchel"
	supplier = "Hub"
	description = "A luxurious satchel befitting a ship's captain."
	price = 45
	items = list(
		/obj/item/storage/backpack/satchel/cap
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_cmo
	category = "operations"
	name = "CMO's satchel"
	supplier = "Hub"
	description = "A satchel for the Chief Medical Officer."
	price = 45
	items = list(
		/obj/item/storage/backpack/satchel/cmo
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_hos
	category = "operations"
	name = "HOS' satchel"
	supplier = "Hub"
	description = "A satchel for the Head of Security."
	price = 45
	items = list(
		/obj/item/storage/backpack/satchel/hos
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_ce
	category = "operations"
	name = "CE's satchel"
	supplier = "Hub"
	description = "A satchel for the Chief Engineer."
	price = 45
	items = list(
		/obj/item/storage/backpack/satchel/ce
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_rd
	category = "operations"
	name = "RD's satchel"
	supplier = "Hub"
	description = "A satchel for the Research Director."
	price = 45
	items = list(
		/obj/item/storage/backpack/satchel/rd
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_om
	category = "operations"
	name = "OM's satchel"
	supplier = "Hub"
	description = "A satchel for the Operations Manager."
	price = 45
	items = list(
		/obj/item/storage/backpack/satchel/om
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_zavod
	category = "operations"
	name = "zavodskoi satchel"
	supplier = "Hub"
	description = "A satchel in Zavodskoi Interstellar livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/satchel/zavod
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_nt
	category = "operations"
	name = "nanotrasen satchel"
	supplier = "Hub"
	description = "A satchel in NanoTrasen livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/satchel/nt
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_zeng
	category = "operations"
	name = "zeng-hu satchel"
	supplier = "Hub"
	description = "A satchel in Zeng-Hu Pharmaceuticals livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/satchel/zeng
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_heph
	category = "operations"
	name = "hephaestus satchel"
	supplier = "Hub"
	description = "A satchel in Hephaestus Industries livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/satchel/heph
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_idris
	category = "operations"
	name = "idris satchel"
	supplier = "Hub"
	description = "A satchel in Idris Incorporated livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/satchel/idris
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_orion
	category = "operations"
	name = "orion satchel"
	supplier = "Hub"
	description = "A satchel in Orion Express livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/satchel/orion
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

// Listed as "pmcg satchel" rather than the item's own name: upstream this type is
// misnamed "PMCG backpack" (backpack.dm:568), which would collide with the real
// PMCG backpack entry above and silently overwrite it in SScargo.cargo_items.
/singleton/cargo_item/bag_satchel_pmcg
	category = "operations"
	name = "pmcg satchel"
	supplier = "Hub"
	description = "A satchel in Private Military Contracting Group livery."
	price = 30
	items = list(
		/obj/item/storage/backpack/satchel/pmcg
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_leather
	category = "operations"
	name = "leather satchel"
	supplier = "Hub"
	description = "A classic satchel in tanned leather."
	price = 30
	items = list(
		/obj/item/storage/backpack/satchel/leather
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_satchel_leather_recolorable
	category = "operations"
	name = "leather satchel (customisable)"
	supplier = "Hub"
	description = "A leather satchel supplied undyed, ready to be coloured to taste."
	price = 30
	items = list(
		/obj/item/storage/backpack/satchel/leather/recolorable
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_pocketbook
	category = "operations"
	name = "leather pocketbook"
	supplier = "Hub"
	description = "A compact leather pocketbook."
	price = 25
	items = list(
		/obj/item/storage/backpack/satchel/pocketbook
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_pocketbook_recolorable
	category = "operations"
	name = "leather pocketbook (customisable)"
	supplier = "Hub"
	description = "A leather pocketbook supplied undyed, ready to be coloured to taste."
	price = 25
	items = list(
		/obj/item/storage/backpack/satchel/pocketbook/recolorable
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_purse
	category = "operations"
	name = "purse"
	supplier = "Hub"
	description = "A small and stylish purse."
	price = 20
	items = list(
		/obj/item/storage/backpack/satchel/pocketbook/purse
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

// ---------------------------------------------------------------------------
// DUFFEL BAGS
// Larger capacity than a backpack, but cannot be opened while worn.
// ---------------------------------------------------------------------------

/singleton/cargo_item/bag_duffel
	category = "operations"
	name = "duffel bag"
	supplier = "Hub"
	description = "A capacious duffel bag. Must be taken off to be opened."
	price = 40
	items = list(
		/obj/item/storage/backpack/duffel
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_hyd
	category = "operations"
	name = "botanist's duffel bag"
	supplier = "Hub"
	description = "A roomy duffel bag for the discerning botanist."
	price = 40
	items = list(
		/obj/item/storage/backpack/duffel/hyd
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_med
	category = "operations"
	name = "medical duffel bag"
	supplier = "Hub"
	description = "A roomy duffel bag in sterile medical white."
	price = 40
	items = list(
		/obj/item/storage/backpack/duffel/med
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_eng
	category = "operations"
	name = "industrial duffel bag"
	supplier = "Hub"
	description = "A hard-wearing duffel bag for engineering work."
	price = 40
	items = list(
		/obj/item/storage/backpack/duffel/eng
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_tox
	category = "operations"
	name = "scientist's duffel bag"
	supplier = "Hub"
	description = "A roomy duffel bag designed for laboratory use."
	price = 40
	items = list(
		/obj/item/storage/backpack/duffel/tox
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_sec
	category = "operations"
	name = "security duffel bag"
	supplier = "Hub"
	description = "A robust duffel bag in security black and red."
	price = 40
	items = list(
		/obj/item/storage/backpack/duffel/sec
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_pharm
	category = "operations"
	name = "pharmacy duffel bag"
	supplier = "Hub"
	description = "A roomy duffel bag for pharmaceutical supplies."
	price = 40
	items = list(
		/obj/item/storage/backpack/duffel/pharm
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_psych
	category = "operations"
	name = "psychiatrist duffel bag"
	supplier = "Hub"
	description = "A discreet duffel bag for psychiatric staff."
	price = 40
	items = list(
		/obj/item/storage/backpack/duffel/psych
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_emt
	category = "operations"
	name = "EMT's duffel bag"
	supplier = "Hub"
	description = "A high-visibility duffel bag for emergency medical response."
	price = 40
	items = list(
		/obj/item/storage/backpack/duffel/emt
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_cap
	category = "operations"
	name = "captain's duffel bag"
	supplier = "Hub"
	description = "A luxurious duffel bag befitting a ship's captain."
	price = 60
	items = list(
		/obj/item/storage/backpack/duffel/cap
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_cmo
	category = "operations"
	name = "CMO's duffel"
	supplier = "Hub"
	description = "A duffel bag for the Chief Medical Officer."
	price = 60
	items = list(
		/obj/item/storage/backpack/duffel/cmo
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_hos
	category = "operations"
	name = "HOS' duffel"
	supplier = "Hub"
	description = "A duffel bag for the Head of Security."
	price = 60
	items = list(
		/obj/item/storage/backpack/duffel/hos
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_ce
	category = "operations"
	name = "CE's duffel"
	supplier = "Hub"
	description = "A duffel bag for the Chief Engineer."
	price = 60
	items = list(
		/obj/item/storage/backpack/duffel/ce
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_rd
	category = "operations"
	name = "RD's duffel"
	supplier = "Hub"
	description = "A duffel bag for the Research Director."
	price = 60
	items = list(
		/obj/item/storage/backpack/duffel/rd
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_om
	category = "operations"
	name = "OM's duffel"
	supplier = "Hub"
	description = "A duffel bag for the Operations Manager."
	price = 60
	items = list(
		/obj/item/storage/backpack/duffel/om
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_zavod
	category = "operations"
	name = "zavodskoi duffel"
	supplier = "Hub"
	description = "A duffel bag in Zavodskoi Interstellar livery."
	price = 45
	items = list(
		/obj/item/storage/backpack/duffel/zavod
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_nt
	category = "operations"
	name = "nanotrasen duffel"
	supplier = "Hub"
	description = "A duffel bag in NanoTrasen livery."
	price = 45
	items = list(
		/obj/item/storage/backpack/duffel/nt
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_zeng
	category = "operations"
	name = "zeng-hu duffel"
	supplier = "Hub"
	description = "A duffel bag in Zeng-Hu Pharmaceuticals livery."
	price = 45
	items = list(
		/obj/item/storage/backpack/duffel/zeng
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_heph
	category = "operations"
	name = "hephaestus duffel"
	supplier = "Hub"
	description = "A duffel bag in Hephaestus Industries livery."
	price = 45
	items = list(
		/obj/item/storage/backpack/duffel/heph
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_idris
	category = "operations"
	name = "idris duffel"
	supplier = "Hub"
	description = "A duffel bag in Idris Incorporated livery."
	price = 45
	items = list(
		/obj/item/storage/backpack/duffel/idris
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_orion
	category = "operations"
	name = "orion duffel"
	supplier = "Hub"
	description = "A duffel bag in Orion Express livery."
	price = 45
	items = list(
		/obj/item/storage/backpack/duffel/orion
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_duffel_pmcg
	category = "operations"
	name = "PMCG duffel"
	supplier = "Hub"
	description = "A duffel bag in Private Military Contracting Group livery."
	price = 45
	items = list(
		/obj/item/storage/backpack/duffel/pmcg
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

// ---------------------------------------------------------------------------
// MESSENGER BAGS
// ---------------------------------------------------------------------------

/singleton/cargo_item/bag_messenger
	category = "operations"
	name = "messenger bag"
	supplier = "Hub"
	description = "A slung messenger bag."
	price = 30
	items = list(
		/obj/item/storage/backpack/messenger
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_pharm
	category = "operations"
	name = "pharmacy messenger bag"
	supplier = "Hub"
	description = "A messenger bag for carrying pharmaceutical supplies."
	price = 30
	items = list(
		/obj/item/storage/backpack/messenger/pharm
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_psych
	category = "operations"
	name = "psychiatrist messenger bag"
	supplier = "Hub"
	description = "A discreet messenger bag for psychiatric staff."
	price = 30
	items = list(
		/obj/item/storage/backpack/messenger/psych
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_emt
	category = "operations"
	name = "EMT's messenger bag"
	supplier = "Hub"
	description = "A high-visibility messenger bag for emergency medical response."
	price = 30
	items = list(
		/obj/item/storage/backpack/messenger/emt
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_med
	category = "operations"
	name = "medical messenger bag"
	supplier = "Hub"
	description = "A messenger bag in sterile medical white."
	price = 30
	items = list(
		/obj/item/storage/backpack/messenger/med
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_tox
	category = "operations"
	name = "research messenger bag"
	supplier = "Hub"
	description = "A messenger bag designed for laboratory use."
	price = 30
	items = list(
		/obj/item/storage/backpack/messenger/tox
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_engi
	category = "operations"
	name = "engineering messenger bag"
	supplier = "Hub"
	description = "A hard-wearing messenger bag for engineering work."
	price = 30
	items = list(
		/obj/item/storage/backpack/messenger/engi
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_hyd
	category = "operations"
	name = "hydroponics messenger bag"
	supplier = "Hub"
	description = "A messenger bag for the discerning botanist."
	price = 30
	items = list(
		/obj/item/storage/backpack/messenger/hyd
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_sec
	category = "operations"
	name = "security messenger bag"
	supplier = "Hub"
	description = "A robust messenger bag in security black and red."
	price = 30
	items = list(
		/obj/item/storage/backpack/messenger/sec
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_com
	category = "operations"
	name = "captain's messenger bag"
	supplier = "Hub"
	description = "A luxurious messenger bag befitting a ship's captain."
	price = 50
	items = list(
		/obj/item/storage/backpack/messenger/com
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_cmo
	category = "operations"
	name = "CMO's messenger bag"
	supplier = "Hub"
	description = "A messenger bag for the Chief Medical Officer."
	price = 50
	items = list(
		/obj/item/storage/backpack/messenger/cmo
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_hos
	category = "operations"
	name = "HOS' messenger bag"
	supplier = "Hub"
	description = "A messenger bag for the Head of Security."
	price = 50
	items = list(
		/obj/item/storage/backpack/messenger/hos
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_ce
	category = "operations"
	name = "CE's messenger bag"
	supplier = "Hub"
	description = "A messenger bag for the Chief Engineer."
	price = 50
	items = list(
		/obj/item/storage/backpack/messenger/ce
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_rd
	category = "operations"
	name = "RD's messenger bag"
	supplier = "Hub"
	description = "A messenger bag for the Research Director."
	price = 50
	items = list(
		/obj/item/storage/backpack/messenger/rd
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_om
	category = "operations"
	name = "OM's messenger bag"
	supplier = "Hub"
	description = "A messenger bag for the Operations Manager."
	price = 50
	items = list(
		/obj/item/storage/backpack/messenger/om
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_zavod
	category = "operations"
	name = "zavodskoi messenger bag"
	supplier = "Hub"
	description = "A messenger bag in Zavodskoi Interstellar livery."
	price = 35
	items = list(
		/obj/item/storage/backpack/messenger/zavod
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_nt
	category = "operations"
	name = "nanotrasen messenger bag"
	supplier = "Hub"
	description = "A messenger bag in NanoTrasen livery."
	price = 35
	items = list(
		/obj/item/storage/backpack/messenger/nt
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_zeng
	category = "operations"
	name = "zeng-hu messenger bag"
	supplier = "Hub"
	description = "A messenger bag in Zeng-Hu Pharmaceuticals livery."
	price = 35
	items = list(
		/obj/item/storage/backpack/messenger/zeng
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_heph
	category = "operations"
	name = "hephaestus messenger bag"
	supplier = "Hub"
	description = "A messenger bag in Hephaestus Industries livery."
	price = 35
	items = list(
		/obj/item/storage/backpack/messenger/heph
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_idris
	category = "operations"
	name = "idris messenger bag"
	supplier = "Hub"
	description = "A messenger bag in Idris Incorporated livery."
	price = 35
	items = list(
		/obj/item/storage/backpack/messenger/idris
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_orion
	category = "operations"
	name = "orion messenger bag"
	supplier = "Hub"
	description = "A messenger bag in Orion Express livery."
	price = 35
	items = list(
		/obj/item/storage/backpack/messenger/orion
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_messenger_pmcg
	category = "operations"
	name = "PMCG messenger bag"
	supplier = "Hub"
	description = "A messenger bag in Private Military Contracting Group livery."
	price = 35
	items = list(
		/obj/item/storage/backpack/messenger/pmcg
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

// ---------------------------------------------------------------------------
// RUCKSACKS
// ---------------------------------------------------------------------------

/singleton/cargo_item/bag_rucksack
	category = "operations"
	name = "black rucksack"
	supplier = "Hub"
	description = "A plain rucksack in black."
	price = 35
	items = list(
		/obj/item/storage/backpack/rucksack
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_rucksack_recolorable
	category = "operations"
	name = "rucksack (customisable)"
	supplier = "Hub"
	description = "A rucksack supplied undyed, ready to be coloured to taste."
	price = 35
	items = list(
		/obj/item/storage/backpack/rucksack/recolorable
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_rucksack_blue
	category = "operations"
	name = "blue rucksack"
	supplier = "Hub"
	description = "A plain rucksack in blue."
	price = 35
	items = list(
		/obj/item/storage/backpack/rucksack/blue
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_rucksack_green
	category = "operations"
	name = "green rucksack"
	supplier = "Hub"
	description = "A plain rucksack in green."
	price = 35
	items = list(
		/obj/item/storage/backpack/rucksack/green
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_rucksack_navy
	category = "operations"
	name = "navy rucksack"
	supplier = "Hub"
	description = "A plain rucksack in navy."
	price = 35
	items = list(
		/obj/item/storage/backpack/rucksack/navy
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_rucksack_tan
	category = "operations"
	name = "tan rucksack"
	supplier = "Hub"
	description = "A plain rucksack in tan."
	price = 35
	items = list(
		/obj/item/storage/backpack/rucksack/tan
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

// ---------------------------------------------------------------------------
// SPECIALIST
// ---------------------------------------------------------------------------

/singleton/cargo_item/bag_chestpouch
	category = "operations"
	name = "chest pouch"
	supplier = "Hub"
	description = "A bulky pouch worn across the chest."
	price = 40
	items = list(
		/obj/item/storage/backpack/chestpouch
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_kala
	category = "operations"
	name = "skrell backpack"
	supplier = "Hub"
	description = "A backpack of Skrellian design."
	price = 30
	items = list(
		/obj/item/storage/backpack/kala
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1

/singleton/cargo_item/bag_cell
	category = "operations"
	name = "power cell backpack"
	supplier = "Hub"
	description = "A specialised backpack that carries nothing but power cells, ten at a time."
	price = 120
	items = list(
		/obj/item/storage/backpack/cell
	)
	access = 0
	container_type = "crate"
	groupable = TRUE
	spawn_amount = 1
