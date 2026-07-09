/*
	These defines specify screen locations using Aurora's EAST/WEST/NORTH/SOUTH anchor system.
	screen/dark.dmi is used for all HUD icons (Serenity's visual style).
*/

#define ui_entire_screen "WEST,SOUTH to EAST,NORTH"

//Lower left, persistant menu
#define ui_inventory "WEST:6,SOUTH:5"

//Lower center, persistant menu
#define ui_sstore1 "WEST+2:10,SOUTH:5"
#define ui_id "WEST+3:12,SOUTH:5"
#define ui_belt "WEST+4:14,SOUTH:5"
#define ui_back "CENTER-2:14,SOUTH:5"
#define ui_rhand "CENTER-1:16,SOUTH:5"
#define ui_lhand "CENTER:16,SOUTH:5"
#define ui_equip "CENTER-1:16,SOUTH+1:5"
#define ui_swaphand1 "CENTER-1:16,SOUTH+1:5"
#define ui_swaphand2 "CENTER:16,SOUTH+1:5"
#define ui_storage1 "CENTER+1:16,SOUTH:5"
#define ui_storage2 "CENTER+2:16,SOUTH:5"

#define ui_alien_head "CENTER-3:12,SOUTH:5"
#define ui_alien_oclothing "CENTER-2:14,SOUTH:5"

#define ui_inv1 "CENTER-1,SOUTH:5"
#define ui_inv2 "CENTER,SOUTH:5"
#define ui_inv3 "CENTER+1,SOUTH:5"
#define ui_borg_store "CENTER+2,SOUTH:5"
#define ui_borg_inventory "CENTER-2,SOUTH:5"

#define ui_monkey_mask "WEST+4:14,SOUTH:5"
#define ui_monkey_back "WEST+5:14,SOUTH:5"

#define ui_construct_health "EAST:00,CENTER:15"
#define ui_construct_purge "EAST:00,CENTER-1:15"
#define ui_construct_fire "EAST-1:16,CENTER+1:13"
#define ui_construct_pull "EAST-1:28,SOUTH+1:10"

//Lower right, persistant menu
#define ui_dropbutton "EAST-4:22,SOUTH:5"
#define ui_drop        "EAST-1:28,SOUTH+1:8"
#define ui_throw       "EAST-1:28,SOUTH+2:5"
#define ui_drop_throw  "EAST-1:28,SOUTH+2:5"
#define ui_pull_resist "EAST-1:28,SOUTH+2:8"
#define ui_pull        "EAST-1:28,SOUTH+4:5"
#define ui_morph_resist "EAST-2:26,SOUTH:5"
#define ui_acti "EAST-2:26,SOUTH:5"
#define ui_movi "EAST-3:24,SOUTH:5"
#define ui_burstfire "EAST-4:20,SOUTH:14"
#define ui_uniqueaction "EAST-4:20,SOUTH:5"
#define ui_zonesel "EAST-1:28,SOUTH+3:7"
#define ui_acti_alt "EAST-1:28,SOUTH:5"
#define ui_resist "EAST-1:28,SOUTH:+2:8"
#define ui_rest   "EAST-1:28,SOUTH+1:5"

// vampire
#define ui_suck "EAST-3:24,SOUTH+1:7"

#define ui_borg_pull "EAST-3:24,SOUTH+1:7"
#define ui_borg_module "EAST-2:26,SOUTH+1:7"
#define ui_borg_panel "EAST-1:28,SOUTH+1:7"

//Gun buttons
#define ui_gun1 "EAST-2:26,SOUTH+2:7"
#define ui_gun2 "EAST-1:28, SOUTH+3:7"
#define ui_gun3 "EAST-2:26,SOUTH+3:7"
#define ui_gun_select "EAST-1:28,SOUTH+2:7"
#define ui_gun4 "EAST-3:24,SOUTH+2:7"

//Upper-middle right (damage indicators)
#define ui_up_hint "EAST-1:28,NORTH-1:29"
#define ui_toxin "EAST-1:28,NORTH-2:27"
#define ui_fire "EAST-1:28,SOUTH+4:11"
#define ui_oxygen "EAST-1:28,NORTH-4:23"
#define ui_pressure "EAST-1:28,NORTH-5:21"
#define ui_paralysis "EAST-1:28,NORTH-10:23"
#define ui_energy_display "EAST-1:28,NORTH-6:50"
#define ui_instability_display "EAST-1:28,NORTH-5:50"
#define ui_surrender "EAST-1:28,NORTH-9:21"
#define ui_fixeye "EAST-1:28,NORTH-10:23"

#define ui_alien_toxin "EAST-1:28,NORTH-2:25"
#define ui_alien_fire "EAST-1:28,NORTH-3:25"
#define ui_alien_oxygen "EAST-1:28,NORTH-4:25"

//Middle right (status indicators)
#define ui_nutrition "EAST-1:28,CENTER-2:11"
#define ui_nutrition_small "EAST:4,CENTER-2:24"
#define ui_temp "EAST-1:28,CENTER-1:13"
#define ui_health "EAST-1:28,CENTER:15"
#define ui_health_east_loc "EAST-1:28"
#define ui_health_east_template "EAST-1:"
//#define ui_internal "EAST-1:28,CENTER+1:17"
#define ui_internal "EAST-1:28,SOUTH:5"
#define UI_MORALE_LOCATION "EAST-1:28,CENTER+2:19"
#define ui_stamina "EAST-1:28,CENTER+3:21"
#define ui_happiness "EAST-1:28,CENTER+4:23"

//Upper-middle right (alerts)
#define ui_alert1 "EAST-1:28,CENTER+5:27"
#define ui_alert2 "EAST-1:28,CENTER+4:25"
#define ui_alert3 "EAST-1:28,CENTER+3:23"
#define ui_alert4 "EAST-1:28,CENTER+2:21"
#define ui_alert5 "EAST-1:28,CENTER+1:19"

//borgs
#define ui_borg_health "EAST-1:28,CENTER-1:13"
#define ui_alien_health "EAST-1:28,CENTER-1:13"

//Combat intents (Serenity HUD elements)
#define ui_atk "EAST-3:24,SOUTH+2:7"
#define ui_atk_intents "EAST-2:26,SOUTH:5"
#define ui_combat "EAST-3:24,SOUTH:5"
#define ui_combat_intent "EAST-2:26,SOUTH+1:7"
#define ui_skills_family "EAST-4:22,SOUTH+1:7"

//Pop-up inventory
#define ui_shoes "WEST+1:8,SOUTH:5"
#define ui_gloves "WEST:6,SOUTH+1:7"
#define ui_pants "WEST+1:8,SOUTH+1:7"
#define ui_wrists "WEST:6,SOUTH+1:9"
#define ui_iclothing "WEST+1:8,SOUTH+1:9"
#define ui_oclothing "WEST+2:10,SOUTH+1:9"
#define ui_mask "WEST+1:8,SOUTH+2:11"
#define ui_glasses "WEST:6,SOUTH+2:11"
#define ui_r_ear "WEST:6,SOUTH+3:13"
#define ui_head "WEST+1:8,SOUTH+3:13"
#define ui_l_ear "WEST+2:10,SOUTH+3:13"

//Intent small buttons
#define ui_help_small "EAST-3:8,SOUTH:1"
#define ui_disarm_small "EAST-3:15,SOUTH:18"
#define ui_grab_small "EAST-3:32,SOUTH:18"
#define ui_harm_small "EAST-3:39,SOUTH:1"

#define ui_hand "CENTER-1:14,SOUTH:5"
#define ui_hstore1 "CENTER-2,CENTER-2"
#define ui_sleep "EAST+1, NORTH-13"
// ui_rest defined above near ui_resist

#define ui_iarrowleft "SOUTH-1,EAST-4"
#define ui_iarrowright "SOUTH-1,EAST-2"

#define ui_spell_master "EAST-1:16,NORTH-1:16"
#define ui_genetic_master "EAST-1:16,NORTH-3:16"

#define ui_hovertext "CENTER-7,CENTER+7"

// AI
#define ui_ai_camera_list "SOUTH:6+1,WEST+1:16"
#define ui_ai_track_with_camera "SOUTH:6+1,WEST+2:16"
#define ui_ai_camera_light "SOUTH:6+1,WEST+3:16"
#define ui_ai_sensor "SOUTH:6+1,WEST+4:16"
#define ui_ai_mech "SOUTH:6+1,WEST+5:16"
#define ui_ai_core "SOUTH:6,WEST+1:16"
#define ui_ai_crew_monitor "SOUTH:6,WEST+2:16"
#define ui_ai_crew_manifest "SOUTH:6,WEST+3:16"
#define ui_ai_alerts "SOUTH:6,WEST+4:16"
#define ui_ai_announcement "SOUTH:6,WEST+5:16"
#define ui_ai_shuttle "SOUTH:6,WEST+6:16"
#define ui_ai_state_laws "SOUTH:6,WEST+7:16"
#define ui_ai_pda_send "SOUTH:6,WEST+8:16"
#define ui_ai_pda_log "SOUTH:6,WEST+9:16"
#define ui_ai_take_picture "SOUTH:6,WEST+10:16"
#define ui_ai_view_images "SOUTH:6,WEST+11:16"
#define ui_ai_move_up "SOUTH:6,WEST+12:16"
#define ui_ai_move_down "SOUTH:6,WEST+13:16"

// HUD element related signals
#define COMSIG_GET_HUD_ELEMENTS "get_hud_elements"


/***********************************************************************************
**********************			TG'S HUD DEFINES			  **********************
************************************************************************************/

#define ui_tg_action_slot1 "1:6,14:26"
#define ui_tg_action_slot2 "2:8,14:26"
#define ui_tg_action_slot3 "3:10,14:26"
#define ui_tg_action_slot4 "4:12,14:26"
#define ui_tg_action_slot5 "5:14,14:26"
#define ui_tg_inventory "1:6,1:5"
#define ui_tg_sstore1 "3:10,1:5"
#define ui_tg_id "4:12,1:5"
#define ui_tg_belt "5:14,1:5"
#define ui_tg_back "6:14,1:5"
#define ui_tg_rhand "7:16,1:5"
#define ui_tg_lhand "8:16,1:5"
#define ui_tg_equip "7:16,2:5"
#define ui_tg_swaphand1 "7:16,2:5"
#define ui_tg_swaphand2 "8:16,2:5"
#define ui_tg_storage1 "9:18,1:5"
#define ui_tg_storage2 "10:20,1:5"
#define ui_tg_alien_head "4:12,1:5"
#define ui_tg_alien_oclothing "5:14,1:5"
#define ui_tg_inv1 "6:16,1:5"
#define ui_tg_inv2 "7:16,1:5"
#define ui_tg_inv3 "8:16,1:5"
#define ui_tg_borg_store "9:16,1:5"
#define ui_tg_monkey_mask "5:14,1:5"
#define ui_tg_monkey_back "6:14,1:5"
#define ui_tg_dropbutton "11:22,1:5"
#define ui_tg_drop_throw "14:28,2:7"
#define ui_tg_pull_resist "13:26,2:7"
#define ui_tg_acti "13:26,1:5"
#define ui_tg_movi "12:24,1:5"
#define ui_tg_zonesel "14:28,1:5"
#define ui_tg_acti_alt "14:28,1:5"
#define ui_tg_borg_pull "12:24,2:7"
#define ui_tg_borg_module "13:26,2:7"
#define ui_tg_borg_panel "14:28,2:7"
#define ui_tg_gun1 "13:26,3:7"
#define ui_tg_gun2 "14:28, 4:7"
#define ui_tg_gun3 "13:26,4:7"
#define ui_tg_gun_select "14:28,3:7"
#define ui_tg_toxin "14:28,13:27"
#define ui_tg_fire "14:28,12:25"
#define ui_tg_oxygen "14:28,11:23"
#define ui_tg_pressure "14:28,10:21"
#define ui_tg_alien_toxin "14:28,13:25"
#define ui_tg_alien_fire "14:28,12:25"
#define ui_tg_alien_oxygen "14:28,11:25"
#define ui_tg_nutrition "14:28,5:11"
#define ui_tg_temp "14:28,6:13"
#define ui_tg_health "14:28,7:15"
#define ui_tg_internal "14:28,8:17"
#define ui_tg_borg_health "14:28,6:13"
#define ui_tg_alien_health "14:28,6:13"
#define ui_tg_shoes "2:8,1:5"
#define ui_tg_iclothing "1:6,2:7"
#define ui_tg_oclothing "2:8,2:7"
#define ui_tg_gloves "3:10,2:7"
#define ui_tg_glasses "1:6,3:9"
#define ui_tg_mask "2:8,3:9"
#define ui_tg_l_ear "3:10,3:9"
#define ui_tg_r_ear "3:10,4:11"
#define ui_tg_head "2:8,4:11"
#define ui_tg_help_small "12:8,1:1"
#define ui_tg_disarm_small "12:15,1:18"
#define ui_tg_grab_small "12:32,1:18"
#define ui_tg_harm_small "12:39,1:1"
#define ui_tg_hand "6:14,1:5"
#define ui_tg_hstore1 "5,5"
#define ui_tg_sleep "EAST+1, NORTH-13"
#define ui_tg_rest "EAST+1, NORTH-14"
#define ui_tg_iarrowleft "SOUTH-1,11"
#define ui_tg_iarrowright "SOUTH-1,13"
