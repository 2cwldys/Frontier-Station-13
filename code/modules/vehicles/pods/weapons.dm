/*
 * Pod main weapon slot -- fires without a handheld gun item, using the same
 * primitive porta_turret.dm's shootAt() uses (preparePixelProjectile() +
 * fire()) rather than the full ammo/firemode/charge-cell gun-item wrapper,
 * which doesn't map cleanly onto "a fixed weapon bolted to a vehicle."
 */
/obj/item/podcomponent/mainweapon
	name = "pod phaser"
	desc = "A light energy weapon mount for a space pod."
	icon = 'icons/obj/vehicle/pod_weapons.dmi'
	icon_state = "class-a"
	power_used = 40

	/// Projectile fired -- a plain beam/laser bolt, not the "practice" (harmless) variant.
	var/projectile_type = /obj/projectile/beam
	/// Deciseconds between shots.
	var/fire_delay = 6
	var/last_fired = 0
	/// How many tiles ahead (in the pod's facing direction) to aim at.
	var/range = 9

/obj/item/podcomponent/mainweapon/get_slot()
	return POD_PART_MAIN_WEAPON

/// Fires one shot straight ahead in the pod's current facing direction.
/// Returns FALSE (and does nothing) if off, disrupted, uninstalled, or
/// still on cooldown.
/obj/item/podcomponent/mainweapon/proc/Fire(mob/user)
	if(!active || disrupted || !pod)
		return FALSE
	if(world.time < last_fired + fire_delay)
		return FALSE
	last_fired = world.time

	var/turf/origin = get_turf(pod)
	var/turf/target = get_ranged_target_turf(pod, pod.dir, range)
	var/obj/projectile/P = new projectile_type(origin)
	P.preparePixelProjectile(target, origin)
	P.firer = pod
	P.fired_from = pod
	P.fire()
	playsound(pod, 'sound/weapons/Taser.ogg', 50, 1)
	return TRUE
