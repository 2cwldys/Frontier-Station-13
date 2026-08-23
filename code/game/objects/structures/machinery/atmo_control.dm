#define SIGNAL_OXYGEN 1
#define SIGNAL_PHORON 2
#define SIGNAL_NITROGEN 4
#define SIGNAL_CARBON_DIOXIDE 8
#define SIGNAL_HYDROGEN 16
#define SIGNAL_N2O 32
#define SIGNAL_HELIUM 64
#define SIGNAL_DEUTERIUM 128
#define SIGNAL_TRITIUM 256
#define SIGNAL_HELIUMFUEL 512
#define SIGNAL_SULFUR_DIOXIDE 1024
#define SIGNAL_NITROGEN_DIOXIDE 2048
#define SIGNAL_CHLORINE 4096
#define SIGNAL_WATERVAPOR 8192

/obj/structure/machinery/air_sensor
	name = "gas sensor"
	desc = "Measures the gas content of the atmosphere around the sensor."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "gsensor1"
	anchored = TRUE

	var/state = 0

	var/id_tag
	var/frequency = 1439

	var/on = 1
	var/output = 0
	var/output_pressure = TRUE
	var/output_temperature = TRUE
	//Flags:
	// 1 for oxygen concentration
	// 2 for phoron concentration
	// 4 for nitrogen concentration
	// 8 for carbon dioxide concentration
	// 16 for hydrogen concentration
	// 32 for nitrous oxide concentration
	// 64 for helium concentration
	// 128 for deuterium concentration
	// 256 for tritium concentration
	// 512 for helium-3 concentration
	// 1024 for sulfur dioxide concentration
	// 2048 for nitrogen dioxide concentration
	// 4096 for chlorine concentration
	// 8192 for water vapor concentration

	var/datum/radio_frequency/radio_connection

/// Auto-assigns a unique id_tag the first time this sensor is linked to a
/// console -- mirrors _ensure_id_tag() on airlocks/vent pumps/injectors.
/// id_tag is what the sensor stamps on its broadcasts and what the console
/// keys its `sensors` list by, and it is mapper-authored only, so a built
/// sensor would otherwise stay null and collide with every other blank one.
/obj/structure/machinery/air_sensor/proc/_ensure_id_tag()
	if(!id_tag)
		id_tag = "sensor_[REF(src)]"
	return id_tag

/// Multitool linking to any atmos console -- buffer either end, click the
/// other. Same buffer-toggle shape used by the injector and vent pump.
/obj/structure/machinery/air_sensor/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		var/obj/item/multitool/MT = attacking_item
		var/obj/structure/machinery/computer/general_air_control/console = MT.get_buffer(/obj/structure/machinery/computer/general_air_control)
		if(!console)
			MT.set_buffer(src)
			to_chat(user, SPAN_NOTICE("You buffer \the [src] in \the [MT]."))
			return TRUE
		console._link_air_sensor(src, user)
		MT.set_buffer(null)
		return TRUE
	return ..()

/obj/structure/machinery/air_sensor/update_icon()
	icon_state = "gsensor[on]"

/obj/structure/machinery/air_sensor/process()
	if(on)
		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO
		signal.data["tag"] = id_tag
		signal.data["timestamp"] = world.time

		var/datum/gas_mixture/air_sample = return_air()

		if(output_pressure)
			signal.data["pressure"] = num2text(round(XGM_PRESSURE(air_sample),0.1),)
		if(output_temperature)
			signal.data["temperature"] = round(air_sample.temperature,0.1)

		if(output)
			var/total_moles = air_sample.total_moles
			if(total_moles > 0)
				if(output&SIGNAL_OXYGEN)
					signal.data[GAS_OXYGEN] = round(100*air_sample.gas[GAS_OXYGEN]/total_moles,0.1)
				if(output&SIGNAL_PHORON)
					signal.data[GAS_PHORON] = round(100*air_sample.gas[GAS_PHORON]/total_moles,0.1)
				if(output&SIGNAL_NITROGEN)
					signal.data[GAS_NITROGEN] = round(100*air_sample.gas[GAS_NITROGEN]/total_moles,0.1)
				if(output&SIGNAL_CARBON_DIOXIDE)
					signal.data[GAS_CO2] = round(100*air_sample.gas[GAS_CO2]/total_moles,0.1)
				if(output&SIGNAL_HYDROGEN)
					signal.data[GAS_HYDROGEN] = round(100*air_sample.gas[GAS_HYDROGEN]/total_moles,0.1)
				if(output&SIGNAL_N2O)
					signal.data[GAS_N2O] = round(100*air_sample.gas[GAS_N2O]/total_moles,0.1)
				if(output&SIGNAL_HELIUM)
					signal.data[GAS_HELIUM] = round(100*air_sample.gas[GAS_HELIUM]/total_moles,0.1)
				if(output&SIGNAL_DEUTERIUM)
					signal.data[GAS_DEUTERIUM] = round(100*air_sample.gas[GAS_DEUTERIUM]/total_moles,0.1)
				if(output&SIGNAL_TRITIUM)
					signal.data[GAS_TRITIUM] = round(100*air_sample.gas[GAS_TRITIUM]/total_moles,0.1)
				if(output&SIGNAL_HELIUMFUEL)
					signal.data[GAS_HELIUMFUEL] = round(100*air_sample.gas[GAS_HELIUMFUEL]/total_moles,0.1)
				if(output&SIGNAL_SULFUR_DIOXIDE)
					signal.data[GAS_SULFUR] = round(100*air_sample.gas[GAS_SULFUR]/total_moles,0.1)
				if(output&SIGNAL_NITROGEN_DIOXIDE)
					signal.data[GAS_NO2] = round(100*air_sample.gas[GAS_NO2]/total_moles,0.1)
				if(output&SIGNAL_CHLORINE)
					signal.data[GAS_CHLORINE] = round(100*air_sample.gas[GAS_CHLORINE]/total_moles,0.1)
				if(output&SIGNAL_WATERVAPOR)
					signal.data[GAS_WATERVAPOR] = round(100*air_sample.gas[GAS_WATERVAPOR]/total_moles,0.1)
			else
				signal.data[GAS_OXYGEN] = 0
				signal.data[GAS_PHORON] = 0
				signal.data[GAS_NITROGEN] = 0
				signal.data[GAS_CO2] = 0
				signal.data[GAS_HYDROGEN] = 0
				signal.data[GAS_N2O] = 0
				signal.data[GAS_HELIUM] = 0
				signal.data[GAS_DEUTERIUM] = 0
				signal.data[GAS_TRITIUM] = 0
				signal.data[GAS_HELIUMFUEL] = 0
				signal.data[GAS_SULFUR] = 0
				signal.data[GAS_NO2] = 0
				signal.data[GAS_CHLORINE] = 0
				signal.data[GAS_WATERVAPOR]= 0
		signal.data["sigtype"]="status"
		radio_connection.post_signal(src, signal, filter = RADIO_ATMOSIA)


/obj/structure/machinery/air_sensor/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection = SSradio.add_object(src, frequency, RADIO_ATMOSIA)

/obj/structure/machinery/air_sensor/Initialize()
	. = ..()
	set_frequency(frequency)

/obj/structure/machinery/air_sensor/Destroy()
	if(SSradio)
		SSradio.remove_object(src,frequency)
	return ..()

/obj/structure/machinery/computer/general_air_control
	name = "atmosphere monitoring console"
	desc = "A console that gives an atmospheric condition readout of various sensors connected to it."
	icon_screen = "tank"
	icon_keyboard = "cyan_key"
	icon_keyboard_emis = "cyan_key_mask"
	light_color = LIGHT_COLOR_CYAN

	var/frequency = 1439
	var/list/sensors = list()

	var/list/sensor_information = list()
	var/datum/radio_frequency/radio_connection
	ui_type = "AtmosControl"
	circuit = /obj/item/circuitboard/air_management

	// Input/output device linking (vent pump / outlet injector, as opposed to
	// the gas-sensor linking right above) lives here on the base rather than
	// only on large_tank_control below -- supermatter_core (further down)
	// already duplicates these same four vars and the UI/receive_signal code
	// that reads them, but had no way to ever populate them: no
	// _link_atmos_device() of its own and no multitool attackby() override to
	// call it, since that also only existed on large_tank_control. Declared
	// once here, both subtypes' own re-declarations below are removed in
	// favor of inheriting these.
	var/input_tag
	var/output_tag
	var/list/input_info
	var/list/output_info

/obj/structure/machinery/computer/general_air_control/Destroy()
	if(SSradio)
		SSradio.remove_object(src, frequency)
	return ..()

/obj/structure/machinery/computer/general_air_control/ui_data(mob/user)
	var/list/data = list("sensors" = list())
	data["control"] = null
	for(var/id_tag in sensors)
		var/long_name = sensors[id_tag]
		var/list/sdata = sensor_information[id_tag]
		var/list/sensor_data = list("id_tag" = id_tag, "name" = long_name)
		sensor_data["datapoints"] = list()
		for(var/datapoint in list("pressure", "temperature", GAS_OXYGEN, GAS_NITROGEN, GAS_CO2, GAS_PHORON, GAS_HYDROGEN, GAS_N2O, GAS_HELIUM, GAS_DEUTERIUM, GAS_TRITIUM, GAS_HELIUMFUEL, GAS_SULFUR, GAS_NO2, GAS_CHLORINE, GAS_WATERVAPOR))
			var/unit
			if(datapoint == "pressure")
				unit = "kPa"
			else if(datapoint == "temperature")
				unit = "K"
			else
				unit = "%"
			sensor_data["datapoints"] += list(list("datapoint" = datapoint, "data" = sdata[datapoint], "unit" = unit))
		data["sensors"] += list(sensor_data)
		sensor_data = list()
	return data

/obj/structure/machinery/computer/general_air_control/attack_hand(mob/user)
	ui_interact(user)

/obj/structure/machinery/computer/general_air_control/ui_interact(mob/user, var/datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, ui_type, "Atmospherics Control", 460, 470)
		ui.open()

/obj/structure/machinery/computer/general_air_control/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption) return

	var/id_tag = signal.data["tag"]
	if(!id_tag || !sensors.Find(id_tag)) return

	sensor_information[id_tag] = signal.data

/obj/structure/machinery/computer/general_air_control/proc/set_frequency(new_frequency)
	SSradio.remove_object(src, frequency)
	frequency = new_frequency
	radio_connection = SSradio.add_object(src, frequency, RADIO_ATMOSIA)

/obj/structure/machinery/computer/general_air_control/Initialize()
	. = ..()
	set_frequency(frequency)

/// Adds/removes a gas sensor from this console's readout list. `sensors` is an
/// assoc id_tag -> display name, walked by ui_data(). Mapper-authored only
/// until now, so a player-built console had no readouts at all. Re-linking the
/// same sensor removes it, matching the injector/vent toggle behaviour.
/obj/structure/machinery/computer/general_air_control/proc/_link_air_sensor(obj/structure/machinery/air_sensor/sensor, mob/user)
	if(!istype(sensor))
		return
	sensor._ensure_id_tag()
	if(sensors[sensor.id_tag])
		sensors -= sensor.id_tag
		sensor_information -= sensor.id_tag
		to_chat(user, SPAN_NOTICE("You unlink \the [sensor] from \the [src]."))
		return
	sensors[sensor.id_tag] = sensor.name
	// Same reason the injector/vent links do this -- writing the tag alone
	// leaves the device on a different channel, so nothing ever arrives.
	sensor.set_frequency(frequency)
	to_chat(user, SPAN_NOTICE("You link \the [sensor] to \the [src]."))

/// Links an injector (Input) or vent pump (Output) to this console by tag,
/// modelled on _link_to_airpump() (airlock_controllers.dm). Both tag slots are
/// mapper-authored only, and a built injector starts with id = null and
/// frequency = 0 (not on any channel at all), so without this a player-built
/// console and injector could never address each other.
///
/// Re-linking the device already in a slot clears it, matching the cycler's
/// own toggle behaviour. set_frequency() at the end is what actually puts the
/// device on this console's channel -- writing the tag alone is not enough.
///
/// Lives on the base type, not just large_tank_control, so supermatter_core
/// (further down) gets it too -- it already duplicated input_tag/output_tag/
/// input_info/output_info and the UI code that reads them, but had no proc
/// and no multitool attackby() hook to ever populate them, so no device of
/// either kind could ever actually be linked to it.
/obj/structure/machinery/computer/general_air_control/proc/_link_atmos_device(obj/structure/machinery/atmospherics/device, mob/user)
	if(istype(device, /obj/structure/machinery/atmospherics/unary/outlet_injector))
		var/obj/structure/machinery/atmospherics/unary/outlet_injector/injector = device
		injector._ensure_id_tag()
		if(input_tag == injector.id)
			input_tag = null
			input_info = null
			to_chat(user, SPAN_NOTICE("You unlink \the [injector] from \the [src]'s input."))
			return
		input_tag = injector.id
		injector.set_frequency(frequency)
		// Ask for a status broadcast on the device's next tick. Without this the
		// link is real but invisible: this console only fills input_info from a
		// RECEIVED signal, ui_data() omits the whole input block while that is
		// null, and an injector only broadcasts when it receives a command --
		// which the UI can't offer until data has arrived. That deadlock is why
		// a linked injector looked like it hadn't linked at all, while a gas
		// sensor (which broadcasts every tick unconditionally) worked fine.
		injector.broadcast_status_next_process = TRUE
		to_chat(user, SPAN_NOTICE("You link \the [injector] to \the [src] as its input."))
		return

	if(istype(device, /obj/structure/machinery/atmospherics/unary/vent_pump))
		var/obj/structure/machinery/atmospherics/unary/vent_pump/pump = device
		pump._ensure_id_tag()
		if(output_tag == pump.id_tag)
			output_tag = null
			output_info = null
			to_chat(user, SPAN_NOTICE("You unlink \the [pump] from \the [src]'s output."))
			return
		output_tag = pump.id_tag
		pump.set_frequency(frequency)
		// Same reason as the injector above -- see that comment.
		pump.broadcast_status_next_process = TRUE
		to_chat(user, SPAN_NOTICE("You link \the [pump] to \the [src] as its output."))
		return

	to_chat(user, SPAN_WARNING("\The [src] only accepts an air injector (input) or an air vent (output)."))

/obj/structure/machinery/computer/general_air_control/attackby(obj/item/attacking_item, mob/user, params)
	if(attacking_item.tool_behaviour == TOOL_MULTITOOL)
		var/obj/item/multitool/MT = attacking_item
		// Buffered injector/vent pump (Input/Output) checked first, then a
		// buffered gas sensor -- both are "an atmos device was buffered
		// elsewhere, now touch the console to complete the link" the same way,
		// just different consumers of the buffer.
		var/obj/structure/machinery/atmospherics/buffered_device = MT.get_buffer(/obj/structure/machinery/atmospherics)
		if(buffered_device)
			_link_atmos_device(buffered_device, user)
			MT.set_buffer(null)
			return TRUE
		var/obj/structure/machinery/air_sensor/sensor = MT.get_buffer(/obj/structure/machinery/air_sensor)
		if(sensor)
			_link_air_sensor(sensor, user)
			MT.set_buffer(null)
			return TRUE
		MT.set_buffer(src)
		to_chat(user, SPAN_NOTICE("You buffer \the [src] in \the [MT]."))
		return TRUE
	return ..()


/obj/structure/machinery/computer/general_air_control/large_tank_control
	ui_type = "AtmosControlTank"
	frequency = 1441
	// input_tag/output_tag/input_info/output_info are declared on the base
	// type now (general_air_control, above) -- shared with supermatter_core.

	var/default_input_flow_setting = 200
	var/default_pressure_setting = PRESSURE_ONE_THOUSAND * 2
	var/max_input_flow_setting = ATMOS_DEFAULT_VOLUME_PUMP + 500
	var/max_pressure_setting = MAX_VENT_PRESSURE
	circuit = /obj/item/circuitboard/air_management/tank_control

/obj/structure/machinery/computer/general_air_control/large_tank_control/terminal
	icon = 'icons/obj/modular_computers/modular_terminal.dmi'
	icon_screen = "tank"
	icon_keyboard = "atmos_key"
	icon_keyboard_emis = "atmos_key_mask"
	is_connected = TRUE
	has_off_keyboards = TRUE
	can_pass_under = FALSE
	light_power_on = 1

/obj/structure/machinery/computer/general_air_control/large_tank_control/wall
	icon = 'icons/obj/modular_computers/modular_telescreen.dmi'
	icon_state = "telescreen"
	icon_screen = "engi"
	density = FALSE

/obj/structure/machinery/computer/general_air_control/large_tank_control/terminal
	icon = 'icons/obj/modular_computers/modular_terminal.dmi'
	icon_screen = "tank"
	icon_keyboard = "atmos_key"
	icon_keyboard_emis = "atmos_key_mask"
	is_connected = TRUE
	has_off_keyboards = TRUE
	can_pass_under = FALSE
	light_power_on = 1

/obj/structure/machinery/computer/general_air_control/large_tank_control/ui_data(mob/user)
	. = ..()
	var/list/data = .
	data["maxrate"] = max_input_flow_setting
	data["maxpressure"] = max_pressure_setting
	if(input_info)
		LAZYINITLIST(data["input"])
		data["input"]["power"] = input_info["power"]
		data["input"]["rate"] = input_info["volume_rate"]
		data["input"]["setrate"] = default_input_flow_setting

	if(output_info)
		LAZYINITLIST(data["output"])
		data["output"]["power"] = output_info["power"]
		data["output"]["pressure"] = output_info["internal"]
		data["output"]["setpressure"] = default_pressure_setting
	return data

// _link_atmos_device() and the multitool attackby() hook that calls it now
// live on the base type (general_air_control, above) -- shared with
// supermatter_core.

/obj/structure/machinery/computer/general_air_control/large_tank_control/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption) return

	var/id_tag = signal.data["tag"]

	if(input_tag == id_tag)
		input_info = signal.data
	else if(output_tag == id_tag)
		output_info = signal.data
	else
		..(signal)

/obj/structure/machinery/computer/general_air_control/large_tank_control/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	if(!radio_connection)
		return FALSE
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO
	signal.source = src
	switch(action)
		if("in_refresh_status")
			input_info = null
			signal.data = list("tag" = input_tag, "status" = 1)
			. = TRUE

		if("in_toggle_injector")
			input_info = null
			signal.data = list("tag" = input_tag, "power_toggle" = 1)
			. = TRUE

		if("in_set_flowrate")
			if(params["in_set_flowrate"] != null)
				var/setrate = between(0, text2num(params["in_set_flowrate"]), max_input_flow_setting)
				input_info = null
				signal.data = list ("tag" = input_tag, "set_volume_rate" = "[setrate]")
				. = TRUE

		if("out_refresh_status")
			output_info = null
			signal.data = list ("tag" = output_tag, "status" = 1)
			. = TRUE

		if("out_toggle_power")
			output_info = null
			signal.data = list ("tag" = output_tag, "power_toggle" = 1)
			. = TRUE

		if("out_set_pressure")
			if(params["out_set_pressure"] != null)
				var/setpressure = between(0, text2num(params["out_set_pressure"]), max_pressure_setting)
				output_info = null
				signal.data = list ("tag" = output_tag, "set_internal_pressure" = "[setpressure]")
				. = TRUE

	signal.data["sigtype"] = "command"
	INVOKE_ASYNC(radio_connection, TYPE_PROC_REF(/datum/radio_frequency, post_signal), src, signal, filter = RADIO_ATMOSIA)

/obj/structure/machinery/computer/general_air_control/supermatter_core
	icon = 'icons/obj/modular_computers/modular_terminal.dmi'
	icon_screen = "tank"
	icon_keyboard = "atmos_key"
	icon_keyboard_emis = "atmos_key_mask"
	ui_type = "AtmosControlSupermatter"
	is_connected = TRUE
	has_off_keyboards = TRUE
	can_pass_under = FALSE
	light_power_on = 1

	frequency = 1438
	// input_tag/output_tag/input_info/output_info are declared on the base
	// type now (general_air_control, above) -- shared with large_tank_control.
	// This subtype previously had no way to ever populate them: no
	// _link_atmos_device() and no multitool attackby() hook of its own, so no
	// injector/vent pump could ever actually be linked to a supermatter core
	// console. Both now come from the base type too.

	var/default_input_flow_setting = 700
	var/default_pressure_setting = 100
	var/max_input_flow_setting = ATMOS_DEFAULT_VOLUME_PUMP + 500
	var/max_pressure_setting = PRESSURE_ONE_THOUSAND
	circuit = /obj/item/circuitboard/air_management/supermatter_core

/obj/structure/machinery/computer/general_air_control/supermatter_core/ui_data(mob/user)
	. = ..()
	var/list/data = .
	data["maxrate"] = max_input_flow_setting
	data["maxpressure"] = max_pressure_setting
	if(input_info)
		LAZYINITLIST(data["input"])
		data["input"]["power"] = input_info["power"]
		data["input"]["rate"] = input_info["volume_rate"]
		data["input"]["setrate"] = default_input_flow_setting

	if(output_info)
		LAZYINITLIST(data["output"])
		data["output"]["power"] = output_info["power"]
		data["output"]["pressure"] = output_info["external"]
		data["output"]["setpressure"] = default_pressure_setting
	return data

/obj/structure/machinery/computer/general_air_control/supermatter_core/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption) return

	var/id_tag = signal.data["tag"]

	if(input_tag == id_tag)
		input_info = signal.data
	else if(output_tag == id_tag)
		output_info = signal.data
	else
		..(signal)

/obj/structure/machinery/computer/general_air_control/supermatter_core/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	if(!radio_connection)
		return
	var/datum/signal/signal = new
	signal.transmission_method = TRANSMISSION_RADIO
	signal.source = src
	switch(action)
		if("in_refresh_status")
			input_info = null
			signal.data = list ("tag" = input_tag, "status" = 1)
			. = TRUE

		if("in_toggle_injector")
			input_info = null
			signal.data = list ("tag" = input_tag, "power_toggle" = 1)
			. = TRUE

		if("in_set_flowrate")
			if(params["in_set_flowrate"] != null)
				var/setrate = between(0, text2num(params["in_set_flowrate"]), max_input_flow_setting)
				input_info = null
				signal.data = list ("tag" = input_tag, "set_volume_rate" = "[setrate]")
				. = TRUE

		if("out_refresh_status")
			output_info = null
			signal.data = list ("tag" = output_tag, "status" = 1)
			. = TRUE

		if("out_toggle_power")
			output_info = null
			signal.data = list ("tag" = output_tag, "power_toggle" = 1)
			. = TRUE

		if("out_set_pressure")
			if(params["out_set_pressure"] != null)
				var/setpressure = between(0, text2num(params["out_set_pressure"]), max_pressure_setting)
				output_info = null
				signal.data = list ("tag" = output_tag, "set_external_pressure" = "[setpressure]", "checks" = 1)
				. = TRUE

	signal.data["sigtype"]="command"
	radio_connection.post_signal(src, signal, filter = RADIO_ATMOSIA)

/obj/structure/machinery/computer/general_air_control/fuel_injection
	icon_screen = "alert:0"
	icon_keyboard = "cyan_key"
	icon_keyboard_emis = "cyan_key_mask"
	light_color = LIGHT_COLOR_CYAN
	ui_type = "AtmosControlInjector"

	var/device_tag
	var/list/device_info

	var/automation = 0

	var/cutoff_temperature = 2000
	var/on_temperature = 1200
	circuit = /obj/item/circuitboard/air_management/injector_control

/obj/structure/machinery/computer/general_air_control/fuel_injection/process()
	if(automation)
		if(!radio_connection)
			return 0

		var/injecting = 0
		for(var/id_tag in sensor_information)
			var/list/data = sensor_information[id_tag]
			if(data["temperature"])
				if(data["temperature"] >= cutoff_temperature)
					injecting = 0
					break
				if(data["temperature"] <= on_temperature)
					injecting = 1

		var/datum/signal/signal = new
		signal.transmission_method = TRANSMISSION_RADIO
		signal.source = src

		signal.data = list(
			"tag" = device_tag,
			"power" = injecting,
			"sigtype"="command"
		)

		radio_connection.post_signal(src, signal, filter = RADIO_ATMOSIA)

	..()

/obj/structure/machinery/computer/general_air_control/fuel_injection/ui_data(mob/user)
	. = ..()
	var/list/data = .
	if(device_info)
		LAZYINITLIST(data["device"])
		data["device"]["power"] = device_info["power"]
		data["device"]["rate"] = device_info["volume_rate"]
		data["device"]["automation"] = automation
	return data

/obj/structure/machinery/computer/general_air_control/fuel_injection/receive_signal(datum/signal/signal)
	if(!signal || signal.encryption) return

	var/id_tag = signal.data["tag"]

	if(device_tag == id_tag)
		device_info = signal.data
	else
		..(signal)

/obj/structure/machinery/computer/general_air_control/fuel_injection/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	switch(action)
		if("refresh_status")
			device_info = null
			if(!radio_connection)
				return 0

			var/datum/signal/signal = new
			signal.transmission_method = TRANSMISSION_RADIO
			signal.source = src
			signal.data = list(
				"tag" = device_tag,
				"status" = 1,
				"sigtype"="command"
			)
			radio_connection.post_signal(src, signal, filter = RADIO_ATMOSIA)
			. = TRUE

		if("toggle_automation")
			automation = !automation
			. = TRUE

		if("toggle_injector")
			device_info = null
			if(!radio_connection)
				return 0

			var/datum/signal/signal = new
			signal.transmission_method = TRANSMISSION_RADIO
			signal.source = src
			signal.data = list(
				"tag" = device_tag,
				"power_toggle" = 1,
				"sigtype"="command"
			)

			radio_connection.post_signal(src, signal, filter = RADIO_ATMOSIA)
			. = TRUE

		if("injection")
			if(!radio_connection)
				return 0

			var/datum/signal/signal = new
			signal.transmission_method = TRANSMISSION_RADIO
			signal.source = src
			signal.data = list(
				"tag" = device_tag,
				"inject" = 1,
				"sigtype"="command"
			)

			radio_connection.post_signal(src, signal, filter = RADIO_ATMOSIA)
			. = TRUE

#undef SIGNAL_OXYGEN
#undef SIGNAL_PHORON
#undef SIGNAL_NITROGEN
#undef SIGNAL_CARBON_DIOXIDE
#undef SIGNAL_HYDROGEN
#undef SIGNAL_N2O
#undef SIGNAL_HELIUM
#undef SIGNAL_DEUTERIUM
#undef SIGNAL_TRITIUM
#undef SIGNAL_HELIUMFUEL
#undef SIGNAL_SULFUR_DIOXIDE
#undef SIGNAL_NITROGEN_DIOXIDE
#undef SIGNAL_CHLORINE
#undef SIGNAL_WATERVAPOR
