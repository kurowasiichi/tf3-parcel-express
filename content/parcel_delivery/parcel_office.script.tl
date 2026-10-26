-- Construction of the post office (parcel_office.con.lua): a building at the street like the road maintenance station,
-- with a loading point for box vans, like the terminals of the industries (industries/industryutil.lua, addTerminals):
-- - an entrance street from the street the construction snaps to (like the industry entrances)
-- - a one-way loop for the vans: in at the right lane of the entrance, past the loading point, turning and out at the
--   left lane; the ends of the loop link to the lanes of the entrance street
-- - a station with one terminal on the loop, and a parcel output stock (filled by the game script) in its catchment
-- - the side building of the modular street station of the era as the post office, left of the loop
--
-- Local coordinates: the entrance street runs along +y and ends at y = 0, the loop and the building lie at y > 0.

local production = ug_require "/parcel_delivery/production.tl" as PdProduction

local StockModel <const> = "parcel_delivery::/parcel_delivery/empty.mdl"
local MailboxModel <const> = "::/assets/buildings/com/misc/mailbox_a_01.mdl"
local AsphaltTexture <const> = "::/terrain/materials/asphalt_02/asphalt_02.gtex"
local EntranceStreetOld <const> = "::/infrastructure/street/constructions/ind_entrance_old_country.street_template"
local EntranceStreetNew <const> = "::/infrastructure/street/constructions/ind_entrance_new_country.street_template"
local BuildingDir <const> = "::/stations/street/modular_street_station/models/sidebuildings/"
--- the side building by era (the eras of the modular street station)
local function buildingModel(year : number) : string
	local era = year < 1950 and "a" or (year < 1990 and "b" or "c")
	return BuildingDir .. "streetstation_sidebuilding_era_" .. era .. "_s2.mdl"
end

--- catchment radius (m) of the station when the construction params give none: the collection radius of the game
--- script, set from the mod parameter by mod.script.tl (construction scripts cannot read the mod parameters). Shown like
--- the catchment of any station; residential districts in it receive parcels.
local DefaultCatchmentRadius <const> = 150
--- distance (m) from the end of the entrance street to the street the construction snaps to
local StreetDistance <const> = 6
--- offset (m) of the lanes of the entrance street from its center
local LaneOffset <const> = 2
--- the loading point and the turn of the loop (y, m)
local TerminalFrom <const> = 4
local TerminalAt <const> = 12
local TurnAt <const> = 16
--- the post office (20 x 20 m), left of the loop
local BuildingCenterX <const> = -15
local BuildingCenterY <const> = 10

local function translation(x : number, y : number, z : number) : {number}
	return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1 }
end

--- rotated by 180 degrees: the side buildings face +y in their module, the street here is at -y
local function turned(x : number, y : number) : {number}
	return { -1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, x, y, 0, 1 }
end

--- a lane from a to b with the tangents ta and tb
local function lane(a : {number}, ta : {number}, b : {number}, tb : {number}, modes : {string}, speed : number, width : number) : table
	return {
		nodes = { { a, ta, width }, { b, tb, width } },
		transportModes = modes,
		speedLimit = speed,
		linkable = true,
	}
end

local function straight(a : {number}, b : {number}, modes : {string}, speed : number, width : number) : table
	local t = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
	return lane(a, t, b, t, modes, speed, width)
end

local function rectangle(x0 : number, y0 : number, x1 : number, y1 : number) : {{number}}
	return { { x0, y0, 0 }, { x1, y0, 0 }, { x1, y1, 0 }, { x0, y1, 0 } }
end

local script = {}

function script.updateFn(captureParams : table, params : table) : table
	local catchmentRadius = tonumber(captureParams ~= nil and captureParams.catchmentRadius or nil) or DefaultCatchmentRadius
	local year = tonumber(params.year) or 1990
	local vans = { "TRUCK" }
	local r = LaneOffset

	-- laneLists of the station (0-based indices): 0 in, 1 person, 2 to the loading point, 3 from it (the vans stop at
	-- its first node), 4 the turn, 5 out
	local laneLists = {
		straight({ r, 0, 0 }, { r, TerminalFrom, 0 }, vans, 20, 3),
		straight({ r + 3, (TerminalFrom + TerminalAt) / 2, 0 }, { r + 5, (TerminalFrom + TerminalAt) / 2, 0 }, { "PERSON" }, 2, 2),
		straight({ r, TerminalFrom, 0 }, { r, TerminalAt, 0 }, vans, 20, 3),
		straight({ r, TerminalAt, 0 }, { r, TurnAt, 0 }, vans, 20, 3),
		lane({ r, TurnAt, 0 }, { 0, 10, 0 }, { -r, TurnAt, 0 }, { 0, -10, 0 }, vans, 10, 3),
		straight({ -r, TurnAt, 0 }, { -r, 0, 0 }, vans, 20, 3),
	}
	local terminal = {
		personEdges = { { 1, 0 } },
		personNodes = { { 1, 0 } },
		vehicleNode = { 3, 0 },
		transportModes = vans,
		capacity = 4,
		cargo = true,
		passengers = false,
		cargoTransferSpeeds = {
			{
				-- GOODS like the parcel delivery points (parcel_box.script.tl)
				cargoTypeSet = { cargoClassesIncluded = { "GOODS" } },
				loadSpeedModifier = 2,
			},
		},
	}

	local ground = rectangle(BuildingCenterX - 11, 0, r + 6, TurnAt + 6)
	local from = { 0, -StreetDistance - 2, 0 }
	local to = { 0, 0, 0 }
	local tangent = { 0, to[2] - from[2], 0 }
	return {
		edgeLists = {
			{
				type = "STREET",
				params = { type = year < 1925 and EntranceStreetOld or EntranceStreetNew },
				edges = {
					{ from, tangent },
					{ to, tangent },
				},
				snapNodes = { 0 },
				freeNodes = {},
			},
		},
		subconstructions = {
			{
				laneLists = {},
				groundFaces = {
					{
						face = ground,
						modes = { { type = "FILL", key = AsphaltTexture, texCoords = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } } },
					},
				},
				terrainAlignmentLists = { { type = "EQUAL", faces = { ground } } },
				models = {
					{ id = buildingModel(year), transf = turned(BuildingCenterX, BuildingCenterY) },
					{ id = MailboxModel, transf = translation(r + 4, TerminalAt, 0) },
					-- the stock needs a model for its position
					{ id = StockModel, transf = translation(r + 4, (TerminalFrom + TerminalAt) / 2, 0) },
				},
				-- the parcels and the parcels handed in (filled by the game script), see parcel_delivery/production.tl
				stocks = production.stocks(),
				rules = production.rules(),
				metadata = {},
				tag = 0,
			},
			{
				laneLists = laneLists,
				models = {},
				groundFaces = {},
				terrainAlignmentLists = { { type = "EQUAL" } },
				station = {
					terminals = { terminal },
					tag = 1,
					pool = { edges = {}, capacity = 0 },
					catchmentAreas = { { position = { 0, 0, 0 }, radius = catchmentRadius } },
				},
				tag = 1000,
			},
		},
		snapPoint = {
			transf = translation(0, -StreetDistance, 0),
			snapToBaseEdgeTypes = { "STREET" },
		},
		cost = 60000,
		maintenanceCost = 10000,
	}
end

return script
