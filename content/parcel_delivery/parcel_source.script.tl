-- Construction of the hidden parcel source (parcel_source.con.lua): an invisible model and an output stock for parcels,
-- set up like the output stock of an industry but without a rule. The game script puts the parcels into it, the
-- mailbox it stands at loads them.

local EmptyModel <const> = "parcel_delivery::/parcel_delivery/empty.mdl"
local ParcelCargo <const> = "parcel_delivery::/cargos/parcel/parcel.cargo"
local StockCapacity <const> = 100

--- length (m) of the person lanes from the source in four directions
local LinkLaneLength <const> = 4

--- A short linkable person lane from the origin: the game links linkable lanes to the network nearby (like the platforms
--- of stations to the sidewalks). A construction without lanes is not on the network, and no station catchment reaches
--- its stock.
local function linkLane(dx : number, dy : number) : table
	local tangent = { dx, dy, 0 }
	return {
		nodes = {
			{ { 0, 0, 0 }, tangent, 1 },
			{ { dx, dy, 0 }, tangent, 1 },
		},
		transportModes = { "PERSON" },
		speedLimit = 2,
		linkable = true,
	}
end

local script = {}

function script.updateFn(_captureParams : table, _params : table) : table
	local l = LinkLaneLength
	return {
		subconstructions = {
			{
				laneLists = { linkLane(l, 0), linkLane(-l, 0), linkLane(0, l), linkLane(0, -l) },
				groundFaces = {},
				models = {
					{ id = EmptyModel, transf = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } },
				},
				stocks = {
					{
						type = "OUTPUT_STOCK",
						cargoType = ParcelCargo,
						capacity = StockCapacity,
						decayRateFactor = 0,
					},
				},
				rules = {},
				metadata = {},
				tag = 0,
			},
		},
		cost = 0,
		maintenanceCost = 0,
	}
end

return script
