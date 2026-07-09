/singleton/emote/audible
	key = "burp"
	emote_message_3p = "USER burps."
	message_type = AUDIBLE_MESSAGE
	var/emote_sound
	var/list/emote_sound_male
	var/list/emote_sound_female

/singleton/emote/audible/do_extra(var/atom/user)
	var/sound_to_play
	if(emote_sound_male || emote_sound_female)
		if(ishuman(user))
			var/mob/living/carbon/human/H = user
			var/list/pool = (H.gender == FEMALE) ? emote_sound_female : emote_sound_male
			if(pool)
				sound_to_play = pick(pool)
		TIMER_COOLDOWN_START(user, COOLDOWN_VERBAL_EMOTE, 10 SECONDS)
	else if(emote_sound)
		if(islist(emote_sound))
			sound_to_play = pick(emote_sound)
		else
			sound_to_play = emote_sound
	if(sound_to_play)
		playsound(user.loc, sound_to_play, 50, 0, vary = FALSE)

/singleton/emote/audible/can_do_emote(var/mob/user)
	. = ..()
	if(. && (emote_sound_male || emote_sound_female) && TIMER_COOLDOWN_RUNNING(user, COOLDOWN_VERBAL_EMOTE))
		return FALSE

/singleton/emote/audible/deathgasp_alien
	key = "deathgasp"
	emote_message_3p = "USER lets out a waning guttural screech, green blood bubbling from its maw."

/singleton/emote/audible/whimper
	key ="whimper"
	emote_message_3p = "USER whimpers."

/singleton/emote/audible/gasp
	key ="gasp"
	emote_message_3p = "USER gasps."
	conscious = 0

/singleton/emote/audible/scretch
	key ="scretch"
	emote_message_3p = "USER scretches."

/singleton/emote/audible/choke
	key ="choke"
	emote_message_3p = "USER chokes!"
	conscious = 0

/singleton/emote/audible/gnarl
	key ="gnarl"
	emote_message_3p = "USER gnarls and shows its teeth.."

/singleton/emote/audible/chirp
	key ="chirp"
	emote_message_3p = "USER chirps!"
	emote_sound = 'sound/misc/nymphchirp.ogg'
	conscious = 0

/singleton/emote/audible/multichirp
	key ="mchirp"
	emote_message_3p = "USER chirps a chorus of notes!"
	emote_sound = 'sound/misc/multichirp.ogg'

/singleton/emote/audible/paincreak
	key ="pcreak"
	emote_message_3p = "USER creaks in pain!"

/singleton/emote/audible/painrustle
	key ="prustle"
	emote_message_3p = "USER rustles in agony!"

/singleton/emote/audible/nymphsqueal
	key ="psqueal"
	emote_message_3p = "USER's nymphs squeal in pain!"

/singleton/emote/audible/chitter
	key = "chitter"
	emote_message_3p = "USER chitters."
	emote_sound = list('sound/voice/chitter1.ogg', 'sound/voice/chitter2.ogg', 'sound/voice/chitter3.ogg')
	conscious = 0

/singleton/emote/audible/click
	key = "click"
	emote_message_3p = "USER clicks USER_THEIR mandibles together."
	emote_sound = 'sound/voice/bugclick.ogg'

/singleton/emote/audible/clack
	key = "clack"
	emote_message_3p = "USER clacks USER_THEIR mandibles together."
	emote_sound = 'sound/voice/bugclack.ogg'

/singleton/emote/audible/rattle
	key = "rattle"
	emote_message_3p = "USER rattles USER_THEIR gaster."
	emote_sound = 'sound/voice/bugrattle.ogg'

/singleton/emote/audible/shriek
	key = "shriek"
	emote_message_3p = "USER shrieks!"

/singleton/emote/audible/screech
	key = "screech"
	emote_message_3p = "USER screeches!"

/singleton/emote/audible/alarm
	key = "alarm"
	emote_message_1p = "You sound an alarm."
	emote_message_3p = "USER sounds an alarm."

/singleton/emote/audible/alert
	key = "alert"
	emote_message_1p = "You let out a distressed noise."
	emote_message_3p = "USER lets out a distressed noise."

/singleton/emote/audible/notice
	key = "notice"
	emote_message_1p = "You play a loud tone."
	emote_message_3p = "USER plays a loud tone."

/singleton/emote/audible/whistle
	key = "whistle"
	emote_message_1p = "You whistle."
	emote_message_3p = "USER whistles."

/singleton/emote/audible/boop
	key = "boop"
	emote_message_1p = "You boop."
	emote_message_3p = "USER boops."

/singleton/emote/audible/sneeze
	key = "sneeze"
	emote_message_3p = "USER sneezes."

/singleton/emote/audible/sniff
	key = "sniff"
	emote_message_3p = "USER sniffs."

/singleton/emote/audible/snore
	key = "snore"
	emote_message_3p = "USER snores."
	conscious = 0

/singleton/emote/audible/whimper
	key = "whimper"
	emote_message_3p = "USER whimpers."

/singleton/emote/audible/yawn
	key = "yawn"
	emote_message_3p = "USER yawns."
	emote_sound_male = list('sound/voice/male_yawn1.ogg', 'sound/voice/male_yawn2.ogg')
	emote_sound_female = list('sound/voice/female_yawn1.ogg', 'sound/voice/female_yawn2.ogg', 'sound/voice/female_yawn3.ogg')

/singleton/emote/audible/clap
	key = "clap"
	emote_message_3p = "USER claps!"
	emote_sound = 'sound/effects/clap.ogg'

/singleton/emote/audible/golfclap
	key = "golfclap"
	emote_message_3p = "USER claps, clearly unimpressed."
	emote_sound = 'sound/effects/golfclap.ogg'

/singleton/emote/audible/chuckle
	key = "chuckle"
	emote_message_3p = "USER chuckles."
	emote_sound_male = list('sound/voice/male_laugh1.ogg', 'sound/voice/male_laugh2.ogg', 'sound/voice/male_laugh3.ogg', 'sound/voice/male_laugh_1.ogg', 'sound/voice/male_laugh_2.ogg', 'sound/voice/male_laugh_3.ogg')
	emote_sound_female = list('sound/voice/female_laugh1.ogg', 'sound/voice/female_laugh2.ogg', 'sound/voice/female_laugh3.ogg')

/singleton/emote/audible/throat
	key = "throat"
	emote_message_3p = "USER clears their throat."
	emote_sound_male = list('sound/voice/throatclear_male.ogg')
	emote_sound_female = list('sound/voice/throatclear_female.ogg')

/singleton/emote/audible/cough
	key = "cough"
	emote_message_3p = "USER coughs!"
	conscious = 0
	emote_sound_male = list('sound/voice/male_cough1.ogg', 'sound/voice/male_cough2.ogg', 'sound/voice/male_cough3.ogg', 'sound/voice/male_cough4.ogg')
	emote_sound_female = list('sound/voice/female_cough1.ogg', 'sound/voice/female_cough2.ogg', 'sound/voice/female_cough3.ogg', 'sound/voice/female_cough4.ogg', 'sound/voice/female_cough5.ogg', 'sound/voice/female_cough6.ogg')

/singleton/emote/audible/cry
	key = "cry"
	emote_message_3p = "USER cries."
	emote_sound_male = list('sound/voice/male_cry1.ogg', 'sound/voice/male_cry2.ogg')
	emote_sound_female = list('sound/voice/female_cry1.ogg', 'sound/voice/female_cry2.ogg')

/singleton/emote/audible/sigh
	key = "sigh"
	emote_message_3p = "USER sighs."

/singleton/emote/audible/laugh
	key = "laugh"
	emote_message_3p_target = "USER laughs at TARGET."
	emote_message_3p = "USER laughs."
	emote_sound_male = list('sound/voice/male_laugh1.ogg', 'sound/voice/male_laugh2.ogg', 'sound/voice/male_laugh3.ogg', 'sound/voice/male_laugh_1.ogg', 'sound/voice/male_laugh_2.ogg', 'sound/voice/male_laugh_3.ogg')
	emote_sound_female = list('sound/voice/female_laugh1.ogg', 'sound/voice/female_laugh2.ogg', 'sound/voice/female_laugh3.ogg')

/singleton/emote/audible/mumble
	key = "mumble"
	emote_message_3p = "USER mumbles."

/singleton/emote/audible/grumble
	key = "grumble"
	emote_message_3p = "USER grumbles."

/singleton/emote/audible/groan
	key = "groan"
	emote_message_3p = "USER groans!"
	conscious = 0
	emote_sound_male = list('sound/voice/man_pain1.ogg', 'sound/voice/man_pain2.ogg', 'sound/voice/man_pain3.ogg')
	emote_sound_female = list('sound/voice/woman_pain1.ogg', 'sound/voice/woman_pain2.ogg', 'sound/voice/woman_pain3.ogg', 'sound/voice/woman_pain4.ogg', 'sound/voice/woman_agony1.ogg', 'sound/voice/woman_agony2.ogg', 'sound/voice/woman_agony3.ogg')

/singleton/emote/audible/moan
	key = "moan"
	emote_message_3p = "USER moans!"
	conscious = 0
	emote_sound_male = list('sound/voice/male_moan1.ogg', 'sound/voice/male_moan2.ogg', 'sound/voice/male_moan3.ogg')
	emote_sound_female = list('sound/voice/female_moan1.ogg', 'sound/voice/female_moan2.ogg', 'sound/voice/female_moan3.ogg')

/singleton/emote/audible/giggle
	key = "giggle"
	emote_message_3p = "USER giggles."
	emote_sound_male = list('sound/voice/male_laugh1.ogg', 'sound/voice/male_laugh2.ogg', 'sound/voice/male_laugh3.ogg', 'sound/voice/male_laugh_1.ogg', 'sound/voice/male_laugh_2.ogg', 'sound/voice/male_laugh_3.ogg')
	emote_sound_female = list('sound/voice/female_giggle1.ogg', 'sound/voice/female_giggle2.ogg')

/singleton/emote/audible/scream
	key = "scream"
	emote_message_3p = "USER screams!"
	emote_sound_male = list('sound/voice/male_scream1.ogg', 'sound/voice/male_scream2.ogg', 'sound/voice/Screams_Male_1.ogg', 'sound/voice/Screams_Male_2.ogg', 'sound/voice/Screams_Male_3.ogg')
	emote_sound_female = list('sound/voice/female_scream1.ogg', 'sound/voice/female_scream2.ogg', 'sound/voice/Screams_Woman_1.ogg', 'sound/voice/Screams_Woman_2.ogg')

/singleton/emote/audible/scream/can_do_emote(var/mob/living/user)
	. = ..()
	if(. && ishuman(user))
		var/mob/living/carbon/human/H = user
		if(!H.can_feel_pain())
			return FALSE

/singleton/emote/audible/grunt
	key = "grunt"
	emote_message_3p = "USER grunts."
	emote_sound_male = list('sound/voice/whimper_male1.ogg', 'sound/voice/whimper_male2.ogg', 'sound/voice/whimper_male3.ogg')
	emote_sound_female = list('sound/voice/whimper_female1.ogg', 'sound/voice/whimper_female2.ogg', 'sound/voice/whimper_female3.ogg')

/singleton/emote/audible/slap
	key = "slap"
	emote_message_1p_target = SPAN_WARNING("You slap TARGET across the face!")
	emote_message_1p = "You slap yourself across the face!"
	emote_message_3p_target = SPAN_WARNING("USER slaps TARGET across the face!")
	emote_message_3p = "USER slaps USER_SELF across the face!"
	emote_sound = 'sound/effects/snap.ogg'

/singleton/emote/audible/slap/target_check(var/atom/user, var/atom/target)
	if(!ismob(target))
		return FALSE
	if(!target.Adjacent(user))
		return FALSE
	return TRUE

/singleton/emote/audible/snap
	key = "snap"
	emote_message_3p = "USER snaps USER_THEIR fingers."
	emote_sound = 'sound/effects/fingersnap.ogg'

/singleton/emote/audible/roar
	key = "roar"
	emote_message_3p = "USER roars!"

/singleton/emote/audible/bellow
	key = "bellow"
	emote_message_3p = "USER bellows!"

/singleton/emote/audible/howl
	key = "howl"
	emote_message_3p = "USER howls!"

/singleton/emote/audible/wheeze
	key = "wheeze"
	emote_message_3p = "USER wheezes."

/singleton/emote/audible/hiss
	key = "hiss"
	emote_message_3p_target = "USER hisses softly at TARGET."
	emote_message_3p = "USER hisses softly."

/singleton/emote/audible/growl
	key = "growl"
	emote_message_3p_target = "USER growls at TARGET."
	emote_message_3p = "USER growls."
	emote_sound = 'sound/voice/lizardgrowl.ogg'

/singleton/emote/audible/hiss/long
	key = "hiss2"
	emote_message_3p_target = "USER hisses loudly at TARGET!"
	emote_message_3p = "USER hisses loudly!"
	emote_sound = 'sound/voice/Lizardhiss2.ogg'

/singleton/emote/audible/lizard_bellow
	key = "bellow"
	emote_message_3p_target = "USER bellows deeply at TARGET!"
	emote_message_3p = "USER bellows!"
	emote_sound = 'sound/voice/LizardBellow.ogg'

/singleton/emote/audible/warble
	key = "warble"
	emote_message_3p = "USER warbles!"
	emote_sound = 'sound/voice/warble.ogg'

/singleton/emote/audible/croon
	key = "croon"
	emote_message_3p = "USER croons..."
	emote_sound = list('sound/voice/croon1.ogg', 'sound/voice/croon2.ogg')

/singleton/emote/audible/lowarble
	key = "lwarble"
	emote_message_3p = "USER lets out a low, throaty warble!"
	emote_sound = 'sound/voice/low warble.ogg'

/singleton/emote/audible/croak
	key = "croak"
	emote_message_3p = "USER croaks!"
	emote_sound = 'sound/voice/croak.ogg'

/singleton/emote/audible/peep
	key = "peep"
	emote_message_3p = "USER vocalizes a sharp chirp!"
	emote_sound = 'sound/voice/peep1.ogg'

/singleton/emote/audible/puff
	key = "puff"
	emote_message_3p = "USER puffs up their cheeks with air!"
	emote_sound = 'sound/voice/puff.ogg'
