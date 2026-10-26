-- Registers ParcelLinePlugin (see line_eow.script.tl): the parcels waiting at the stops of a line.
function data()
	return {
		type = "react-plugin ::LineEowExtensionPoint",
		data = {
			filePath = "parcel_delivery::/gui/parcel_delivery/line_eow.script@ParcelLinePlugin",
			order = 45,
		}
	}
end
