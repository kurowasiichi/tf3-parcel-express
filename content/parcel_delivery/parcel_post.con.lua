-- Parcel post: a mailbox on the sidewalk that collects the parcels of the residents around it. Stocks only reach a
-- station catchment when their construction is on the network, which takes a street (like the entrance of a depot):
-- a very short entrance street connects it to the street it stands at. Box vans load the parcels at a parcel mailbox
-- stop (parcel_box.con.lua) or any cargo stop whose catchment area covers it. The game script
-- (parcel_delivery.script.tl) fills its stock.
-- Retired (a trial before the post office): not in the menu any more, the game script removes the built ones. Kept for
-- the savegames that have them.
function data()
return {
	description = {
		name = _("parcel_delivery_post_name"),
		description = _("parcel_delivery_post_description"),
		icon = "parcel_box.tga",
		previewIcon = "parcel_box.tga",
		attributes = {
			cost = { 10000, -1 },
			maintenanceCost = { 1000, -1 },
		},
	},
	availability = {
		yearFrom = 1,
		yearTo = 2,
	},
	order = 1050,
	menuCategory = {
		categories = {
			{
				category = "road_buildings",
				filterCategories = { "cargo" },
				order = 1050,
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
		fileName = "parcel_post.script@updateFn",
		params = {},
	},
}
end
