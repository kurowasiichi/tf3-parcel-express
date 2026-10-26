-- Cargo class of the parcels (parcel.cargo.lua): the parcel delivery points (parcel_box.script.tl) load and unload this
-- class only, and the station window shows its name for their terminals. The parcels are also GOODS, so the box vans
-- carry them.
function data()
	return {
		tag = "PARCEL",
		name = _("parcel_delivery_class_name"),
		description = "",
		icon = "parcel_class.tga",
		order = 7,
		color = { 217/255, 158/255, 89/255 },
	}
end
