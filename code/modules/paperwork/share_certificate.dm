/*
 * Share certificate -- a printable equity document created by the Faction
 * Management program's "Print Share Certificate" action. Swiping your own ID
 * card on it grants you the listed percentage of that faction's stock
 * listing (see persistence_faction_shareholders.dm), diluting every other
 * current shareholder proportionally. If a price was set, redeeming it also
 * charges that many credits from your personal account into the faction
 * treasury. Unclaimed certificates show a red marker; claimed ones show
 * green, mirroring invoice.dm's paid/unpaid marker.
 */

#define SHARE_CERT_ID_CHARS "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$^*-_=+?"
#define SHARE_CERT_ID_LENGTH 5

GLOBAL_LIST_EMPTY(used_share_certificate_ids)

/// Short random certificate identifier, mirroring generate_invoice_id()
/// (invoice.dm) -- unguessable, own dedupe list (kept separate from
/// GLOB.used_invoice_ids since these are a different namespace of document).
/proc/generate_share_certificate_id()
	var/pool_len = length(SHARE_CERT_ID_CHARS)
	var/id
	do
		id = ""
		for(var/i in 1 to SHARE_CERT_ID_LENGTH)
			var/idx = rand(1, pool_len)
			id += copytext(SHARE_CERT_ID_CHARS, idx, idx + 1)
	while(id in GLOB.used_share_certificate_ids)
	GLOB.used_share_certificate_ids += id
	return id

/obj/item/paper/share_certificate
	name = "share certificate"
	var/certificate_id = ""
	var/faction_uid = ""
	var/percent = 0
	var/price = 0
	var/issued_by_name = ""
	var/redeemed = FALSE
	var/shareholder_ckey = ""
	var/shareholder_char_name = ""

/obj/item/paper/share_certificate/Initialize()
	. = ..()
	if(!certificate_id)
		certificate_id = generate_share_certificate_id()
	update_icon()

// Restores a certificate's identity/terms/claimed state across a save --
// without this, a saved certificate comes back blank/unclaimed with a
// freshly rolled ID, same reasoning as invoice.dm's own persistence hooks.
/obj/item/paper/share_certificate/persistent_objects_get_content()
	var/list/content = list()
	content["certificate_id"]         = certificate_id
	content["faction_uid"]            = faction_uid
	content["percent"]                = percent
	content["price"]                  = price
	content["issued_by_name"]         = issued_by_name
	content["redeemed"]               = redeemed
	content["shareholder_ckey"]       = shareholder_ckey
	content["shareholder_char_name"]  = shareholder_char_name
	return content

/obj/item/paper/share_certificate/persistent_objects_apply_content(content, x, y, z)
	..()
	if(!islist(content))
		return
	if(!isnull(content["certificate_id"]))        certificate_id        = content["certificate_id"]
	if(!isnull(content["faction_uid"]))           faction_uid           = normalize_faction_uid(content["faction_uid"])
	if(!isnull(content["percent"]))                percent               = content["percent"]
	if(!isnull(content["price"]))                  price                 = content["price"]
	if(!isnull(content["issued_by_name"]))         issued_by_name        = content["issued_by_name"]
	if(!isnull(content["redeemed"]))               redeemed              = content["redeemed"]
	if(!isnull(content["shareholder_ckey"]))       shareholder_ckey      = content["shareholder_ckey"]
	if(!isnull(content["shareholder_char_name"]))  shareholder_char_name = content["shareholder_char_name"]
	update_icon()

/obj/item/paper/share_certificate/update_icon()
	..()
	var/static/image/marker_unclaimed
	var/static/image/marker_claimed
	if(!marker_unclaimed)
		marker_unclaimed = image('icons/obj/bureaucracy.dmi', "paper")
		marker_unclaimed.transform = matrix() * 0.25
		marker_unclaimed.color = "#cc2222"
		marker_unclaimed.appearance_flags = RESET_COLOR
		marker_unclaimed.pixel_x = 10
		marker_unclaimed.pixel_y = -10
		marker_claimed = image('icons/obj/bureaucracy.dmi', "paper")
		marker_claimed.transform = matrix() * 0.25
		marker_claimed.color = "#22cc22"
		marker_claimed.appearance_flags = RESET_COLOR
		marker_claimed.pixel_x = 10
		marker_claimed.pixel_y = -10
	CutOverlays(marker_unclaimed)
	CutOverlays(marker_claimed)
	if(crumpled)
		return
	AddOverlays(redeemed ? marker_claimed : marker_unclaimed)

/obj/item/paper/share_certificate/crumple(mob/user)
	..()
	crumpled = TRUE
	update_icon()

/obj/item/paper/share_certificate/get_examine_text(mob/user, distance, is_adjacent, infix, suffix)
	. = ..()
	if(distance <= 2)
		. += SPAN_NOTICE("Share Certificate #[certificate_id]: [percent]% of [faction_uid ? get_faction_name(faction_uid) : "an unknown faction"][price > 0 ? ", price [price] credits" : " (free grant)"].")
		if(redeemed)
			. += SPAN_GOOD("CLAIMED by [shareholder_char_name].")
		else
			. += SPAN_WARNING("UNCLAIMED. Swipe your own ID to accept this stake.")

/obj/item/paper/share_certificate/attackby(obj/item/attacking_item, mob/user)
	var/obj/item/card/id/card = attacking_item.GetID()
	if(istype(card))
		try_redeem(card, user)
		return TRUE
	return ..()

/// Swiping grants the stake -- unlike an invoice (payable by anyone holding
/// a valid card/wallet), a share stake binds to the person accepting it, so
/// identity comes from the swiping mob itself (user.ckey/user.real_name),
/// not the card's own account fields. Matches personal_tagger_set()'s
/// existing "the interacting user IS the one being registered" idiom
/// (persistence_faction_tagger.dm).
/obj/item/paper/share_certificate/proc/try_redeem(obj/item/card/id/card, mob/user)
	if(redeemed)
		to_chat(user, SPAN_NOTICE("This certificate has already been claimed."))
		return
	if(card.registered_name != user.real_name)
		to_chat(user, SPAN_WARNING("You can only redeem a share certificate with your own ID."))
		return
	if(!islist(GLOB.persistence_faction_cache) || !(faction_uid in GLOB.persistence_faction_cache))
		to_chat(user, SPAN_WARNING("This faction no longer exists."))
		return

	var/payer_desc = user.real_name || key_name(user)

	if(price > 0)
		var/datum/money_account/acc = SSeconomy.get_account_by_ckey_and_name(user.ckey, user.real_name)
		if(!acc)
			to_chat(user, SPAN_WARNING("You need a personal Idris account first -- print a replacement ID at any ID console."))
			return
		if(acc.money < price)
			to_chat(user, SPAN_WARNING("Insufficient funds -- this certificate costs [price] credits."))
			return
		acc.adjust_money(-price)
		faction_credit(faction_uid, price, "Share certificate #[certificate_id] purchased by [payer_desc] ([percent]%)")

	var/refusal = SSpersistence.factionGrantShareholder(faction_uid, user.ckey, user.real_name, percent, payer_desc, certificate_id)
	if(refusal)
		if(price > 0)
			// Refund -- the grant itself failed after payment already went
			// through (e.g. the cap table shifted between print and swipe).
			faction_debit(faction_uid, price, "Share certificate #[certificate_id] refund")
			var/datum/money_account/refund_acc = SSeconomy.get_account_by_ckey_and_name(user.ckey, user.real_name)
			if(refund_acc)
				refund_acc.adjust_money(price)
		to_chat(user, SPAN_WARNING("Could not grant the stake: [refusal]"))
		return

	redeemed = TRUE
	shareholder_ckey = user.ckey
	shareholder_char_name = user.real_name
	update_icon()
	playsound(get_turf(src), 'sound/machines/chime.ogg', 50, 1)
	visible_message(SPAN_GOOD("\The [src] chimes: [percent]% share certificate claimed by [payer_desc]."))
	to_chat(user, SPAN_GOOD("You are now a [percent]% shareholder in [get_faction_name(faction_uid)]."))
	log_and_message_admins("[key_name(user)] redeemed a [percent]% share certificate (#[certificate_id]) in faction '[faction_uid]'[price > 0 ? " for [price] cr" : ""].", user)

#undef SHARE_CERT_ID_CHARS
#undef SHARE_CERT_ID_LENGTH
