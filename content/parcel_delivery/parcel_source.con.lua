-- Hidden parcel source of a mailbox: an invisible construction with an output stock for parcels, built at every mailbox
-- by the game script (parcel_delivery.script.tl) because street stops cannot hold stocks. It is not in the build menu;
-- its params.mailbox is the edge object of its mailbox.
function data()
return {
	description = {
		name = _("parcel_delivery_source_name"),
		description = "",
	},
	availability = {
	},
	skipCollision = true,
	autoRemovable = false,
	params = {},
	updateScript = {
		fileName = "parcel_source.script@updateFn",
		params = {},
	},
}
end
