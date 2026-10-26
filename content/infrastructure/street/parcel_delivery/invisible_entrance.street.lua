-- Street style of the invisible entrance of the parcel drop boxes of one earlier version
-- (invisible_entrance.street_template.lua): no material for any part, so nothing is drawn. No longer used (the drop
-- boxes are linked to the sidewalk like the warehouses), kept for the savegames that have such entrances.
function data()
return {
	roadType = "STREET",
	materials = {
		streetPaving = { name = "" },
		streetBorder = { name = "" },
		crossingBorder = { name = "" },
		junctionBorder = { name = "" },
		streetLane = { name = "" },
		streetArrow = { name = "" },
		streetStripe = { name = "" },
		junctionStripe = { name = "" },
		streetTram = { name = "" },
		streetTramTrack = { name = "" },
		streetBus = { name = "" },
		crossingLane = { name = "" },
		crossingBus = { name = "" },
		crossingTram = { name = "" },
		crossingTramTrack = { name = "" },
		sidewalkPaving = {},
		sidewalkLane = {},
		sidewalkBorderInner = {},
		sidewalkBorderOuter = {},
		sidewalkCurb = {},
		sidewalkWall = {},
	},
	assets = {},
	arrowIndices = {
		LEFT = 0,
		STRAIGHT = 1,
		RIGHT = 2,
		LEFT_STRAIGHT = 3,
		RIGHT_STRAIGHT = 4,
		LEFT_RIGHT = 5,
		LEFT_RIGHT_STRAIGHT = 6
	},
}
end
