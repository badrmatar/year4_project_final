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

  /// Checks if a location accuracy value is valid and not the suspicious 1440m default
  bool _isValidAccuracy(double accuracy) {
    // Filter out the specific 1440m value which seems to be a default
    if (accuracy == 1440.0) return false;

    // Also filter out any abnormally high values
    if (accuracy > 100.0 && !Platform.isIOS) return false;
    if (accuracy > 200.0 && Platform.isIOS) return false;

    return true;
  }

  Future<Position?> getCurrentLocation() async {
    try {
      // For iOS, use specific iOS settings to force high accuracy
      if (Platform.isIOS) {
        final LocationSettings locationSettings = AppleSettings(
          accuracy: LocationAccuracy.bestForNavigation, // Force highest accuracy
          activityType: ActivityType.fitness,
          distanceFilter: 0, // Update with any distance change
          pauseLocationUpdatesAutomatically: false,
          // Request these to improve accuracy
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );

        // Use continuous position stream with sampling to get best accuracy
        try {
          final positionStream = Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: (sink) => sink.close(),
          );

          final positions = await positionStream.take(8).toList();

          // Filter out invalid accuracy values and sort by accuracy (lower is better)
          final validPositions = positions
              .where((pos) => _isValidAccuracy(pos.accuracy))
              .toList();

          if (validPositions.isNotEmpty) {
            validPositions.sort((a, b) => a.accuracy.compareTo(b.accuracy));
            return validPositions.first; // Return most accurate position
          }

          // If no valid positions found, try with all positions
          if (positions.isNotEmpty) {
            positions.sort((a, b) => a.accuracy.compareTo(b.accuracy));
            return positions.first;
          }
        } catch (e) {
          print('Error in position stream: $e');
        }

        // Fall back to direct position request
        final Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 20),
        );

        // Check if the position has the suspicious 1440m accuracy
        if (_isValidAccuracy(position.accuracy)) {
          return position;
        } else {
          // If we got the suspicious value, try one more time with a delay
          await Future.delayed(const Duration(seconds: 2));
          return await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: const Duration(seconds: 10),
          );
        }
      } else {
        // Android path - use similar sampling approach for consistency
        final LocationSettings locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          forceLocationManager: false, // true = GPS only, false = fused provider
          intervalDuration: const Duration(seconds: 1),
        );

        try {
          final positionStream = Geolocator.getPositionStream(
            locationSettings: locationSettings,
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: (sink) => sink.close(),
          );

          final positions = await positionStream.take(5).toList();

          // Filter out invalid accuracy values
          final validPositions = positions
              .where((pos) => _isValidAccuracy(pos.accuracy))
              .toList();

          if (validPositions.isNotEmpty) {
            validPositions.sort((a, b) => a.accuracy.compareTo(b.accuracy));
            return validPositions.first;
          }

          if (positions.isNotEmpty) {
            positions.sort((a, b) => a.accuracy.compareTo(b.accuracy));
            return positions.first;
          }
        } catch (e) {
          print('Error in Android position stream: $e');
        }

        // Fall back to direct position request
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
      }
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }

  // Modified tracking method for better continuous updates
  Stream<Position> trackLocation() {
    var locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Update every 5 meters
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
    } else {
      // Android specific settings
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 1),
      );
    }

    return Geolocator.getPositionStream(locationSettings: locationSettings)
        .where((position) => _isValidAccuracy(position.accuracy)); // Filter out suspicious values
  }
}