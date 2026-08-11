/// Master singleton for cargo items. Contains data relating to what a cargo item spawns, price, desc, supplier, access, etc.
/singleton/cargo_item
	/// The category this item belongs to. This MUST match the cargo_category "name" this item belongs to.
	var/category = "miscellaneous"

	/// The name of the item.
	var/name = "generic cargo item"

	/// The category this item belongs to. This MUST match the cargo_supplier "short_name" this item belongs to.
	var/supplier = "Hub"

	/// The description of this item.
	var/description = "A basic cargo item."

	/// The amount of 'things' this "item" has. Defaults to 1. Change this for cargo items that have multiple objects packaged in them.
	var/amount = 1

	/// The base price of the item, in credits.
	var/price = 1

	/// The list of objects this item has. Duplicate items are handled by the "spawn_amount" variable.
	var/list/items = list()

	/// The req_access level required to order/open the crate.
	var/access = 0

	/// What kind of container this object spawns in. Valid options: "crate", "freezer", "box" (wooden box, or shipping container if restricted), and "bodybag".
	var/container_type = "crate"

	/// Whether or not this item can be shipped with other objects in the same crate. Switch to FALSE for large items that realistically cannot fit multiple in a container.
	var/groupable = TRUE

	/// How many of the given items to spawn. A value of 2 spawns double the items, 5 spawns 5x, etc. Applied to EVERYTHING in the "items" list.
	var/spawn_amount = 1

	/// The numerical ID of this item. Assigned automatically during initialization. DO NOT MANUALLY MODIFY.
	var/id = 0

	/// The adjusted price of this item. Automatically calculated during initialization. DO NOT MANUALLY MODIFY.
	var/adjusted_price = 1

	/// The "supplier data" of this item, containing all the data of this item's "supplier". Automatically calculated during initialization. DO NOT MANUALLY MODIFY.
	var/singleton/cargo_supplier/supplier_data = /singleton/cargo_supplier/generic_supplier

	/// If TRUE, this item is only orderable from a faction-shackled console on a
	/// Z-level with an active piracy beacon -- see piracy_beacon_active_on_z().
	var/requires_piracy_beacon = FALSE

	/// Faction-exclusive equipment. Null/empty = orderable by anyone (every
	/// pre-existing item, unchanged). Otherwise a faction uid, or a list of
	/// them, and only a console shackled to one of those factions may see or
	/// order it -- see _can_order_faction_item() (cargo_order.dm), which gates
	/// both the listing and the order itself.
	///
	/// Same shape as requires_piracy_beacon deliberately: one declarative var on
	/// the item, checked in the same two places, rather than a second
	/// registration mechanism that could disagree with this one.
	var/restricted_to_faction

	/// If TRUE, every spawned piece that is faction-taggable gets tagged to the
	/// ordering console's own faction via the existing faction_tagger_set()
	/// interface -- so faction gear arrives already marked (and, for clothing,
	/// already wearing that faction's colour) instead of needing a tagger pass
	/// by hand.
	var/tag_spawned_to_faction = FALSE

	/// Optional colour applied to every spawned piece. Independent of
	/// tag_spawned_to_faction -- use it for a house look on items that are not
	/// faction-taggable, or to override the faction colour deliberately.
	var/spawned_color

/// Sets the item's adjusted_price according to different price modifiers. Returns nothing.
/singleton/cargo_item/proc/get_adjusted_price()
	var/return_price = price
	var/item_category = SScargo.get_category_by_name(category)
	var/item_supplier = SScargo.get_supplier_by_name(supplier)

	for(var/supplier_name in SScargo.cargo_suppliers)
		var/singleton/cargo_supplier/cs = SScargo.get_supplier_by_name(supplier_name)
		if(cs == item_supplier)
			return_price *= cs.price_modifier

	for(var/category_name in SScargo.cargo_categories)
		var/singleton/cargo_category/cc = SScargo.get_category_by_name(category_name)
		if(cc == item_category)
			return_price *= cc.price_modifier

	adjusted_price = return_price
