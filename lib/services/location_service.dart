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
  // In your LocationService class
  Future<Position?> getCurrentLocation() async {
    try {
      // For iOS, use specific iOS settings to force high accuracy
      if (Platform.isIOS) {
        final LocationSettings locationSettings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation, // Force highest accuracy
          activityType: ActivityType.fitness,
          distanceFilter: 5,
          pauseLocationUpdatesAutomatically: false,
          // Request these to improve accuracy
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );

        // Use continuous position stream to force GPS activation
        final positionStream = Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).timeout(
          const Duration(seconds: 15),
          onTimeout: (sink) => sink.close(),
        );

        // Take the first position with reasonable accuracy
        try {
          final positions = await positionStream.take(10).toList();

          // Find the position with best accuracy
          if (positions.isNotEmpty) {
            positions.sort((a, b) => a.accuracy.compareTo(b.accuracy));
            return positions.first; // Return most accurate position
          }
        } catch (e) {
          print('Error in position stream: $e');
        }

        // Fall back to direct position request
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 20),
        );
      } else {
        // Android path - unchanged
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