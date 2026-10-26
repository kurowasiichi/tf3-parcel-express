-- Invisible entrance of the parcel drop boxes of one earlier version: the entrance street of the base game
-- (infrastructure/street/constructions/entrance_new.street_template.lua) with an invisible style and no ground
-- texture. No longer used (the drop boxes are linked to the sidewalk like the warehouses), kept for the savegames
-- that have such entrances.
function data()
return {
	availability = {
		yearFrom = 0,
		yearTo = 0,
	},
	borderGroundTex = "::/infrastructure/street/airport/none.gtex",
	cost = 0,
	description = {
		description = "",
		icon = "::/infrastructure/street/constructions/entrance_new.tga",
		name = "",
		previewIcon = "::/infrastructure/street/constructions/entrance_new_preview.tga",
	},
	emissions = {
		noise = 0,
		pollution = 0,
		pollutionRadius = 0,
		radius = 0,
	},
	fillGroundTex = "::/infrastructure/street/airport/none.gtex",
	initiallyLocked = true,
	laneConfigs = {
		{
			forward = false,
			height = 0.15,
			offset = 0.5,
			speed = 13.89,
			transportModes = { "PERSON", "CARGO", },
			width = 1,
		},
		{
			forward = false,
			height = 0,
			offset = 0,
			speed = 13.89,
			transportModes = { "CAR", "BUS", "TRUCK", },
			width = 1,
		},
		{
			forward = true,
			height = 0,
			offset = 0,
			speed = 13.89,
			transportModes = { "CAR", "BUS", "TRUCK", },
			width = 1,
		},
		{
			forward = true,
			height = 0.15,
			offset = -0.5,
			speed = 13.89,
			transportModes = { "PERSON", "CARGO", },
			width = 1,
		},
	},
	maintenanceCost = 0,
	modifiers = {
		maxSpeedModifier = 0,
		noiseModifier = 0,
		pollutionModifier = 0,
	},
	priority = 20,
	roadType = "STREET",
	sidewalkFillGroundTex = "::/infrastructure/street/airport/none.gtex",
	streetStyle = "parcel_delivery::/infrastructure/street/parcel_delivery/invisible_entrance.street",
	builderAudioRes = "::/gui/construction/sound/buildoze_street.builder_audio",
}
end
