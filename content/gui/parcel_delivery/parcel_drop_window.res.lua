-- Leaves the close-up view out of the window of the parcel drop boxes (see office_eow.script.tl, doReplaceFn).
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "parcel_delivery::/gui/parcel_delivery/office_eow.script",
			doReplaceFn = "doReplaceFn",
		},
	}
end
