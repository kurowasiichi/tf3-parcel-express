-- Parcel delivery point (both sides of the street): a street stop like the small stops of the base game where box vans
-- load and unload parcels only (three stacked boxes, parcel_box.script.tl).
-- Street stops cannot hold stocks: the parcels come from the post offices and parcel drop boxes in the catchment.
function data()
-- the catchment of the small street stops of the base game
local serviceRadius = 160
return {
	availability = {
	},
	description = {
		attributes = {
			cost = { 20000, -1 },
			maintenanceCost = { 2000, -1 },
		},
		description = _("parcel_delivery_box_description"),
		icon = "parcel_box.tga",
		name = _("parcel_delivery_box_twosided_name"),
		previewIcon = "parcel_box_preview.tga",
		cargoTypeSet = {
			cargoClassesExcluded = {},
			cargoClassesIncluded = { "PARCEL" },
			cargoTypesExcluded = {},
			cargoTypesIncluded = {},
		},
	},
	menuCategory = {
		categories = {
			{
				category = "road_buildings",
				filterCategories = { "cargo" },
				order = 1101,
			},
		},
	},
	soundConfig = {
		builderAudioRes = "::/gui/construction/sound/buildoze_construction_small.builder_audio",
		effects = {},
		soundSet = {
			name = "",
		},
	},
	updateScript = {
		fileName = "parcel_box.script@updateFn",
		params = {
			serviceRadius = serviceRadius,
			twoSided = true,
		},
	},
	configureHudIconsScript = {
		fileName = "::/gui/construction/construction_desc_hud_icons.script@configureStationHudIconsFn",
		params = {
			cargo = true,
		},
	},
	edgeObject = {
		snapToStreet = true,
		catchmentCargo = true,
		catchmentPassengers = false,
		catchmentAreaRadius = serviceRadius,
		minDistToCrossing = 10,
	},
	params = {},
}
end
