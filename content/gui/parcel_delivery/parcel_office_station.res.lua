-- Registers StationParcelsPlugin (see office_eow.script.tl): the parcels of a post office in the window of its station.
function data()
	return {
		type = "react-plugin ::StationGroupEowExtensionPoint",
		data = {
			filePath = "parcel_delivery::/gui/parcel_delivery/office_eow.script@StationParcelsPlugin",
			order = 5,
		}
	}
end
