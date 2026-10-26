-- Construction of the parcel delivery point (parcel_box.con.lua, parcel_box_twosided.con.lua): a street stop like the
-- small stops of the base game (stations/street/small_stops/small_stops.script.lua) where box vans load and unload
-- parcels only, with three stacked cardboard boxes of the base game as model (two side by side, one on top). The
-- two-sided variant stops on both sides of the street (wantSymmetric), the game places the model on both sides like for
-- the two-sided small stops.

local production = ug_require "/parcel_delivery/production.tl" as PdProduction

local BoxModel <const> = "::/assets/buildings/ind/boxes/box_cardboard_cubic.mdl"
--- height (m) of the box model
local BoxHeight <const> = 0.82

--- a box at x, y, z turned by the angle (radians) about the vertical axis
local function box(x : number, y : number, z : number, angle : number) : table
	local c, s = math.cos(angle), math.sin(angle)
	return {
		model = {
			id = BoxModel,
			transf = { c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, x, y, z, 1 },
		},
	}
end

local record Params
	serviceRadius : number
	twoSided : boolean
end

local script = {}

function script.updateFn(captureParams : Params, _params : table) : table
	return {
		streetTerminal = {
			capacity = 50,
			cargoLoad = true,
			cargoUnload = true,
			-- the parcel class of the mod only (cargos/classes/parcel.cargoclass.lua), so the stop handles parcels only; the
			-- station window shows its name (it fails without a class). (A trial with it that reached no parcel stock was
			-- made while the drop boxes had no ground area, which kept every stop from them.)
			cargoTransferSpeeds = {
				{
					cargoTypeSet = {
						cargoClassesExcluded = {},
						cargoClassesIncluded = { production.ParcelClass },
						cargoTypesExcluded = {},
						cargoTypesIncluded = {},
					},
					length = 0,
					loadSpeedModifier = 1,
				},
			},
			catchmentArea = {
				position = { 0, 0, 0 },
				radius = captureParams.serviceRadius,
			},
			passengers = false,
			cargo = true,
			wantSymmetric = captureParams.twoSided == true,
		},
		edgeModels = {
			box(-0.42, 0, 0, 0.05),
			box(0.42, 0.03, 0, -0.08),
			box(0, 0.02, BoxHeight, 0.25),
		},
		cost = 20000,
		maintenanceCost = 2000,
		edgeObjectEmissionEmitter = {
			noise = 1,
			pollution = 1,
		},
	}
end

return script
