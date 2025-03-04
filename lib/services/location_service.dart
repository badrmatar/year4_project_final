import 'dart:async';
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
    // For iOS, if we only have "while in use" permission, request additional permission if needed.
    if (Platform.isIOS && permission == LocationPermission.whileInUse) {
      await Geolocator.requestPermission();
    }
  }

  /// Returns the current location.
  Future<Position?> getCurrentLocation() async {
    try {
      // Use the same call for both iOS and Android.
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  /// Provides a stream of location updates.
  Stream<Position> trackLocation() {
    LocationSettings locationSettings;
    if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 1),
      );
    }
    return Geolocator.getPositionStream(locationSettings: locationSettings)
        .where((position) => position.accuracy > 0);
  }
}
