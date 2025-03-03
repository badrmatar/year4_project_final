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
      // Make sure location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null; // Location services not enabled
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null; // Permissions not granted
      }

      // iOS-specific settings
      if (Platform.isIOS) {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 10),
        );
      } else {
        // Android path
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
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