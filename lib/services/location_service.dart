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

  Future<Position?> getCurrentLocation() async {
    try {
      // Use platform-specific settings if needed
      var locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
      );

      // iOS-specific settings to handle background tracking
      if (Platform.isIOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.fitness,
          showBackgroundLocationIndicator: true,
        );
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
    } catch (e) {
      return null;
    }
  }

  // Continuous location tracking stream.
  Stream<Position> trackLocation() {
    var locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
    );

    // iOS-specific settings
    if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        activityType: ActivityType.fitness,
        showBackgroundLocationIndicator: true,
      );
    }

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}