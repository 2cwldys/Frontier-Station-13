/*
 * Phase 1's one buildable pod variant + its construction recipe. A 7-stage
 * build hitting the major beats: secure the frame, weld, wire it, plate it,
 * install the engine, seal the exterior, glass the cockpit. Later phases
 * can layer in more construction stages and an armor-skin system without
 * disturbing this path.
 */
/obj/vehicle/bike/pod/mini
	name = "mini pod"
	desc = "A small, single-seat space pod."
	ship_sprite = "miniputt"

#define POD_FRAME_STAGE_WRENCH 0
#define POD_FRAME_STAGE_WELD_JOINTS 1
#define POD_FRAME_STAGE_CABLE 2
#define POD_FRAME_STAGE_PLATING 3
#define POD_FRAME_STAGE_ENGINE 4
#define POD_FRAME_STAGE_WELD_EXTERIOR 5
#define POD_FRAME_STAGE_GLASS 6

/obj/item/pod_frame_kit
	name = "pod frame kit"
	desc = "You can hear an awful lot of junk rattling around in this box."
	icon = 'icons/obj/vehicle/pod_ship.dmi'
	icon_state = "parts"
	/// Which /obj/structure/pod_frame subtype this kit dumps out -- lets
	/// each ship variant below have its own matching kit without repeating
	/// attack_self().
	var/frame_type = /obj/structure/pod_frame

/obj/item/pod_frame_kit/attack_self(mob/user)
	to_chat(user, SPAN_NOTICE("You dump out the box of parts onto the floor."))
	new frame_type(get_turf(user))
	qdel(src)

/obj/structure/pod_frame
	name = "pod frame"
	desc = "A space pod under construction."
	icon = 'icons/obj/vehicle/pod_ship.dmi'
	icon_state = "frame"
	anchored = TRUE
	density = TRUE

	var/stage = POD_FRAME_STAGE_WRENCH
	var/cable_amt = 2
	var/metal_amt = 3
	var/glass_amt = 2
	var/vehicle_type = /obj/vehicle/bike/pod/mini
	/// Held here between POD_FRAME_STAGE_ENGINE and POD_FRAME_STAGE_GLASS --
	/// the vehicle doesn't exist yet when the engine is bolted in, so it
	/// can't be install_part()'d until the frame finishes into a real pod.
	var/obj/item/podcomponent/engine/held_engine

/obj/structure/pod_frame/attackby(obj/item/attacking_item, mob/user)
	switch(stage)
		if(POD_FRAME_STAGE_WRENCH)
			if(attacking_item.tool_behaviour == TOOL_WRENCH)
				to_chat(user, SPAN_NOTICE("You begin to secure the frame..."))
				if(!do_after(user, 3 SECONDS, src))
					return
				to_chat(user, SPAN_NOTICE("You wrench the frame parts together."))
				stage = POD_FRAME_STAGE_WELD_JOINTS
			else
				to_chat(user, SPAN_WARNING("If only there was some way to secure all this junk together! You should get a wrench."))

		if(POD_FRAME_STAGE_WELD_JOINTS)
			if(attacking_item.tool_behaviour == TOOL_WELDER)
				var/obj/item/weldingtool/W = attacking_item
				if(!W.use(1, user))
					return
				to_chat(user, SPAN_NOTICE("You begin to weld the joints of the frame..."))
				if(!do_after(user, 3 SECONDS, src))
					return
				to_chat(user, SPAN_NOTICE("You weld the joints of the frame together."))
				stage = POD_FRAME_STAGE_CABLE
			else
				to_chat(user, SPAN_WARNING("The joints of this frame still feel pretty wobbly. Welding it will make it sturdy."))

		if(POD_FRAME_STAGE_CABLE)
			var/obj/item/stack/cable_coil/C = attacking_item
			if(istype(C))
				if(C.get_amount() < cable_amt)
					to_chat(user, SPAN_WARNING("You need at least [cable_amt] lengths of cable."))
					return
				to_chat(user, SPAN_NOTICE("You begin to install the wiring..."))
				if(!do_after(user, 3 SECONDS, src) || !C.use(cable_amt))
					return
				to_chat(user, SPAN_NOTICE("You wire the frame's internal systems."))
				stage = POD_FRAME_STAGE_PLATING
			else
				to_chat(user, SPAN_WARNING("You're not gonna get very far without power cables. You need at least [cable_amt] lengths."))

		if(POD_FRAME_STAGE_PLATING)
			var/obj/item/stack/material/steel/S = attacking_item
			if(istype(S))
				if(S.get_amount() < metal_amt)
					to_chat(user, SPAN_WARNING("You need at least [metal_amt] metal sheets to plate the hull."))
					return
				to_chat(user, SPAN_NOTICE("You begin to install the internal plating..."))
				if(!do_after(user, 3 SECONDS, src) || !S.use(metal_amt))
					return
				to_chat(user, SPAN_NOTICE("You plate over the frame's internals."))
				stage = POD_FRAME_STAGE_ENGINE
			else
				to_chat(user, SPAN_WARNING("The internals are exposed and unsafe. You'll need [metal_amt] sheets of metal to cover them."))

		if(POD_FRAME_STAGE_ENGINE)
			var/obj/item/podcomponent/engine/E = attacking_item
			if(istype(E))
				user.drop_from_inventory(E, src)
				to_chat(user, SPAN_NOTICE("You begin to install the engine..."))
				if(!do_after(user, 3 SECONDS, src))
					return
				to_chat(user, SPAN_NOTICE("You bolt the engine into place."))
				E.forceMove(src)
				held_engine = E
				stage = POD_FRAME_STAGE_WELD_EXTERIOR
			else
				to_chat(user, SPAN_WARNING("Having an engine installed would help."))

		if(POD_FRAME_STAGE_WELD_EXTERIOR)
			if(attacking_item.tool_behaviour == TOOL_WELDER)
				var/obj/item/weldingtool/W = attacking_item
				if(!W.use(1, user))
					return
				to_chat(user, SPAN_NOTICE("You begin to weld the exterior seams..."))
				if(!do_after(user, 3 SECONDS, src))
					return
				to_chat(user, SPAN_NOTICE("You weld the outer hull airtight."))
				stage = POD_FRAME_STAGE_GLASS
			else
				to_chat(user, SPAN_WARNING("The outer hull still feels pretty loose. Welding it would make it airtight."))

		if(POD_FRAME_STAGE_GLASS)
			var/obj/item/stack/material/glass/reinforced/G = attacking_item
			if(istype(G))
				if(G.get_amount() < glass_amt)
					to_chat(user, SPAN_WARNING("You need at least [glass_amt] reinforced glass sheets for the cockpit."))
					return
				to_chat(user, SPAN_NOTICE("You begin to install the cockpit glass..."))
				if(!do_after(user, 3 SECONDS, src) || !G.use(glass_amt))
					return
				to_chat(user, SPAN_NOTICE("With the cockpit sealed, the pod is ready to fly."))
				var/obj/vehicle/bike/pod/V = new vehicle_type(loc)
				V.set_dir(dir)
				if(held_engine)
					V.install_part(null, held_engine)
				qdel(src)
			else
				to_chat(user, SPAN_WARNING("You'll need a sealed cockpit before this flies anywhere -- [glass_amt] reinforced glass sheets will do."))

/*
 * Phase 3: eight more buildable variants, each reusing the same 7-stage
 * recipe above via pod_frame's vehicle_type -- flavor/stat differences only,
 * no new mechanics (except cargo, which comes pre-fitted with a cargo hold).
 * Ship variants below use hull sprites from pod_ship.dmi; more variants can
 * be added later as more art becomes available.
 */
/obj/vehicle/bike/pod/recon
	name = "recon pod"
	desc = "A stripped-down space pod built for speed over survivability."
	ship_sprite = "recon"
	health = 90
	maxhealth = 90
	land_speed = 1.1
	space_speed = 0.7

/obj/item/pod_frame_kit/recon
	name = "recon pod frame kit"
	frame_type = /obj/structure/pod_frame/recon

/obj/structure/pod_frame/recon
	vehicle_type = /obj/vehicle/bike/pod/recon

/obj/vehicle/bike/pod/cargo
	name = "cargo pod"
	desc = "A space pod with a built-in cargo hold, at the cost of some speed."
	ship_sprite = "cargo"
	land_speed = 1.7
	space_speed = 1.3

/obj/vehicle/bike/pod/cargo/Initialize()
	. = ..()
	install_part(null, new /obj/item/podcomponent/secondary/cargo(src))

/obj/item/pod_frame_kit/cargo
	name = "cargo pod frame kit"
	frame_type = /obj/structure/pod_frame/cargo

/obj/structure/pod_frame/cargo
	vehicle_type = /obj/vehicle/bike/pod/cargo

/obj/vehicle/bike/pod/saucer
	name = "saucer pod"
	desc = "A space pod built in an unmistakable saucer shape."
	ship_sprite = "saucer"

/obj/item/pod_frame_kit/saucer
	name = "saucer pod frame kit"
	frame_type = /obj/structure/pod_frame/saucer

/obj/structure/pod_frame/saucer
	vehicle_type = /obj/vehicle/bike/pod/saucer

/obj/vehicle/bike/pod/slick
	name = "slick pod"
	desc = "A sleek, fast space pod that trades armor plating for a sharper hull."
	ship_sprite = "putt_wizard"
	health = 100
	maxhealth = 100
	land_speed = 1.1
	space_speed = 0.8

/obj/item/pod_frame_kit/slick
	name = "slick pod frame kit"
	frame_type = /obj/structure/pod_frame/slick

/obj/structure/pod_frame/slick
	vehicle_type = /obj/vehicle/bike/pod/slick

/obj/vehicle/bike/pod/corporate
	name = "corporate pod"
	desc = "A space pod finished in corporate livery."
	ship_sprite = "nanoputt"
	health = 150
	maxhealth = 150

/obj/item/pod_frame_kit/corporate
	name = "corporate pod frame kit"
	frame_type = /obj/structure/pod_frame/corporate

/obj/structure/pod_frame/corporate
	vehicle_type = /obj/vehicle/bike/pod/corporate

/obj/vehicle/bike/pod/heg
	name = "Hegemony-pattern pod"
	desc = "A space pod built to a Hegemony maintenance pattern."
	ship_sprite = "soviputt"
	health = 160
	maxhealth = 160
	land_speed = 1.6
	space_speed = 1.2

/obj/item/pod_frame_kit/heg
	name = "Hegemony-pattern pod frame kit"
	frame_type = /obj/structure/pod_frame/heg

/obj/structure/pod_frame/heg
	vehicle_type = /obj/vehicle/bike/pod/heg

/obj/vehicle/bike/pod/independent
	name = "independent pod"
	desc = "A no-frills civilian space pod, cheap and easy to build."
	ship_sprite = "indyputt"

/obj/item/pod_frame_kit/independent
	name = "independent pod frame kit"
	frame_type = /obj/structure/pod_frame/independent

/obj/structure/pod_frame/independent
	vehicle_type = /obj/vehicle/bike/pod/independent

/obj/vehicle/bike/pod/escape
	name = "escape pod"
	desc = "A minimal, cheaply-built pod meant to get one person out of danger, not into it."
	ship_sprite = "escape"
	health = 80
	maxhealth = 80

/obj/item/pod_frame_kit/escape
	name = "escape pod frame kit"
	frame_type = /obj/structure/pod_frame/escape

/obj/structure/pod_frame/escape
	vehicle_type = /obj/vehicle/bike/pod/escape

/*
 * "Stocked" hull variants -- used only by the fully-built cargo packs
 * (code/modules/cargo/items/operations.dm), never by the from-scratch
 * construction recipe above (pod_frame's vehicle_type vars still point at
 * the plain hull types, unchanged). Each just installs a bare, unfueled
 * engine on spawn, matching the from-scratch recipe's own requirement that
 * a pod can't be completed without one -- a cargo-bought "fully built" pod
 * shouldn't be any less complete than one someone assembled by hand.
 */
/obj/vehicle/bike/pod/mini/stocked/Initialize(mapload)
	. = ..()
	install_part(null, new /obj/item/podcomponent/engine(src))

/obj/vehicle/bike/pod/recon/stocked/Initialize(mapload)
	. = ..()
	install_part(null, new /obj/item/podcomponent/engine(src))

/obj/vehicle/bike/pod/cargo/stocked/Initialize(mapload)
	. = ..()
	install_part(null, new /obj/item/podcomponent/engine(src))

/obj/vehicle/bike/pod/saucer/stocked/Initialize(mapload)
	. = ..()
	install_part(null, new /obj/item/podcomponent/engine(src))

/obj/vehicle/bike/pod/slick/stocked/Initialize(mapload)
	. = ..()
	install_part(null, new /obj/item/podcomponent/engine(src))

/obj/vehicle/bike/pod/corporate/stocked/Initialize(mapload)
	. = ..()
	install_part(null, new /obj/item/podcomponent/engine(src))

/obj/vehicle/bike/pod/heg/stocked/Initialize(mapload)
	. = ..()
	install_part(null, new /obj/item/podcomponent/engine(src))

/obj/vehicle/bike/pod/independent/stocked/Initialize(mapload)
	. = ..()
	install_part(null, new /obj/item/podcomponent/engine(src))

/obj/vehicle/bike/pod/escape/stocked/Initialize(mapload)
	. = ..()
	install_part(null, new /obj/item/podcomponent/engine(src))
