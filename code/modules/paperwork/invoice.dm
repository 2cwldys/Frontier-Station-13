/*
 * Invoice paper -- a payable document created by the Invoice program.
 * Swiping an ID card, charge card, or faction charge card on it pays the
 * listed amount to the payee (a personal bank account or a faction account).
 * Unpaid invoices show a red marker; paid ones show a green marker.
 */

#define INVOICE_PAYEE_PERSONAL "personal"
#define INVOICE_PAYEE_FACTION  "faction"

// Excludes <>&"'`/\% -- invoice_id gets interpolated straight into raw HTML
// paper content (set_content_unsafe) as well as chat/log text.
#define INVOICE_ID_CHARS "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$^*-_=+?"
#define INVOICE_ID_LENGTH 5

GLOBAL_LIST_EMPTY(used_invoice_ids)

/// Short random invoice identifier instead of a sequential counter --
/// unguessable, so an invoice can't be paid/spoofed by number-guessing.
/proc/generate_invoice_id()
	var/pool_len = length(INVOICE_ID_CHARS)
	var/id
	do
		id = ""
		for(var/i in 1 to INVOICE_ID_LENGTH)
			var/idx = rand(1, pool_len)
			id += copytext(INVOICE_ID_CHARS, idx, idx + 1)
	while(id in GLOB.used_invoice_ids)
	GLOB.used_invoice_ids += id
	return id

/obj/item/paper/invoice
	name = "invoice"
	var/invoice_id = ""
	var/amount = 0
	var/purpose = ""
	var/payee_name = ""                     // display name of who gets paid
	var/payee_type = INVOICE_PAYEE_PERSONAL // INVOICE_PAYEE_PERSONAL or INVOICE_PAYEE_FACTION
	var/payee_account_number = 0            // when personal
	var/payee_faction_uid = ""              // when faction
	var/paid = FALSE
	var/payer_name = ""

/obj/item/paper/invoice/Initialize()
	. = ..()
	if(!invoice_id)
		invoice_id = generate_invoice_id()
	update_icon()

/obj/item/paper/invoice/update_icon()
	..()
	// Payment state marker: small colored square in the lower-right corner
	var/static/image/marker_unpaid
	var/static/image/marker_paid
	if(!marker_unpaid)
		marker_unpaid = image('icons/obj/bureaucracy.dmi', "paper")
		marker_unpaid.transform = matrix() * 0.25
		marker_unpaid.color = "#cc2222"
		marker_unpaid.appearance_flags = RESET_COLOR
		marker_unpaid.pixel_x = 10
		marker_unpaid.pixel_y = -10
		marker_paid = image('icons/obj/bureaucracy.dmi', "paper")
		marker_paid.transform = matrix() * 0.25
		marker_paid.color = "#22cc22"
		marker_paid.appearance_flags = RESET_COLOR
		marker_paid.pixel_x = 10
		marker_paid.pixel_y = -10
	CutOverlays(marker_unpaid)
	CutOverlays(marker_paid)
	// Crumpled invoices (harm intent + use) show plain scrap, no marker
	if(crumpled)
		return
	AddOverlays(paid ? marker_paid : marker_unpaid)

/obj/item/paper/invoice/crumple(mob/user)
	..()
	// Parent sets the scrap icon_state but not the flag; we need it so
	// update_icon() drops the payment marker off the paper ball
	crumpled = TRUE
	update_icon()

/obj/item/paper/invoice/get_examine_text(mob/user, distance, is_adjacent, infix, suffix)
	. = ..()
	if(distance <= 2)
		. += SPAN_NOTICE("Invoice #[invoice_id]: [amount] credits payable to [payee_name].")
		if(paid)
			. += SPAN_GOOD("It has been PAID[payer_name ? " by [payer_name]" : ""].")
		else
			. += SPAN_WARNING("It is UNPAID. Swipe an ID or charge card to settle it.")

/obj/item/paper/invoice/attackby(obj/item/attacking_item, mob/user)
	// Faction charge card first -- it is an ewallet subtype
	if(istype(attacking_item, /obj/item/spacecash/ewallet/faction_charge_card))
		var/obj/item/spacecash/ewallet/faction_charge_card/FC = attacking_item
		try_pay_faction_card(FC, user)
		return TRUE
	if(istype(attacking_item, /obj/item/spacecash/ewallet))
		var/obj/item/spacecash/ewallet/E = attacking_item
		try_pay_ewallet(E, user)
		return TRUE
	var/obj/item/card/id/card = attacking_item.GetID()
	if(istype(card))
		try_pay_id(card, user)
		return TRUE
	return ..()

/// Common pre-checks. Returns TRUE if payment can proceed.
/obj/item/paper/invoice/proc/can_pay(mob/user)
	if(paid)
		to_chat(user, SPAN_NOTICE("This invoice has already been paid."))
		return FALSE
	if(amount <= 0)
		to_chat(user, SPAN_WARNING("This invoice has an invalid amount."))
		return FALSE
	return TRUE

/// Credit the payee. Returns TRUE on success.
/obj/item/paper/invoice/proc/credit_payee(payer_desc)
	if(payee_type == INVOICE_PAYEE_FACTION)
		return faction_credit(payee_faction_uid, amount, "Invoice #[invoice_id] paid by [payer_desc]: [purpose]")
	return SSeconomy.charge_to_account(payee_account_number, payer_desc, "Invoice #[invoice_id]: [purpose]", "Invoice", amount)

/obj/item/paper/invoice/proc/finalize_payment(mob/user, payer_desc)
	paid = TRUE
	payer_name = payer_desc
	stamps += "<HR><i>Invoice #[invoice_id] settled by [payer_desc] for [amount] credits.</i>"
	update_icon()
	playsound(get_turf(src), 'sound/machines/chime.ogg', 50, 1)
	visible_message(SPAN_GOOD("\The [src] chimes: invoice #[invoice_id] paid in full by [payer_desc]."))

/obj/item/paper/invoice/proc/try_pay_id(obj/item/card/id/card, mob/user)
	if(!can_pay(user))
		return
	if(!card.associated_account_number)
		to_chat(user, SPAN_WARNING("That ID has no bank account linked to it."))
		return
	var/payer_desc = card.registered_name || "unknown"
	if(payee_type == INVOICE_PAYEE_FACTION)
		// Manual path: no destination money_account exists for factions
		var/datum/money_account/source = SSeconomy.get_account(card.associated_account_number)
		if(!source)
			to_chat(user, SPAN_WARNING("Account not found."))
			return
		if(source.suspended)
			to_chat(user, SPAN_WARNING("That account is suspended."))
			return
		if(source.security_level == 2)
			var/pin = input(user, "Enter Account PIN") as num
			if(pin != source.remote_access_pin)
				to_chat(user, SPAN_WARNING("Invalid PIN."))
				return
		if(source.money < amount)
			to_chat(user, SPAN_WARNING("Insufficient funds on that account."))
			return
		SSeconomy.charge_to_account(source.account_number, payee_name, "Invoice #[invoice_id]: [purpose]", "Invoice", -amount)
		if(!credit_payee(payer_desc))
			// Refund -- the faction target vanished between checks
			SSeconomy.charge_to_account(source.account_number, payee_name, "Invoice #[invoice_id] refund", "Invoice", amount)
			to_chat(user, SPAN_WARNING("Payment failed: payee faction not found. Funds returned."))
			return
	else
		var/error = SSeconomy.transfer_money(card.associated_account_number, payee_account_number, "Invoice #[invoice_id]: [purpose]", "Invoice", amount, null, user)
		if(error)
			to_chat(user, SPAN_WARNING(error))
			return
	finalize_payment(user, payer_desc)

/obj/item/paper/invoice/proc/try_pay_ewallet(obj/item/spacecash/ewallet/E, mob/user)
	if(!can_pay(user))
		return
	if(E.worth < amount)
		to_chat(user, SPAN_WARNING("\The [E] has insufficient funds."))
		return
	var/payer_desc = E.owner_name || "charge card"
	if(!credit_payee(payer_desc))
		to_chat(user, SPAN_WARNING("Payment failed: payee not found."))
		return
	E.worth -= amount
	finalize_payment(user, payer_desc)

/obj/item/paper/invoice/proc/try_pay_faction_card(obj/item/spacecash/ewallet/faction_charge_card/FC, mob/user)
	if(!can_pay(user))
		return
	if(!FC.faction_uid)
		to_chat(user, SPAN_WARNING("\The [FC] is not linked to any faction."))
		return
	if(payee_type == INVOICE_PAYEE_FACTION && payee_faction_uid == FC.faction_uid)
		to_chat(user, SPAN_WARNING("This invoice is payable to the same faction that owns \the [FC]."))
		return
	var/payer_desc = "[get_faction_name(FC.faction_uid)] (faction)"
	if(!faction_debit(FC.faction_uid, amount, "Invoice #[invoice_id] to [payee_name]: [purpose]"))
		to_chat(user, SPAN_WARNING("The faction account has insufficient funds."))
		return
	if(!credit_payee(payer_desc))
		// Refund the faction -- payee vanished between checks
		faction_credit(FC.faction_uid, amount, "Invoice #[invoice_id] refund")
		to_chat(user, SPAN_WARNING("Payment failed: payee not found. Funds returned."))
		return
	finalize_payment(user, payer_desc)

#undef INVOICE_PAYEE_PERSONAL
#undef INVOICE_PAYEE_FACTION
#undef INVOICE_ID_CHARS
#undef INVOICE_ID_LENGTH
