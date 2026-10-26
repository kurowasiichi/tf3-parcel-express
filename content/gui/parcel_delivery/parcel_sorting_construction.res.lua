-- Registers SortingPlugin (see sorting_eow.script.tl): the production, boosters and stock cards of the intercity parcel
-- sorting centers in the window of their construction.
function data()
	return {
		type = "react-plugin ::EmptyConstructionEowExtensionPoint",
		data = {
			filePath = "parcel_delivery::/gui/parcel_delivery/sorting_eow.script@SortingPlugin",
			order = 5,
		}
	}
end
