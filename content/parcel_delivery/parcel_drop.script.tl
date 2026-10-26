-- Construction of the parcel drop box (parcel_drop.con.lua): the mailbox of the base game on the sidewalk with the
-- parcel stock of the drop boxes (parcel_delivery/production.tl). The game script builds one next to every parcel
-- delivery point (the stops whose catchment reaches it); it can also be placed by hand, then it snaps to a street.
--
-- - placed without collision (skipCollision in parcel_drop.con.lua): no buildings are removed
-- - a small ground area (an empty ground texture and a collider): the stations reach the stock of a construction only
--   when it has one, a street connection is not needed
-- - the street is at -y: the mailbox faces it
--
-- Earlier versions were built by the warehouse script of the base game (with a goods module) and had a station or a
-- depot for a range display; createTemplateFn stays for their savegames.

local production = ug_require "/parcel_delivery/production.tl" as PdProduction

local MailboxModel <const> = "::/assets/buildings/com/misc/mailbox_a_01.mdl"
local EmptyGroundTexture <const> = "::/infrastructure/street/airport/none.gtex"
--- half size (m) of the ground area of the box
local FootprintHalfSize <const> = 1.5
--- distance (m) from the box to the center of the street it snaps to when placed by hand
local StreetDistance <const> = 0.5

local function translation(x : number, y : number, z : number) : {number}
	return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1 }
end

local script = {}

function script.createTemplateFn(_captureParams : table, _params : table) : table
	return {}
end

function script.updateFn(_captureParams : table, _params : table) : table
	local h = FootprintHalfSize
	local face = { { -h, -h, 0, 1 }, { h, -h, 0, 1 }, { h, h, 0, 1 }, { -h, h, 0, 1 } }
	return {
		subconstructions = {
			{
				laneLists = {},
				-- turned by 90 degrees counterclockwise, so the mailbox faces the street (-y)
				models = { { id = MailboxModel, transf = { 0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } } },
				groundFaces = {
					{
						face = face,
						modes = { { type = "FILL", key = EmptyGroundTexture, texCoords = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } } } },
					},
				},
				colliders = {
					{
						type = "BOX",
						transf = translation(0, 0, 0),
						params = { halfExtents = { h, h, 1 } },
					},
				},
				stocks = production.stocks(),
				rules = production.rules(),
				-- the game script finds the drop boxes by this key (forEachConstructionWithMetadata)
				metadata = { [production.DropMetadata] = true },
				tag = 0,
			},
		},
		snapPoint = {
			transf = translation(0, -StreetDistance, 0),
			snapToBaseEdgeTypes = { "STREET" },
		},
		cost = 10000,
		-- the maintenance of a small street stop of the base game (stations/street/small_stops)
		maintenanceCost = 5000,
	}
end

return script
