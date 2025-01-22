import 'package:location/location.dart';

class LocationService {
  final Location _location = Location();

  // Configure location settings in the constructor
  LocationService() {
    // Request high accuracy and set a minimum distance filter (in meters)
    _location.changeSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
  }

  Future<LocationData?> getCurrentLocation() async {
    // Check permissions
    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return null; // Permission denied
      }
    }

    // Check if location service is enabled
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        return null; // Location service not enabled
      }
    }

    // Get current location
    return await _location.getLocation();
  }

  // Continuous location tracking stream
  Stream<LocationData> trackLocation() {
    return _location.onLocationChanged;
  }
}
