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
  TrackingMode _currentMode = TrackingMode.high_accuracy; // Default to high accuracy
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

  // Auto-pause variables
  int stillCounter = 0;
  final double pauseThreshold = 0.5;
  final double resumeThreshold = 1.0;

  // Platform-specific settings
  LocationSettings _getLocationSettings() {
    // Use higher accuracy settings regardless of platform
    // to ensure we get the best possible updates
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 15,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 1),
      );
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
      // If already tracking, restart with new mode
      if (_isTracking) {
        _stopTracking();
        _startTracking();
      }
    }
  }

  // Apply Kalman filter to reduce position jitter
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

    print('LocationService: Starting position tracking with ${_currentMode.toString()}');

    _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings
    ).listen((Position position) {
      // Process all positions, but let consumers decide quality threshold
      final quality = _assessLocationQuality(position);

      // Apply filtering for smoother paths
      final filteredPosition = _filterPosition(position);
      _lastPosition = filteredPosition;

      // Broadcast to all listeners
      _locationController.add(filteredPosition);

      // Update quality if changed
      if (quality != _currentQuality) {
        _currentQuality = quality;
        _qualityController.add(quality);
        _statusController.add(getQualityDescription(quality));

        print('LocationService: Quality changed to ${quality.toString()} with accuracy ${position.accuracy}m');
      }
    },
        onError: (error) {
          print('LocationService error: $error');
          _statusController.add('Location error: $error');
        });

    _isTracking = true;
  }

  // Stop location tracking
  void _stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
    print('LocationService: Stopped position tracking');
  }

  // Check permission and start monitoring GPS quality
  Future<void> startQualityMonitoring() async {
    if (_isTracking) {
      print('LocationService: Already tracking, not restarting');
      return;
    }

    final hasPermission = await _checkAndRequestPermission();
    if (hasPermission) {
      _startTracking();
    } else {
      _statusController.add('Location permission denied');
    }
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
      // Lower process noise for smoother tracking
      processNoise: 1e-5,
      // Set based on typical GPS accuracy
      measurementNoise: 15.0,
    );
    print('LocationService: Initialized Kalman filter with starting position');
  }

  // Check if location accuracy is good enough to start a run
  Future<bool> isAccuracyGoodForRun() async {
    if (_currentQuality == LocationQuality.unusable ||
        _currentQuality == LocationQuality.poor) {
      return false;
    }
    return true;
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

      print('LocationService: Getting current location...');

      // Request position with highest accuracy and a reasonable timeout
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 15),
      );

      print('LocationService: Got position with accuracy ${position.accuracy}m');

      // Update last position and quality
      _lastPosition = position;
      _currentQuality = _assessLocationQuality(position);

      // Send an initial update to streams
      _locationController.add(position);
      _qualityController.add(_currentQuality);

      return position;
    } catch (e) {
      print('LocationService: Error getting current location: $e');
      _statusController.add('Error getting location: $e');
      return null;
    }
  }

  // Actively get a fresh GPS fix - used for frequent polling
  Future<Position?> refreshCurrentLocation() async {
    try {
      // Request position with highest accuracy but shorter timeout
      // to avoid blocking UI for too long
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 5),
      );

      print('LocationService: Refreshed position with accuracy ${position.accuracy}m');

      // Update last position and quality
      _lastPosition = position;
      _currentQuality = _assessLocationQuality(position);

      // Send updates to streams
      _locationController.add(position);
      _qualityController.add(_currentQuality);

      return position;
    } catch (e) {
      // Less intrusive error logging for refresh attempts
      print('LocationService: Refresh location attempt: $e');
      return null;
    }
  }

  // For compatibility with original trackLocation() method
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
    print('LocationService: Disposed');
  }
}