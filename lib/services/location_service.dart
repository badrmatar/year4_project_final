import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/kalman_filter.dart';

enum LocationQuality { excellent, good, fair, poor, unusable }
enum TrackingMode { standard, battery_saving, high_accuracy }

class LocationService {
  // Singleton pattern for location service
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Stream controllers
  final _locationController = StreamController<Position>.broadcast();
  final _qualityController = StreamController<LocationQuality>.broadcast();
  final _statusController = StreamController<String>.broadcast();

  // Core state variables
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  LocationQuality _currentQuality = LocationQuality.unusable;
  TrackingMode _currentMode = TrackingMode.standard;
  bool _isTracking = false;

  // Accuracy thresholds in meters
  final Map<LocationQuality, double> _accuracyThresholds = {
    LocationQuality.excellent: 10.0, // Less than 10m accuracy
    LocationQuality.good: 20.0,      // 10-20m accuracy
    LocationQuality.fair: 35.0,      // 20-35m accuracy
    LocationQuality.poor: 50.0,      // 35-50m accuracy
    // Anything above 50m is considered unusable
  };

  // Kalman filter for smoother position updates (only used in high accuracy mode)
  KalmanFilter2D? _kalmanFilter;

  // Platform-specific settings
  LocationSettings _getLocationSettings() {
    if (Platform.isIOS) {
      // iOS-specific settings with appropriate activity type
      switch (_currentMode) {
        case TrackingMode.high_accuracy:
          return AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 5,
            activityType: ActivityType.fitness,
            pauseLocationUpdatesAutomatically: false,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          );
        case TrackingMode.battery_saving:
          return AppleSettings(
            accuracy: LocationAccuracy.reduced, // Changed from 'balanced' to 'reduced'
            distanceFilter: 15,
            activityType: ActivityType.fitness,
            pauseLocationUpdatesAutomatically: true,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          );
        case TrackingMode.standard:
        default:
          return AppleSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 10,
            activityType: ActivityType.fitness,
            pauseLocationUpdatesAutomatically: false,
            allowBackgroundLocationUpdates: true,
            showBackgroundLocationIndicator: true,
          );
      }
    } else {
      // Android-specific settings
      switch (_currentMode) {
        case TrackingMode.high_accuracy:
          return AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            forceLocationManager: false,
            intervalDuration: const Duration(seconds: 1),
          );
        case TrackingMode.battery_saving:
          return AndroidSettings(
            accuracy: LocationAccuracy.reduced, // Changed from 'balanced' to 'reduced'
            distanceFilter: 15,
            forceLocationManager: false,
            intervalDuration: const Duration(seconds: 3),
          );
        case TrackingMode.standard:
        default:
          return AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 10,
            forceLocationManager: false,
            intervalDuration: const Duration(seconds: 2),
          );
      }
    }
  }

  // Assess location quality based on accuracy
  LocationQuality _assessLocationQuality(Position position) {
    final accuracy = position.accuracy;

    if (accuracy <= _accuracyThresholds[LocationQuality.excellent]!) {
      return LocationQuality.excellent;
    } else if (accuracy <= _accuracyThresholds[LocationQuality.good]!) {
      return LocationQuality.good;
    } else if (accuracy <= _accuracyThresholds[LocationQuality.fair]!) {
      return LocationQuality.fair;
    } else if (accuracy <= _accuracyThresholds[LocationQuality.poor]!) {
      return LocationQuality.poor;
    } else {
      return LocationQuality.unusable;
    }
  }

  // Get readable description of quality
  String getQualityDescription(LocationQuality quality) {
    switch (quality) {
      case LocationQuality.excellent:
        return 'Excellent GPS signal';
      case LocationQuality.good:
        return 'Good GPS signal';
      case LocationQuality.fair:
        return 'Fair GPS signal';
      case LocationQuality.poor:
        return 'Poor GPS signal';
      case LocationQuality.unusable:
        return 'GPS signal too weak';
    }
  }

  // Get color representation of quality
  Color getQualityColor(LocationQuality quality) {
    switch (quality) {
      case LocationQuality.excellent:
        return Colors.green;
      case LocationQuality.good:
        return Colors.lightGreen;
      case LocationQuality.fair:
        return Colors.orange;
      case LocationQuality.poor:
        return Colors.deepOrange;
      case LocationQuality.unusable:
        return Colors.red;
    }
  }

  // Streams for consumers to listen to
  Stream<Position> get positionStream => _locationController.stream;
  Stream<LocationQuality> get qualityStream => _qualityController.stream;
  Stream<String> get statusStream => _statusController.stream;

  // Current state getters
  LocationQuality get currentQuality => _currentQuality;
  Position? get lastPosition => _lastPosition;
  bool get isTracking => _isTracking;

  // Set tracking mode
  void setTrackingMode(TrackingMode mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      if (_isTracking) {
        // Restart tracking with new mode
        _stopTracking();
        _startTracking();
      }
    }
  }

  // Apply Kalman filter to reduce position jitter (only in high accuracy mode)
  Position _filterPosition(Position position) {
    if (_currentMode != TrackingMode.high_accuracy || _kalmanFilter == null) {
      return position;
    }

    // Update Kalman filter with new measurement
    _kalmanFilter!.predict(0.1); // 100ms prediction step
    _kalmanFilter!.update(position.latitude, position.longitude);

    final smoothedPosition = Position(
      longitude: _kalmanFilter!.x.y,
      latitude: _kalmanFilter!.x.x,
      timestamp: position.timestamp,
      accuracy: position.accuracy,
      altitude: position.altitude,
      altitudeAccuracy: position.altitudeAccuracy,
      heading: position.heading,
      headingAccuracy: position.headingAccuracy,
      speed: position.speed,
      speedAccuracy: position.speedAccuracy,
    );

    return smoothedPosition;
  }

  // Start location tracking
  void _startTracking() {
    if (_isTracking) return;

    final locationSettings = _getLocationSettings();

    _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings
    ).listen((Position position) {
      // Assess location quality
      final quality = _assessLocationQuality(position);

      // Only update position if quality is acceptable
      if (quality != LocationQuality.unusable) {
        // Apply filtering for smoother paths
        final filteredPosition = _filterPosition(position);
        _lastPosition = filteredPosition;
        _locationController.add(filteredPosition);
      }

      // Always update quality
      if (quality != _currentQuality) {
        _currentQuality = quality;
        _qualityController.add(quality);
        _statusController.add(getQualityDescription(quality));
      }
    });

    _isTracking = true;
  }

  // Stop location tracking
  void _stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
  }

  // Check permission and start monitoring GPS quality
  Future<void> startQualityMonitoring() async {
    if (_isTracking) return;

    await _checkAndRequestPermission();
    _startTracking();
  }

  // Stop quality monitoring
  void stopQualityMonitoring() {
    _stopTracking();
  }

  // Initialize Kalman filter with current position
  void initializeKalmanFilter(Position position) {
    _kalmanFilter = KalmanFilter2D(
      initialX: position.latitude,
      initialY: position.longitude,
      // Default values are fine for most cases, but could be tuned
      processNoise: 1e-5,      // Lower for smoother but less responsive tracking
      measurementNoise: 15.0,   // Based on typical GPS accuracy in meters
    );
  }

  // Check if location accuracy is good enough to start a run
  Future<bool> isAccuracyGoodForRun() async {
    if (_currentQuality == LocationQuality.unusable ||
        _currentQuality == LocationQuality.poor) {
      return false;
    }
    return true;
  }

  // Wait for a good accuracy fix before starting a run
  Future<bool> waitForGoodAccuracy({
    required Duration timeout,
    required Function(int, LocationQuality) onProgress
  }) async {
    if (!_isTracking) {
      await startQualityMonitoring();
    }

    // If we already have good accuracy, return immediately
    if (_currentQuality == LocationQuality.good ||
        _currentQuality == LocationQuality.excellent) {
      return true;
    }

    // Create a completer to wait for good accuracy
    final completer = Completer<bool>();

    // Set timeout
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });

    // Counter for progress updates
    int secondsElapsed = 0;
    final progressTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      secondsElapsed++;
      onProgress(secondsElapsed, _currentQuality);
    });

    // Listen for quality updates
    final subscription = _qualityController.stream.listen((quality) {
      if (quality == LocationQuality.good || quality == LocationQuality.excellent) {
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      }
    });

    // Wait for result
    final result = await completer.future;

    // Clean up
    timer.cancel();
    progressTimer.cancel();
    subscription.cancel();

    return result;
  }

  // Check and request location permission
  Future<bool> _checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _statusController.add('Location services are disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _statusController.add('Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _statusController.add('Location permissions are permanently denied');
      return false;
    }

    return true;
  }

  // Get a single location update with the best possible accuracy
  Future<Position?> getCurrentLocation() async {
    try {
      final hasPermission = await _checkAndRequestPermission();
      if (!hasPermission) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (e) {
      _statusController.add('Error getting location: $e');
      return null;
    }
  }

  // For compatibility with your original trackLocation() method
  Stream<Position> trackLocation() {
    if (!_isTracking) {
      startQualityMonitoring();
    }
    return positionStream;
  }

  // Clean up resources
  void dispose() {
    _stopTracking();
    _locationController.close();
    _qualityController.close();
    _statusController.close();
  }
}