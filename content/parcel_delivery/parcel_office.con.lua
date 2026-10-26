-- Post office: a building at the street like the road maintenance station, with its own loading point for box vans
-- (built by parcel_office.script.tl). It collects the parcels of the residents around it: the game script
-- (parcel_delivery.script.tl) fills its stock, and lines of box vans stop at it like at the terminal of an industry.
-- Retired: the parcel drop boxes with the delivery points do its work. Not in the menu any more; the built ones keep
-- working (they are stops of lines, so they are not removed by the script) and the file is kept for them.
function data()
return {
	description = {
		name = _("parcel_delivery_office_name"),
		description = _("parcel_delivery_office_description"),
		icon = "parcel_box.tga",
		previewIcon = "parcel_box.tga",
		attributes = {
			noise = { 10, -1 },
			pollution = { 20, -1 },
			cost = { 60000, -1 },
			maintenanceCost = { 10000, -1 },
		},
		cargoTypeSet = {
			cargoClassesIncluded = { "GOODS" },
		},
	},
	namePrefix = _("{townName} Post Office"),
	subConstructionNamePrefix = "{constructionName}",
	availability = {
		yearFrom = 1,
		yearTo = 2,
	},
	order = 1040,
	menuCategory = {
		categories = {
			{
				category = "road_buildings",
				filterCategories = { "cargo" },
				order = 1040,
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
	params = {},
	updateScript = {
		fileName = "parcel_office.script@updateFn",
		params = {},
	},
}
end
