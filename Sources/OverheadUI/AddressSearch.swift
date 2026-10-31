import MapKit
import OverheadKit

/// Street-address lookup through Apple Maps, which is built into the Apple TV. The address you type goes to Apple Maps
/// and nowhere else, and only the resulting point and town name are kept.
enum AddressSearch {
    static func find(_ text: String) async throws -> [AddressMatch] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        do {
            let response = try await MKLocalSearch(request: request).start()
            return AddressMatch.usable(response.mapItems.compactMap(match))
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        }
    }

    private static func match(_ item: MKMapItem) -> AddressMatch? {
        let coordinate: CLLocationCoordinate2D
        let full: String
        var town: String?
        if #available(iOS 26, tvOS 26, macOS 26, *) {
            coordinate = item.location.coordinate
            full = item.address?.fullAddress ?? item.name ?? ""
            town = item.addressRepresentations?.cityWithContext
        } else {
            let placemark = item.placemark
            coordinate = placemark.coordinate
            full = placemark.title ?? item.name ?? ""
            town = [placemark.locality, placemark.administrativeArea].compactMap { $0 }.joined(separator: ", ")
        }
        let address = AddressMatch.singleLine(full)
        guard !address.isEmpty else { return nil }
        let place = (town?.isEmpty == false ? town : nil) ?? address
        return AddressMatch(address: address, placeName: place, location: GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
}
