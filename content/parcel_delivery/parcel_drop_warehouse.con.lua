-- Parcel drop warehouse (trial): the goods warehouse of the base game with the parcel stock of the drop boxes, placed
-- without collision. It shows whether skipCollision keeps the stations from reaching a construction
-- (parcel_drop_warehouse.script.tl).
-- Retired: the trial is done (the drop box is built like it, with a ground area). Not in the menu any more, the game
-- script removes the built ones; kept for the savegames that have them.
function data()
return {
	description = {
		name = _("parcel_delivery_drop_warehouse_name"),
		description = _("parcel_delivery_drop_warehouse_description"),
		icon = "parcel_box.tga",
		previewIcon = "parcel_box.tga",
		attributes = {
			cost = { 10000, -1 },
			maintenanceCost = { 1000, -1 },
		},
	},
	namePrefix = _("{townName} Warehouse"),
	-- the only difference to the warehouse of the base game besides the parcels: placed without collision
	skipCollision = true,
	autoRemovable = false,
	availability = {
	},
	constructionTemplates = {
		{
			type = "DYNAMIC",
			availability = {
				yearFrom = 1,
				yearTo = 2,
			},
			description = {
				name = _("parcel_delivery_drop_warehouse_name"),
				description = _("parcel_delivery_drop_warehouse_description"),
				icon = "parcel_box.tga",
				previewIcon = "parcel_box.tga",
			},
			data = {
				params = {},
			},
			menuCategory = {
				categories = {
					{
						category = "road_buildings",
						filterCategories = { "cargo" },
						order = 1095,
					},
				},
			},
		},
	},
	order = 1095,
	soundConfig = {
		soundSet = { name = "::/warehouses/sound/warehouse.snd" },
		builderAudioRes = "::/gui/construction/sound/buildoze_construction_large.builder_audio",
	},
	params = {},
	createTemplateScript = {
		fileName = "parcel_drop_warehouse.script@createTemplateFn",
		params = {},
	},
	updateScript = {
		fileName = "parcel_drop_warehouse.script@updateFn",
		params = {},
	},
	preProcessScript = {
		fileName = "::/warehouses/warehouse.script@preProcessFn",
		params = {},
	},
}
end
