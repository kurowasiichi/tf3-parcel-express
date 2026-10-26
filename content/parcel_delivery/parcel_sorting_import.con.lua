-- Intercity parcel sorting center (import): the goods warehouse of the base game that takes the intercity
-- parcels and gives parcels for the residential districts of the town (built by parcel_sorting.script.tl). Built next to
-- a train station or an airport, whose lines bring the intercity parcels from the export center of another town.
function data()
return {
	description = {
		name = _("parcel_delivery_sorting_import_name"),
		description = _("parcel_delivery_sorting_import_description"),
		icon = "parcel_sorting_import.tga",
		previewIcon = "parcel_sorting_import_preview.tga",
		attributes = {
			noise = { 20, -1 },
			pollution = { 40, -1 },
			cost = { 180000, -1 },
			maintenanceCost = { 30000, -1 },
		},
	},
	namePrefix = _("{townName} Parcel Import"),
	subConstructionNamePrefix = "{constructionName}",
	availability = {
	},
	order = 1051,
	menuCategory = {
		categories = {
			{
				category = "road_buildings",
				filterCategories = { "cargo" },
				order = 1051,
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
			kind = "import",
		},
	},
	createTemplateScript = {
		fileName = "parcel_sorting.script@createTemplateFn",
		params = {},
	},
}
end
