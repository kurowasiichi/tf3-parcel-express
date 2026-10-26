-- Parcel drop box (range test): the parcel drop box (parcel_drop.con.lua) that shows its collection range while it is
-- placed, as the catchment of a station no vehicle reaches (parcel_drop.script.tl, showRange; the radius is passed by
-- mod.script.tl). A trial whether the range display works.
-- Retired: the delivery points show the range and get their drop boxes from the game script. Not in the menu any more,
-- the game script removes the built ones; kept for the savegames that have them.
function data()
return {
	description = {
		name = _("parcel_delivery_drop_range_test_name"),
		description = _("parcel_delivery_drop_range_test_description"),
		icon = "parcel_box.tga",
		previewIcon = "parcel_box.tga",
		attributes = {
			cost = { 10000, -1 },
			maintenanceCost = { 5000, -1 },
		},
	},
	skipCollision = true,
	autoRemovable = false,
	snapping = {
		road = true,
		rail = false,
		water = false,
	},
	availability = {
	},
	-- the station icons and catchment areas while placing, like a cargo station
	configureHudIconsScript = {
		fileName = "::/gui/construction/construction_desc_hud_icons.script@configureStationHudIconsFn",
		params = {
			cargo = true,
		},
	},
	constructionTemplates = {
		{
			type = "DYNAMIC",
			configureHudIconsScript = {
				fileName = "::/gui/construction/construction_desc_hud_icons.script@configureStationHudIconsFn",
				params = {
					cargo = true,
				},
			},
			availability = {
				yearFrom = 1,
				yearTo = 2,
			},
			description = {
				name = _("parcel_delivery_drop_range_test_name"),
				description = _("parcel_delivery_drop_range_test_description"),
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
						order = 1091,
					},
				},
			},
		},
	},
	order = 1091,
	soundConfig = {
		builderAudioRes = "::/gui/construction/sound/buildoze_construction_small.builder_audio",
		effects = {},
		soundSet = {
			name = "",
		},
	},
	params = {},
	createTemplateScript = {
		fileName = "parcel_drop.script@createTemplateFn",
		params = {},
	},
	updateScript = {
		fileName = "parcel_drop.script@updateFn",
		params = {
			showRange = true,
		},
	},
	preProcessScript = {
		fileName = "::/warehouses/warehouse.script@preProcessFn",
		params = {},
	},
}
end
