import 'package:location/location.dart';

class LocationService {
  final Location _location = Location();
  LocationData? _lastKnownLocation;
  Stream<LocationData>? _locationStream;

  // Configure location settings in the constructor
  LocationService() {
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    // Request high accuracy and set a minimum distance filter (in meters)
    await _location.changeSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
    );

    // Start tracking location immediately
    _locationStream = _location.onLocationChanged;
    _locationStream?.listen((LocationData location) {
      _lastKnownLocation = location;
    });
  }

  Future<LocationData?> getCurrentLocation() async {
    // If we already have a location, return it immediately
    if (_lastKnownLocation != null) {
      return _lastKnownLocation;
    }

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
    _lastKnownLocation = await _location.getLocation();
    return _lastKnownLocation;
  }

  // Get last known location without waiting
  LocationData? getLastLocation() {
    return _lastKnownLocation;
  }

  // Continuous location tracking stream
  Stream<LocationData> trackLocation() {
    return _locationStream ?? _location.onLocationChanged;
  }
}