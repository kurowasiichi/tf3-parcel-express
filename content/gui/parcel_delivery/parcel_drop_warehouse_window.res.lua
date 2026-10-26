-- Registers WarehouseParcelsPlugin (see office_eow.script.tl): the parcels of a parcel drop box, whose window is that of
-- a warehouse.
function data()
	return {
		type = "react-plugin ::WarehouseEowExtensionPoint",
		data = {
			filePath = "parcel_delivery::/gui/parcel_delivery/office_eow.script@WarehouseParcelsPlugin",
			order = 5,
		}
	}
end
