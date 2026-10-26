-- Intercity parcels: the parcels between the two intercity parcel sorting centers (parcel_sorting.script.tl). The export
-- center turns the parcels of a town into them, the import center turns them back into parcels. Only the import centers
-- take them (their input stock): their category is not in the cargo categories of the economy (mod.script.tl adds only
-- the parcels), so no town demands them. A cargo of its own keeps them apart from the parcels of the towns in the
-- warehouses and on the trains between the towns.
--
-- GOODS like the parcels, so the goods wagons, the cargo planes and the box vans carry them; not PARCEL, so the parcel
-- delivery points of the towns do not handle them. The price is that of the parcels (parcel.cargo.lua), and mod.script.tl
-- sets the delivery time of both from the mod parameters.
function data()
return
	{
		name = _("parcel_delivery_intercity_cargo_name"),
		weightFactor = 1.0,
		order = 277,
		icon = "parcel_export.tga",
		cargoClasses = { "UNIVERSAL", "GOODS" },
		category = "parcel_intercity",
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
		color = { 0.62, 0.45, 0.25 },
		loadSpeedFactor = 0.0625,
		-- that of the grain (the default of the mod parameter)
		timeToDeliverInSeconds = 1286,
	}
end
