-- Parcels handed in: no longer used. A version had them as the input of the parcel stocks with a rule turning them into
-- parcels, but the rule did not convert them. Kept only for the savegames with post offices of that version (their
-- stock lists refer to it); in no cargo class, so no vehicle carries it.
function data()
return
	{
		name = _("parcel_delivery_input_cargo_name"),
		weightFactor = 1.0,
		order = 276,
		icon = "parcel.tga",
		cargoClasses = {},
		category = "parcel_input",
		categoryList = {
			categories = {
				"temperate.eco",
				"dry.eco",
				"tropic.eco",
				"subarctic.eco"
			}
		},
		scriptRef = {
			fileName = "::/economy/cargotype.script@incomeFactors.constantFn",
			params = {
				initialPrice = 0,
				finalPrice = 0,
				decayRate = 0.01,
				decayMod = 0.1,
				decayStart = 50,
			}
		},
		color = { 0.85, 0.62, 0.35 },
		loadSpeedFactor = 0.0625,
		timeToDeliverInSeconds = 1500,
	}
end
