-- Intercity parcel sorting center (export): the goods warehouse of the base game that takes the parcels of the
-- town and gives intercity parcels (built by parcel_sorting.script.tl). Built next to a train station or an airport,
-- whose lines take the intercity parcels to the import center of another town.
function data()
return {
	description = {
		name = _("parcel_delivery_sorting_export_name"),
		description = _("parcel_delivery_sorting_export_description"),
		icon = "parcel_sorting_export.tga",
		previewIcon = "parcel_sorting_export_preview.tga",
		attributes = {
			noise = { 20, -1 },
			pollution = { 40, -1 },
			cost = { 180000, -1 },
			maintenanceCost = { 30000, -1 },
		},
	},
	namePrefix = _("{townName} Parcel Export"),
	subConstructionNamePrefix = "{constructionName}",
	availability = {
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
		fileName = "parcel_sorting.script@updateFn",
		params = {
			kind = "export",
		},
	},
	createTemplateScript = {
		fileName = "parcel_sorting.script@createTemplateFn",
		params = {},
	},
}
end
