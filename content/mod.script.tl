-- - Adds the parcels to the cargo categories of every economy (economy/placementparamsutil.lua, getCargoCategories): a
--   residential cargo like the town cargos of the base game, whose townConsumptionFactor sets the demand of the
--   residential districts. Parcels need no industry, every town demands them.
-- - Passes the range of the mod parameters (the collection range of the drop boxes, parcel_delivery.script.tl) to the
--   parcel delivery points (parcel_box.con.lua, parcel_box_twosided.con.lua) as their catchment radius, so it is the
--   circle drawn while one is placed, and to the retired post office (parcel_office.con.lua): construction scripts
--   cannot read the mod parameters.
-- - Sets the delivery time of the parcels and of the intercity parcels from the mod parameters, and the price curve
--   along with it.

-- addModifier is defined by the game in mod.lua, its Teal definition has a different signature
local type ModifierFn = function(fileName : string, data : table) : table
local addResourceModifier = addModifier as function(category : string, fn : ModifierFn)

--- the category of parcel.cargo.lua
local ParcelCategory <const> = "parcel"
--- demand of the residential districts (the base game uses 1 for the basic town cargos, 0.5 and 0.25 for later ones);
--- 5.3 gave a demand of about twice the population in a new game; 2.7 still put some towns above their population, 2.5
--- keeps it at or a little below. The mod parameter multiplies it (the options of the demand parameter); the factor is
--- stored in the savegame when a new game starts.
local TownConsumptionFactor <const> = 2.5
local DemandParam <const> = "parcel_delivery_demand"
local DemandSteps <const> : {number} = { 0.5, 0.75, 1, 1.25, 1.5 }
local DefaultDemandIndex <const> = 3
--- the constructions taking the range, and the options of the range parameter (the same as in
--- parcel_delivery.script.tl): 1x is the catchment of the small street stops of the base game, 160 m
local OfficeFile <const> = "parcel_office.con"
local DeliveryPointFile <const> = "parcel_box"
local RadiusParam <const> = "parcel_delivery_radius"
local RadiusSteps <const> : {number} = { 160, 200, 240, 320 }
local DefaultRadiusIndex <const> = 1
--- the parcel cargos (the parcels and the intercity parcels), and the options of the delivery time parameter: the
--- timeToDeliverInSeconds of the vegetables, the grain (default), the wool and the furniture of the base game
local ParcelCargoFile <const> = "parcel.cargo"
local IntercityCargoFile <const> = "parcel_intercity.cargo"
local DeliveryTimeParam <const> = "parcel_delivery_time"
local DeliveryTimeSteps <const> : {integer} = { 1125, 1286, 1500, 1800 }
local DefaultDeliveryTimeIndex <const> = 2
--- game time (ms) of a day, as in economy/cargotype.script.lua
local MillisPerDay <const> = 2000
--- the price curve (parcel.cargo.lua, logisticDecayFn) is centered on half the delivery time and this many decay
--- units wide on each side, so it is near its limits at the start and at the end of the delivery time
local DecaySpan <const> = 5

--- the option of a parameter (1-based index), the default if missing
local function step<T>(params : {string : integer}, key : string, steps : {T}, default : integer) : T
	local index = params ~= nil and tonumber(params[key]) or nil
	return steps[index ~= nil and math.floor(index) or default] or steps[default]
end

local mod = {}

mod.runFn = function(_captureParams : table, _configDict : {{string, string}}, allModParams : {string : {string : integer}})
	local params = allModParams ~= nil and allModParams[getCurrentModId()] or nil

	local demand = TownConsumptionFactor * step(params, DemandParam, DemandSteps, DefaultDemandIndex)
	addResourceModifier("loadEconomy", function(_fileName : string, data : table) : table
		local categories = data ~= nil and data.cargoCategories as table or nil
		if categories ~= nil and categories[ParcelCategory] == nil then
			categories[ParcelCategory] = {
				tier = 0,
				landUses = { "RESIDENTIAL" },
				requiredIndustryTags = {},
				townConsumptionFactor = demand,
			}
		end
		return data
	end)

	local deliveryTime = step(params, DeliveryTimeParam, DeliveryTimeSteps, DefaultDeliveryTimeIndex)
	addResourceModifier("loadCargoType", function(fileName : string, data : table) : table
		local name = fileName or ""
		if data == nil or (string.find(name, ParcelCargoFile, 1, true) == nil and string.find(name, IntercityCargoFile, 1, true) == nil) then
			return data
		end
		data.timeToDeliverInSeconds = deliveryTime
		local scriptRef = data.scriptRef as table
		local curve = scriptRef ~= nil and scriptRef.params as table or nil
		if curve ~= nil then
			local halfDays = deliveryTime * 1000 / MillisPerDay / 2
			curve.decayStart = halfDays
			curve.decayRate = DecaySpan / halfDays
		end
		return data
	end)

	local radius = step(params, RadiusParam, RadiusSteps, DefaultRadiusIndex)
	addResourceModifier("loadConstruction", function(fileName : string, data : table) : table
		if data == nil then
			return data
		end
		local name = fileName or ""
		local updateScript = data.updateScript as table
		if string.find(name, DeliveryPointFile, 1, true) ~= nil then
			-- the catchment of the stop: drawn while placing (edgeObject) and the terminal (parcel_box.script.tl)
			local edgeObject = data.edgeObject as table
			if edgeObject ~= nil then
				edgeObject.catchmentAreaRadius = radius
			end
			if updateScript ~= nil then
				local scriptParams = (updateScript.params or {}) as table
				scriptParams.serviceRadius = radius
				updateScript.params = scriptParams
			end
		elseif string.find(name, OfficeFile, 1, true) ~= nil and updateScript ~= nil then
			local scriptParams = (updateScript.params or {}) as table
			scriptParams.catchmentRadius = radius
			updateScript.params = scriptParams
		end
		return data
	end)
end

return mod
