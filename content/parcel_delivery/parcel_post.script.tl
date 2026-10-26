-- Construction of the parcel post (parcel_post.con.lua): the mailbox of the base game on the sidewalk, an output stock
-- for parcels (filled by the game script) and a very short entrance street that connects the construction to the
-- street, like the entrance of the road depot (depots/road/road_depot/road_depot.script.lua): the first node snaps to
-- the street, the snap point of the construction lies on it.

local MailboxModel <const> = "::/assets/buildings/com/misc/mailbox_a_01.mdl"
local EntranceStreet <const> = "::/infrastructure/street/constructions/entrance_new.street_template"
local production = ug_require "/parcel_delivery/production.tl" as PdProduction

--- distance (m) from the mailbox to the street the construction snaps to, and the end of the entrance street
local StreetDistance <const> = 6
local EntranceEnd <const> = 1

local function translation(x : number, y : number, z : number) : {number}
	return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1 }
end

local script = {}

function script.updateFn(_captureParams : table, _params : table) : table
	local from = { 0, -StreetDistance - 2, 0 }
	local to = { 0, -EntranceEnd, 0 }
	local tangent = { 0, to[2] - from[2], 0 }
	return {
		edgeLists = {
			{
				type = "STREET",
				params = { type = EntranceStreet },
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
				groundFaces = {},
				models = {
					{ id = MailboxModel, transf = translation(0, 0, 0) },
				},
				-- the parcels and the parcels handed in (filled by the game script), see parcel_delivery/production.tl
				stocks = production.stocks(),
				rules = production.rules(),
				metadata = {},
				tag = 0,
			},
		},
		snapPoint = {
			transf = translation(0, -StreetDistance, 0),
			snapToBaseEdgeTypes = { "STREET" },
		},
		cost = 10000,
		maintenanceCost = 1000,
	}
end

return script
