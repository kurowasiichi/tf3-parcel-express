-- Parcel drop box: a mailbox on the sidewalk that collects the parcels of the residents around it (built by
-- parcel_drop.script.tl). The game script builds one next to every parcel delivery point; box vans load its parcels
-- there. Placed without collision, so no buildings are removed. Not in the build menu.
function data()
return {
	description = {
		name = _("parcel_delivery_drop_name"),
		description = _("parcel_delivery_drop_description"),
		icon = "parcel_box.tga",
		previewIcon = "parcel_box.tga",
		attributes = {
			cost = { 10000, -1 },
			-- that of a small one-sided street stop of the base game
			maintenanceCost = { 5000, -1 },
		},
	},
	-- placed without collision and not removed by other building work, like the assets of the asset placer
	-- (scripts/construction/assetbuilderutil.lua)
	skipCollision = true,
	autoRemovable = false,
	snapping = {
		road = true,
		rail = false,
		water = false,
	},
	availability = {
	},
	-- not in the build menu (no menu category, like the hidden parcel sources of an early version): the game script
	-- builds the drop boxes with the delivery points
	order = 1090,
	soundConfig = {
		builderAudioRes = "::/gui/construction/sound/buildoze_construction_small.builder_audio",
		effects = {},
		soundSet = {
			name = "",
		},
	},
	params = {},
	updateScript = {
		fileName = "parcel_drop.script@updateFn",
		params = {},
	},
}
end
