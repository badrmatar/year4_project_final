// lib/services/location_service.dart
import 'dart:io';
import 'package:geolocator/geolocator.dart';

class LocationService {
  LocationService() {
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    // Check and request location permissions if necessary.
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // For iOS only: if we only have "when in use" permission, request "always" permission
    if (Platform.isIOS && permission == LocationPermission.whileInUse) {
      // This will prompt for "Always" permission if currently only "When In Use"
      await Geolocator.requestPermission();
    }
  }

  // lib/services/location_service.dart (partial update)
  Future<Position?> getCurrentLocation() async {
    try {
      // First check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        return null;
      }

      // On iOS, we need to handle authorization status more carefully
      LocationPermission permission = await Geolocator.checkPermission();
      print('Current location permission status: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        print('After request, permission status: $permission');

        if (permission == LocationPermission.denied) {
          print('Location permission denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permissions permanently denied');
        return null;
      }

      // When targeting iOS, use a longer timeout for initial position acquisition
      if (Platform.isIOS) {
        try {
          return await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: const Duration(seconds: 15),
          );
        } catch (timeoutError) {
          print('Timeout getting precise location, falling back to last known position');
          // Fall back to last known position if getCurrentPosition times out
          return await Geolocator.getLastKnownPosition();
        }
      } else {
        // Android path
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      }
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

// Modify the tracking method too
  Stream<Position> trackLocation() {
    var locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Update more frequently on iOS
    );

    // iOS-specific settings
    if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}