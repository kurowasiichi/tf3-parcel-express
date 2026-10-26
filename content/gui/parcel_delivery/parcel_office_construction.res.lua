-- Registers ConstructionParcelsPlugin (see office_eow.script.tl): the parcels of a parcel post in the window of its
-- construction.
function data()
	return {
		type = "react-plugin ::EmptyConstructionEowExtensionPoint",
		data = {
			filePath = "parcel_delivery::/gui/parcel_delivery/office_eow.script@ConstructionParcelsPlugin",
			order = 5,
		}
	}
end
