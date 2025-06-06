GLOBAL_LIST_EMPTY(shuttle_controls)

/obj/structure/machinery/computer/shuttle_control
	name = "shuttle control console"
	icon = 'icons/obj/structures/machinery/computer.dmi'
	icon_state = "shuttle"
	circuit = null
	unacidable = TRUE

	var/shuttle_tag  // Used to coordinate data in shuttle controller.
	var/hacked = 0   // Has been emagged, no access restrictions.
	var/shuttle_optimized = 0 //Have the shuttle's flight subroutines been generated ?
	var/onboard = 0 //Wether or not the computer is on the physical ship. A bit hacky but that'll do.
	var/shuttle_type = 0
	var/skip_time_lock = 0 // Allows admins to var edit the time lock away.
	var/obj/structure/dropship_equipment/selected_equipment //the currently selected equipment installed on the shuttle this console controls.
	var/list/shuttle_equipments = list() //list of the equipments on the shuttle this console controls
	var/can_abort_flyby = TRUE
	var/abort_timer = 100 //10 seconds
	var/link = 0 // Does this terminal activate the transport system?

	///Has it been admin-disabled?
	var/disabled = FALSE

	var/datum/shuttle/ferry/shuttle_datum

/obj/structure/machinery/computer/shuttle_control/Initialize()
	. = ..()
	GLOB.shuttle_controls += src

/obj/structure/machinery/computer/shuttle_control/Destroy()
	GLOB.shuttle_controls -= src
	return ..()

/obj/structure/machinery/computer/shuttle_control/proc/get_shuttle()
	var/datum/shuttle/ferry/shuttle = SSoldshuttle.shuttle_controller.shuttles[shuttle_tag]

	if(shuttle_datum)
		shuttle = shuttle_datum
	else
		shuttle_datum = shuttle

	return shuttle

/obj/structure/machinery/computer/shuttle_control/is_valid_user(mob/user)
	if(isxeno(user))
		var/mob/living/carbon/xenomorph/xeno_user = user
		if(xeno_user.caste?.is_intelligent)
			return TRUE // Allow access by Queen and Predalien
	return ..()

/obj/structure/machinery/computer/shuttle_control/allowed(mob/M)
	if(isxeno(M))
		var/mob/living/carbon/xenomorph/xeno_user = M
		if(xeno_user.caste?.is_intelligent)
			return TRUE // Allow access by Queen and Predalien
	return ..()

/obj/structure/machinery/computer/shuttle_control/attack_hand(mob/user)
	if(..(user))
		return

	if(!allowed(user))
		to_chat(user, SPAN_WARNING("Access denied."))
		return 1

	if(disabled)
		to_chat(user, SPAN_WARNING("The console seems to be broken."))
		return

	user.set_interaction(src)

	var/datum/shuttle/ferry/shuttle = get_shuttle()

	if(!shuttle)
		log_debug("Shuttle control computer failed to find shuttle with tag '[shuttle_tag]'!")
		return

	if(!isxeno(user) && (onboard || is_ground_level(z)) && !shuttle.iselevator)
		if(shuttle.queen_locked)
			if(onboard && skillcheck(user, SKILL_PILOT, SKILL_PILOT_TRAINED))
				user.visible_message(SPAN_NOTICE("[user] starts to type on [src]."),
					SPAN_NOTICE("You try to take back the control over the shuttle. It will take around 3 minutes."))
				if(do_after(user, 3 MINUTES, INTERRUPT_ALL, BUSY_ICON_FRIENDLY))
					shuttle.last_locked = world.time
					shuttle.queen_locked = 0
					shuttle.last_door_override = world.time
					shuttle.door_override = 0
					user.visible_message(SPAN_NOTICE("[src] blinks with blue lights."),
						SPAN_NOTICE("You have successfully taken back the control over the dropship."))
					ui_interact(user)
				return
			else
				if(world.time < shuttle.last_locked + SHUTTLE_LOCK_COOLDOWN)
					to_chat(user, SPAN_WARNING("You can't seem to re-enable remote control, some sort of safety cooldown is in place. Please wait another [time_left_until(shuttle.last_locked + SHUTTLE_LOCK_COOLDOWN, world.time, 1 MINUTES)] minutes before trying again."))
				else
					to_chat(user, SPAN_NOTICE("You interact with the pilot's console and re-enable remote control."))
					shuttle.last_locked = world.time
					shuttle.queen_locked = 0
		if(shuttle.door_override)
			if(world.time < shuttle.last_door_override + SHUTTLE_LOCK_COOLDOWN)
				to_chat(user, SPAN_WARNING("You can't seem to reverse the door override. Please wait another [time_left_until(shuttle.last_door_override + SHUTTLE_LOCK_COOLDOWN, world.time, 1 MINUTES)] minutes before trying again."))
			else
				to_chat(user, SPAN_NOTICE("You reverse the door override."))
				shuttle.last_door_override = world.time
				shuttle.door_override = 0

	if(link && !shuttle.linked)
		user.visible_message(SPAN_NOTICE("[src] blinks with blue lights."),
			SPAN_NOTICE("Transport link activated."))
		shuttle.linked = TRUE

	if(shuttle.require_link && !shuttle.linked)
		user.visible_message(SPAN_NOTICE("[src] blinks with red lights."),
			SPAN_WARNING("Transport terminal unlinked. Manual activation required."))
		return
	ui_interact(user)

/obj/structure/machinery/computer/shuttle_control/ui_interact(mob/user, ui_key = "main", datum/nanoui/ui = null, force_open = 0)
	var/data[0]
	var/datum/shuttle/ferry/shuttle = get_shuttle()
	if (!istype(shuttle))
		return

	var/shuttle_state
	switch(shuttle.moving_status)
		if(SHUTTLE_IDLE)
			shuttle_state = "idle"
		if(SHUTTLE_WARMUP)
			shuttle_state = "warmup"
		if(SHUTTLE_INTRANSIT)
			shuttle_state = "in_transit"
		if(SHUTTLE_CRASHED)
			shuttle_state = "crashed"

	var/shuttle_status
	switch (shuttle.process_state)
		if(IDLE_STATE)
			if (shuttle.in_use)
				shuttle_status = "Busy."
			else if (!shuttle.location)
				shuttle_status = "Standing by at station."
			else
				shuttle_status = "Standing by at an off-site location."
		if(WAIT_LAUNCH, FORCE_LAUNCH)
			shuttle_status = "Shuttle has received command and will depart shortly."
		if(WAIT_ARRIVE)
			shuttle_status = "Proceeding to destination."
		if(WAIT_FINISH)
			shuttle_status = "Arriving at destination now."

	var/shuttle_status_message
	if(shuttle.transit_gun_mission && (onboard || shuttle.moving_status != SHUTTLE_IDLE))
		shuttle_status_message = "<b>Flight type:</b> <span style='font-weight: bold;color: #ff4444'>FLYBY. </span>"
	else //console not onboard stays on TRANSPORT and only shows FIRE MISSION when shuttle has already launched
		shuttle_status_message = "<b>Flight type:</b> <span style='font-weight: bold;color: #44ff44'>TRANSPORT. </span>"

	if(shuttle.transit_optimized) //If the shuttle is recharging, just go ahead and tell them it's unoptimized (it will be once recharged)
		if(shuttle.recharging && shuttle.moving_status == SHUTTLE_IDLE)
			shuttle_status_message += "<br>No custom flight subroutines have been submitted for the upcoming flight" //FYI: Flight plans are reset once recharging ends
		else
			shuttle_status_message += "<br>Custom flight subroutines have been submitted for the [shuttle.moving_status == SHUTTLE_INTRANSIT ? "ongoing":"upcoming"] flight."
	else
		if(shuttle.moving_status == SHUTTLE_INTRANSIT)
			shuttle_status_message += "<br>Default failsafe flight subroutines are being used for the current flight."
		else
			shuttle_status_message += "<br>No custom flight subroutines have been submitted for the upcoming flight"

	var/effective_recharge_time = shuttle.recharge_time
	if(shuttle.transit_optimized)
		effective_recharge_time *= SHUTTLE_OPTIMIZE_FACTOR_RECHARGE

	var/recharge_status = effective_recharge_time - shuttle.recharging

	var/is_dropship = FALSE
	var/is_automated = FALSE
	var/automated_launch_delay = 0
	var/automated_launch_time_left = 0

	data = list(
		"shuttle_status" = shuttle_status,
		"shuttle_state" = shuttle_state,
		"has_docking" = shuttle.docking_controller? 1 : 0,
		"docking_status" = shuttle.docking_controller? shuttle.docking_controller.get_docking_status() : null,
		"docking_override" = shuttle.docking_controller? shuttle.docking_controller.override_enabled : null,
		"can_launch" = shuttle.can_launch(),
		"can_cancel" = shuttle.can_cancel(),
		"can_force" = shuttle.can_force(),
		"can_optimize" = shuttle.can_optimize(),
		"optimize_allowed" = shuttle.can_be_optimized,
		"optimized" = shuttle.transit_optimized,
		"gun_mission_allowed" = shuttle.can_do_gun_mission,
		"shuttle_status_message" = shuttle_status_message,
		"recharging" = shuttle.recharging,
		"recharging_seconds" = floor(shuttle.recharging/10),
		"flight_seconds" = floor(shuttle.in_transit_time_left/10),
		"can_return_home" = shuttle.transit_gun_mission && shuttle.moving_status == SHUTTLE_INTRANSIT && shuttle.in_transit_time_left>abort_timer,
		"recharge_time" = effective_recharge_time,
		"recharge_status" = recharge_status,
		"human_user" = ishuman(user),
		"is_dropship" = is_dropship,
		"onboard" = onboard,
		"automated" = is_automated,
		"auto_time" = automated_launch_delay,
		"auto_time_cdown" = automated_launch_time_left,
	)

	ui = SSnano.nanomanager.try_update_ui(user, src, ui_key, ui, data, force_open)

	if (!ui)
		ui = new(user, src, ui_key, shuttle.iselevator? "elevator_control_console.tmpl" : "shuttle_control_console.tmpl", shuttle.iselevator? "Elevator Control" : "Shuttle Control", 550, 500)
		ui.set_initial_data(data)
		ui.open()
		ui.set_auto_update(1)

/obj/structure/machinery/computer/shuttle_control/Topic(href, href_list)
	if(..())
		return

	add_fingerprint(usr)

	var/datum/shuttle/ferry/shuttle = get_shuttle()
	if (!istype(shuttle))
		return

	if(href_list["move"])
		if(shuttle.recharging) //Prevent the shuttle from moving again until it finishes recharging. This could be made to look better by using the shuttle computer's visual UI.
			if(shuttle.iselevator)
				to_chat(usr, SPAN_WARNING("The elevator is loading and unloading. Please hold."))
			else
				to_chat(usr, SPAN_WARNING("The shuttle's engines are still recharging and cooling down."))
			return
		if(shuttle.queen_locked && !isqueen(usr))
			to_chat(usr, SPAN_WARNING("The shuttle isn't responding to prompts, it looks like remote control was disabled."))
			return
		//Comment to test
		if(!skip_time_lock && world.time < SSticker.mode.round_time_lobby + SHUTTLE_TIME_LOCK && istype(shuttle, /datum/shuttle/ferry/marine))
			to_chat(usr, SPAN_WARNING("The shuttle is still undergoing pre-flight fueling and cannot depart yet. Please wait another [floor((SSticker.mode.round_time_lobby + SHUTTLE_TIME_LOCK-world.time)/600)] minutes before trying again."))
			return
		if(SSticker.mode.active_lz != src && !onboard && isqueen(usr))
			to_chat(usr, SPAN_WARNING("The shuttle isn't responding to prompts, it looks like this isn't the primary shuttle."))
			return
		if(istype(shuttle, /datum/shuttle/ferry/marine))
			var/datum/shuttle/ferry/marine/s = shuttle
			if(!length(s.locs_land) && !s.transit_gun_mission)
				to_chat(usr, SPAN_WARNING("There is no suitable LZ for this shuttle. Flight configuration changed to fire-mission."))
				s.transit_gun_mission = 1
		if(shuttle.moving_status == SHUTTLE_IDLE) //Multi consoles, hopefully this will work

			if(shuttle.locked)
				return
			var/mob/M = usr

			//Alert code is the Queen is the one calling it, the shuttle is on the ground and the shuttle still allows alerts
			if(isqueen(M) && shuttle.location == 1 && shuttle.alerts_allowed && onboard && !shuttle.iselevator)
				var/mob/living/carbon/xenomorph/queen/Q = M

				// Check for onboard xenos, so the Queen doesn't leave most of her hive behind.
				var/count = Q.count_hivemember_same_area()

				// Check if at least half of the hive is onboard. If not, we don't launch.
				if(count < length(Q.hive.totalXenos) * 0.5)
					to_chat(Q, SPAN_WARNING("More than half of your hive is not on board. Don't leave without them!"))
					return

				// Allow the queen to choose the ship section to crash into
				var/crash_target = tgui_input_list(usr, "Choose a ship section to target","Hijack", GLOB.almayer_ship_sections + list("Cancel"))
				if(crash_target == "Cancel")
					return

				var/i = tgui_alert(Q, "Warning: Once you launch the shuttle you will not be able to bring it back. Confirm anyways?", "WARNING", list("Yes", "No"))
				if(i != "Yes")
					return

				if(shuttle.moving_status != SHUTTLE_IDLE || shuttle.locked || shuttle.location != 1 || !shuttle.alerts_allowed || !shuttle.queen_locked || shuttle.recharging)
					return

				//Shit's about to kick off now
				if(istype(shuttle, /datum/shuttle/ferry/marine) && is_ground_level(z))
					var/datum/shuttle/ferry/marine/shuttle1 = shuttle

					shuttle1.true_crash_target_section = crash_target

					// If the AA is protecting the target area, pick any other section to crash into at random
					if(GLOB.almayer_aa_cannon.protecting_section == crash_target)
						var/list/potential_crash_sections = GLOB.almayer_ship_sections.Copy()
						potential_crash_sections -= GLOB.almayer_aa_cannon.protecting_section
						crash_target = pick(potential_crash_sections)

					shuttle1.crash_target_section = crash_target
					shuttle1.transit_gun_mission = 0

					if(GLOB.round_statistics)
						GLOB.round_statistics.track_hijack()

					marine_announcement("Unscheduled dropship departure detected from operational area. Hijack likely. Shutting down autopilot.", "Dropship Alert", 'sound/AI/hijack.ogg', logging = ARES_LOG_SECURITY)
					shuttle.alerts_allowed--
					log_ares_flight("Unknown", "Unscheduled dropship departure detected from operational area. Hijack likely. Shutting down autopilot.")

					to_chat(Q, SPAN_DANGER("A loud alarm erupts from [src]! The fleshy hosts must know that you can access it!"))
					xeno_message(SPAN_XENOANNOUNCE("The Queen has commanded the metal bird to depart for the metal hive in the sky! Rejoice!"),3,Q.hivenumber)
					xeno_message(SPAN_XENOANNOUNCE("The hive swells with power! You will now steadily gain burrowed larva over time."),2,Q.hivenumber)

					// Notify the yautja too so they stop the hunt
					message_all_yautja("The serpent Queen has commanded the landing shuttle to depart.")
					playsound(src, 'sound/misc/queen_alarm.ogg')

					Q.count_niche_stat(STATISTICS_NICHE_FLIGHT)

					if(Q.hive)
						addtimer(CALLBACK(Q.hive, TYPE_PROC_REF(/datum/hive_status, abandon_on_hijack)), DROPSHIP_WARMUP_TIME + 5 SECONDS, TIMER_UNIQUE) //+ 5 seconds catch standing in doorways

					if(GLOB.bomb_set)
						for(var/obj/structure/machinery/nuclearbomb/bomb in world)
							bomb.end_round = FALSE

					if(GLOB.almayer_orbital_cannon)
						GLOB.almayer_orbital_cannon.is_disabled = TRUE
						addtimer(CALLBACK(GLOB.almayer_orbital_cannon, TYPE_PROC_REF(/obj/structure/orbital_cannon, enable)), 10 MINUTES, TIMER_UNIQUE)

					if(GLOB.almayer_aa_cannon)
						GLOB.almayer_aa_cannon.is_disabled = TRUE
				else
					if(shuttle.require_link)
						use_power(4080)
					shuttle.launch(src)

			else if(!onboard && isqueen(M) && shuttle.location == 1 && !shuttle.iselevator)
				to_chat(M, SPAN_WARNING("Hrm, that didn't work. Maybe try the one on the ship?"))
				return
			else
				if(is_ground_level(z))
					shuttle.transit_gun_mission = 0 //remote launch always do transport flight.
				shuttle.launch(src)
				if(onboard && !shuttle.iselevator)
					M.count_niche_stat(STATISTICS_NICHE_FLIGHT)
			msg_admin_niche("[M] ([M.key]) launched \a [shuttle.iselevator? "elevator" : "shuttle"] using [src].")

	ui_interact(usr)


/obj/structure/machinery/computer/shuttle_control/bullet_act(obj/projectile/Proj)
	visible_message("[Proj] ricochets off [src]!")
	return 0

/obj/structure/machinery/computer/shuttle_control/ex_act(severity)
	if(unacidable)
		return //unacidable shuttle consoles are also immune to explosions.
	..()




//Dropship control console

/obj/structure/machinery/computer/shuttle_control/dropship1
	name = "\improper 'Alamo' dropship console"
	desc = "The remote controls for the 'Alamo' Dropship. Named after the Alamo Mission, stage of the Battle of the Alamo in the United States' state of Texas in the Spring of 1836. The defenders held to the last, encouraging other Texans to rally to the flag."
	icon = 'icons/obj/structures/machinery/computer.dmi'
	icon_state = "shuttle"

	shuttle_type = SHUTTLE_DROPSHIP
	unslashable = TRUE
	unacidable = TRUE
	explo_proof = TRUE
	req_one_access = list(ACCESS_MARINE_LEADER, ACCESS_MARINE_DROPSHIP)

/obj/structure/machinery/computer/shuttle_control/dropship1/Initialize()
	. = ..()
	shuttle_tag = DROPSHIP_ALAMO

/obj/structure/machinery/computer/shuttle_control/dropship1/onboard
	name = "\improper 'Alamo' flight controls"
	desc = "The flight controls for the 'Alamo' Dropship. Named after the Alamo Mission, stage of the Battle of the Alamo in the United States' state of Texas in the Spring of 1836. The defenders held to the last, encouraging other Texians to rally to the flag."
	icon = 'icons/obj/structures/machinery/shuttle-parts.dmi'
	icon_state = "console"
	density = TRUE
	onboard = 1

/obj/structure/machinery/computer/shuttle_control/dropship2
	name = "\improper 'Normandy' dropship console"
	desc = "The remote controls for the 'Normandy' Dropship. Named after a department in France, noteworthy for the famous naval invasion of Normandy on the 6th of June 1944, a bloody but decisive victory in World War II and the campaign for the Liberation of France."
	icon = 'icons/obj/structures/machinery/computer.dmi'
	icon_state = "shuttle"

	shuttle_type = SHUTTLE_DROPSHIP
	unslashable = TRUE
	unacidable = TRUE
	explo_proof = TRUE
	req_one_access = list(ACCESS_MARINE_LEADER, ACCESS_MARINE_DROPSHIP)

/obj/structure/machinery/computer/shuttle_control/dropship2/Initialize()
	. = ..()
	shuttle_tag = DROPSHIP_NORMANDY

/obj/structure/machinery/computer/shuttle_control/dropship2/onboard
	name = "\improper 'Normandy' flight controls"
	desc = "The flight controls for the 'Normandy' Dropship. Named after a department in France, noteworthy for the famous naval invasion of Normandy on the 6th of June 1944, a bloody but decisive victory in World War II and the campaign for the Liberation of France."
	icon = 'icons/obj/structures/machinery/shuttle-parts.dmi'
	icon_state = "console"
	onboard = 1
	density = TRUE

/obj/structure/machinery/computer/shuttle_control/dropship3
	name = "\improper 'Saipan' dropship console"
	desc = "The remote controls for the 'Saipan' Dropship."
	icon = 'icons/obj/structures/machinery/computer.dmi'
	icon_state = "shuttle"

	shuttle_type = SHUTTLE_DROPSHIP
	unslashable = TRUE
	unacidable = TRUE
	explo_proof = TRUE
	req_one_access = list(ACCESS_MARINE_LEADER, ACCESS_MARINE_DROPSHIP)

/obj/structure/machinery/computer/shuttle_control/dropship3/Initialize()
	. = ..()
	shuttle_tag = DROPSHIP_SAIPAN

/obj/structure/machinery/computer/shuttle_control/dropship3/onboard
	name = "\improper 'Saipan' flight controls"
	desc = "The flight controls for the 'Saipan' Dropship."
	icon = 'icons/obj/structures/machinery/shuttle-parts.dmi'
	icon_state = "console"
	onboard = 1
	density = TRUE

/obj/structure/machinery/computer/shuttle_control/dropship_upp
	name = "\improper 'Morana' dropship console"
	desc = "The remote controls for the 'Morana' Dropship. Named after the slavic goddess of death and rebirth."
	icon = 'icons/obj/structures/machinery/computer.dmi'
	icon_state = "shuttle"

	shuttle_type = SHUTTLE_DROPSHIP
	unslashable = TRUE
	unacidable = TRUE
	explo_proof = TRUE
	req_one_access = list(ACCESS_UPP_FLIGHT, ACCESS_UPP_LEADERSHIP)

/obj/structure/machinery/computer/shuttle_control/dropship_upp/Initialize()
	. = ..()
	shuttle_tag = DROPSHIP_MORANA

/obj/structure/machinery/computer/shuttle_control/dropship_upp/onboard
	name = "\improper 'Morana' flight controls"
	desc = "The flight controls for the 'Morana' Dropship. Named after the slavic goddess of death and rebirth."
	icon = 'icons/obj/structures/machinery/shuttle-parts.dmi'
	icon_state = "console_upp"
	onboard = 1
	density = TRUE

/obj/structure/machinery/computer/shuttle_control/dropship_upp2
	name = "\improper 'Devana' dropship console"
	desc = "The remote controls for the 'Devana' Dropship. Named after the slavic goddess of nature, hunting and the moon."
	icon = 'icons/obj/structures/machinery/computer.dmi'
	icon_state = "shuttle"

	shuttle_type = SHUTTLE_DROPSHIP
	unslashable = TRUE
	unacidable = TRUE
	explo_proof = TRUE
	req_one_access = list(ACCESS_UPP_FLIGHT, ACCESS_UPP_LEADERSHIP)

/obj/structure/machinery/computer/shuttle_control/dropship_upp2/Initialize()
	. = ..()
	shuttle_tag = DROPSHIP_DEVANA

/obj/structure/machinery/computer/shuttle_control/dropship_upp2/onboard
	name = "\improper 'Devana' flight controls"
	desc = "The flight controls for the 'Devana' Dropship. Named after the slavic goddess of nature, hunting and the moon."
	icon = 'icons/obj/structures/machinery/shuttle-parts.dmi'
	icon_state = "console_upp"
	onboard = 1
	density = TRUE

//Elevator control console

/obj/structure/machinery/computer/shuttle_control/ice_colony
	name = "Elevator Console"
	icon = 'icons/obj/structures/machinery/computer.dmi'
	icon_state = "elevator_screen"

	shuttle_type = SHUTTLE_ELEVATOR
	unslashable = TRUE
	unacidable = TRUE
	explo_proof = TRUE
	density = FALSE
	req_access = null

/obj/structure/machinery/computer/shuttle_control/ice_colony/proc/animate_on()
	icon_state = "elevator_screen_animated"

/obj/structure/machinery/computer/shuttle_control/ice_colony/proc/animate_off()
	icon_state = "elevator_screen"

/obj/structure/machinery/computer/shuttle_control/ice_colony/elevator1
	shuttle_tag = "Elevator 1"

/obj/structure/machinery/computer/shuttle_control/ice_colony/elevator2
	shuttle_tag = "Elevator 2"

/obj/structure/machinery/computer/shuttle_control/ice_colony/elevator3
	shuttle_tag = "Elevator 3"

/obj/structure/machinery/computer/shuttle_control/ice_colony/elevator4
	shuttle_tag = "Elevator 4"



//Trijent transit control console

/obj/structure/machinery/computer/shuttle_control/trijent
	name = "Transit Console"
	icon = 'icons/obj/structures/machinery/computer.dmi'
	icon_state = "elevator_screen"

	shuttle_type = SHUTTLE_ELEVATOR
	unslashable = TRUE
	unacidable = TRUE
	explo_proof = TRUE
	density = FALSE
	req_access = null

/obj/structure/machinery/computer/shuttle_control/trijent/proc/animate_on()
	icon_state = "elevator_screen_animated"

/obj/structure/machinery/computer/shuttle_control/trijent/proc/animate_off()
	icon_state = "elevator_screen"

/obj/structure/machinery/computer/shuttle_control/trijent/tri_trans1
	shuttle_tag = "Transit 1"

/obj/structure/machinery/computer/shuttle_control/trijent/tri_trans2
	shuttle_tag = "Transit 2"
