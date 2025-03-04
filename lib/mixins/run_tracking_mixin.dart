// run_tracking_mixin.dart

import 'dart:async';
import 'dart:math';
import 'dart:io'; // Add import for Platform
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import '../services/location_service.dart';

mixin RunTrackingMixin<T extends StatefulWidget> on State<T> {
  // Variables common to both pages:
  final LocationService locationService = LocationService();
  Position? currentLocation;
  Position? startLocation;
  Position? endLocation;
  double distanceCovered = 0.0;
  int secondsElapsed = 0;
  Timer? runTimer;
  bool isTracking = false;
  bool autoPaused = false;
  StreamSubscription<Position>? locationSubscription;
  Timer? _locationQualityCheckTimer; // Add timer for monitoring location quality

  // For mapping route points
  final List<LatLng> routePoints = [];
  Polyline routePolyline = const Polyline(
    polylineId: PolylineId('route'),
    color: Colors.orange,
    width: 5,
    points: [],
  );
  GoogleMapController? mapController;

  // Variables for auto-pause
  int stillCounter = 0;
  final double pauseThreshold = 0.5;
  final double resumeThreshold = 1.0;
  LatLng? lastRecordedLocation;

  // Variables for location quality monitoring
  int _poorQualityReadingsCount = 0;
  Position? _lastGoodPosition;
  final int _maxPoorReadings = 5; // How many poor readings before taking action

  // Strict accuracy threshold - iOS is particularly problematic
  final double _goodAccuracyThreshold = 30.0; // Good accuracy
  final double _acceptableAccuracyThreshold = 50.0; // Acceptable accuracy

  /// Start run: initialize all variables and start timers & location tracking.
  void startRun(Position initialPosition) {
    setState(() {
      startLocation = initialPosition;
      currentLocation = initialPosition; // Set initial current location
      _lastGoodPosition = initialPosition; // Save as last known good position
      isTracking = true;
      distanceCovered = 0.0;
      secondsElapsed = 0;
      autoPaused = false;
      routePoints.clear();
      _poorQualityReadingsCount = 0;

      final startPoint = LatLng(initialPosition.latitude, initialPosition.longitude);
      routePoints.add(startPoint);
      routePolyline = routePolyline.copyWith(pointsParam: routePoints);
      lastRecordedLocation = startPoint;
    });

    // Start a timer to count seconds
    runTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!autoPaused && mounted) {
        setState(() => secondsElapsed++);
      }
    });

    // Start a timer to periodically check location quality
    _startLocationQualityMonitoring();

    // Subscribe to location updates with the proper settings for continuous tracking
    _startContinuousLocationTracking();
  }

  /// Start a periodic check of location quality
  void _startLocationQualityMonitoring() {
    _locationQualityCheckTimer?.cancel();
    _locationQualityCheckTimer = Timer.periodic(
        const Duration(seconds: 30), // Check every 30 seconds
            (_) => _checkLocationQuality()
    );
  }

  /// Force a refresh of location services if quality degrades
  void _checkLocationQuality() {
    if (!isTracking || currentLocation == null) return;

    // If we've had too many poor quality readings in a row, try to refresh
    if (_poorQualityReadingsCount >= _maxPoorReadings) {
      print('Location quality degraded - forcing refresh');

      // Restart location tracking
      _restartLocationTracking();

      // Reset counter
      _poorQualityReadingsCount = 0;
    }
  }

  /// Restart location tracking with fresh settings
  void _restartLocationTracking() {
    // Cancel existing subscription
    locationSubscription?.cancel();

    // Brief pause to let system reset
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && isTracking) {
        _startContinuousLocationTracking();
      }
    });
  }

  /// Start continuous tracking with optimal settings
  void _startContinuousLocationTracking() {
    final LocationSettings locationSettings = Platform.isIOS
        ? AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
      activityType: ActivityType.fitness,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    )
        : AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      forceLocationManager: true, // Use GPS directly for more consistent results
    );

    // Subscribe to location updates
    locationSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings
    ).listen((position) {
      if (!isTracking) return;

      // Check location quality
      bool isGoodQuality = _isGoodQualityReading(position);

      if (isGoodQuality) {
        // Reset poor readings counter
        _poorQualityReadingsCount = 0;

        // Save this as last good position
        _lastGoodPosition = position;

        // Update auto-pause logic
        final speed = position.speed.clamp(0.0, double.infinity);
        _handleAutoPauseLogic(speed);

        // Calculate distance if not auto-paused
        if (lastRecordedLocation != null && !autoPaused) {
          final newDistance = calculateDistance(
            lastRecordedLocation!.latitude,
            lastRecordedLocation!.longitude,
            position.latitude,
            position.longitude,
          );
          if (newDistance > 5.0) {  // Only count movements greater than 5m to filter noise
            setState(() {
              distanceCovered += newDistance;
              lastRecordedLocation = LatLng(position.latitude, position.longitude);
            });
          }
        }

        // Update route points and current location
        setState(() {
          currentLocation = position;
          final newPoint = LatLng(position.latitude, position.longitude);
          routePoints.add(newPoint);
          routePolyline = routePolyline.copyWith(pointsParam: routePoints);
        });

        // Optionally animate the map camera
        mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
        );
      } else {
        // Increment poor quality counter
        _poorQualityReadingsCount++;

        print('Poor quality GPS reading: ${position.accuracy}m (${_poorQualityReadingsCount}/$_maxPoorReadings)');

        // If we have a good previous position, keep using it instead
        if (_lastGoodPosition != null && _poorQualityReadingsCount < _maxPoorReadings * 2) {
          // Just update the position display but don't add to route or distance
          setState(() {
            currentLocation = position; // Show current position for transparency
          });
        }
      }
    }, onError: (error) {
      print('Error in location tracking: $error');

      // On error, increment poor readings counter
      _poorQualityReadingsCount++;

      // If too many errors, try to restart
      if (_poorQualityReadingsCount >= _maxPoorReadings) {
        _restartLocationTracking();
        _poorQualityReadingsCount = 0;
      }
    });
  }

  /// Check if a location reading is of good quality
  bool _isGoodQualityReading(Position position) {
    // For iOS, be stricter about what constitutes a good reading
    if (Platform.isIOS) {
      // Filter out common iOS default values
      if (position.accuracy == 1440.0) return false;
      if (position.accuracy == 65.0) return false;
      if (position.accuracy >= 100.0) return false;

      // Additional validation for iOS
      if (position.speed < 0) return false; // Invalid speed

      // Basic sanity check - if position jumps too far too quickly, it's likely bad
      if (_lastGoodPosition != null) {
        final double jumpDistance = Geolocator.distanceBetween(
            _lastGoodPosition!.latitude,
            _lastGoodPosition!.longitude,
            position.latitude,
            position.longitude
        );

        // If we suddenly jump more than 300m in a single update, it's suspicious
        // (humans don't teleport)
        if (jumpDistance > 300 && position.speed < 20) {
          print('Detected position jump of ${jumpDistance.round()}m - ignoring');
          return false;
        }
      }
    }

    // General quality check for all platforms
    return position.accuracy <= _acceptableAccuracyThreshold;
  }

  /// Stop the run and cancel timers/subscriptions.
  void endRun() {
    runTimer?.cancel();
    locationSubscription?.cancel();
    _locationQualityCheckTimer?.cancel();
    isTracking = false;
    endLocation = currentLocation;
  }

  /// Calculate distance using the haversine formula.
  double calculateDistance(double startLat, double startLng, double endLat, double endLng) {
    const double earthRadius = 6371000.0;
    final dLat = (endLat - startLat) * (pi / 180);
    final dLng = (endLng - startLng) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(startLat * (pi / 180)) * cos(endLat * (pi / 180)) *
            sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  /// Auto-pause logic: updates the [autoPaused] flag based on speed.
  void _handleAutoPauseLogic(double speed) {
    if (autoPaused) {
      if (speed > resumeThreshold) {
        setState(() {
          autoPaused = false;
          stillCounter = 0;
        });
      }
    } else {
      if (speed < pauseThreshold) {
        stillCounter++;
        if (stillCounter >= 5) {
          setState(() => autoPaused = true);
        }
      } else {
        stillCounter = 0;
      }
    }
  }

  /// Dispose resources
  @override
  void dispose() {
    runTimer?.cancel();
    locationSubscription?.cancel();
    _locationQualityCheckTimer?.cancel();
    super.dispose();
  }
}