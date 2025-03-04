// lib/services/location_service.dart
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

    // For iOS only: if we only have "when in use" permission, request "always" permission
    if (Platform.isIOS && permission == LocationPermission.whileInUse) {
      // This will prompt for "Always" permission if currently only "When In Use"
      await Geolocator.requestPermission();
    }
  }

  /// Checks if a location accuracy value is valid and not a suspicious default value
  bool _isValidAccuracy(double accuracy) {
    // Filter out the specific 1440m value which seems to be a default
    if (accuracy == 1440.0) return false;

    // iOS-specific checks
    if (Platform.isIOS) {
      // Filter out other common iOS default values
      if (accuracy == 65.0) return false;
      if (accuracy == 100.0) return false;

      // For iOS, be more strict about max permitted values
      if (accuracy > 200.0) return false;
    } else {
      // For Android, filter out abnormally high values
      if (accuracy > 500.0) return false;
    }

    return true;
  }

  Future<Position?> getCurrentLocation() async {
    try {
      // Force iOS to give a fresh location reading
      if (Platform.isIOS) {
        final LocationSettings locationSettings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 0,
          activityType: ActivityType.fitness,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );

        try {
          // Step 1: Flush any cached location by requesting a quick position
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.lowest,
            timeLimit: const Duration(seconds: 1),
          ).catchError((_) {}); // Ignore errors

          // Step 2: Small delay to let iOS reset
          await Future.delayed(const Duration(milliseconds: 500));

          // Step 3: Start a position stream and take multiple readings
          final positions = await Geolocator.getPositionStream(
              locationSettings: locationSettings
          )
              .take(10) // Take up to 10 readings
              .timeout(
            const Duration(seconds: 15),
            onTimeout: (sink) => sink.close(),
          )
              .toList();

          // Step 4: Filter and find the best reading
          if (positions.isNotEmpty) {
            final validPositions = positions
                .where((pos) => _isValidAccuracy(pos.accuracy))
                .toList();

            if (validPositions.isNotEmpty) {
              // Sort by accuracy (lower is better)
              validPositions.sort((a, b) => a.accuracy.compareTo(b.accuracy));
              return validPositions.first;
            }

            // If no valid positions, use the best from all positions
            positions.sort((a, b) => a.accuracy.compareTo(b.accuracy));
            return positions.first;
          }
        } catch (e) {
          print('Error getting streamed position: $e');
        }

        // Step 5: If stream approach failed, try direct position request
        try {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation,
            timeLimit: const Duration(seconds: 20),
          );

          if (_isValidAccuracy(position.accuracy)) {
            return position;
          }
        } catch (e) {
          print('Error getting direct position: $e');
        }
      } else {
        // Android approach (simpler)
        final LocationSettings locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          forceLocationManager: true, // Use GPS directly
          intervalDuration: const Duration(seconds: 1),
        );

        try {
          // Try to get a good reading from a stream first
          final positions = await Geolocator.getPositionStream(
              locationSettings: locationSettings
          )
              .take(5)
              .timeout(
            const Duration(seconds: 10),
            onTimeout: (sink) => sink.close(),
          )
              .toList();

          if (positions.isNotEmpty) {
            positions.sort((a, b) => a.accuracy.compareTo(b.accuracy));
            return positions.first;
          }
        } catch (e) {
          print('Error in Android position stream: $e');
        }

        // Fallback to direct request
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
      }

      // Final fallback if all else fails
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  /// Provides a stream of location updates, filtering out bad readings
  Stream<Position> trackLocation() {
    // Create platform-specific location settings
    LocationSettings locationSettings;

    if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5, // Update every 5 meters
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

    // Return filtered stream - only pass positions with acceptable accuracy
    return Geolocator.getPositionStream(locationSettings: locationSettings)
        .where((position) => _isValidAccuracy(position.accuracy));
  }
}