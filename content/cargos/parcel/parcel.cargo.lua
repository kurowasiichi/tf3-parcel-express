-- Parcels: GOODS cargo (box vans), produced by the parcel collection points (parcel_delivery.script.tl) and demanded by
-- the residential districts of the towns.
--
-- Price: the base cargos earn 3.8 per meter (economy/cargotype.script.lua, constantFn with 4 and 3.2). Parcels earn less
-- the longer they take, along the logistic curve of logisticDecayFn over the delivery time (by default that of the
-- grain, 1286 s; with a day of 2000 ms, 643 days):
-- - initialPrice 4.56 (1.2 x 3.8) and finalPrice 3.04 (0.8 x 3.8) are the limits of the curve;
-- - decayStart 321.5 days is half of the delivery time, where the price is halfway, 3.8 (decayMod 1: the plain
--   logistic curve);
-- - decayRate 5 / 321.5 keeps it near the limits at the start (1.197 x) and at the end (0.803 x) of the delivery time.
-- mod.script.tl sets the delivery time from the mod parameters, and decayStart and decayRate with it.
function data()
return
	{
		name = _("parcel_delivery_cargo_name"),
		weightFactor = 1.0,
		order = 275,
		icon = "parcel.tga",
		-- PARCEL: the class of the parcel delivery points, which handle parcels only (cargos/classes/parcel.cargoclass.lua);
		-- GOODS: the box vans carry them
		cargoClasses = { "UNIVERSAL", "GOODS", "PARCEL" },
		category = "parcel",
		categoryList = {
			categories = {
				"temperate.eco",
				"dry.eco",
				"tropic.eco",
				"subarctic.eco"
			}
		},
		scriptRef = {
			fileName = "::/economy/cargotype.script@incomeFactors.logisticDecayFn",
			params = {
				initialPrice = 4.56,
				finalPrice = 3.04,
				decayRate = 0.015552,
				decayMod = 1,
				decayStart = 321.5,
			}
		},
		color = { 0.85, 0.62, 0.35 },
		loadSpeedFactor = 0.0625,
		-- that of the grain (the default of the mod parameter)
		timeToDeliverInSeconds = 1286,
	}
end
