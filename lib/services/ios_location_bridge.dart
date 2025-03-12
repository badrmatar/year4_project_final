import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// A bridge class to communicate with native iOS code for background location tracking
class IOSLocationBridge {
  static final IOSLocationBridge _instance = IOSLocationBridge._internal();

  factory IOSLocationBridge() => _instance;

  IOSLocationBridge._internal();

  // Method channel for communicating with native iOS code
  final MethodChannel _channel = const MethodChannel('com.duorun.location/background');

  // Stream controller for broadcasting location updates from native code
  final _locationController = StreamController<Position>.broadcast();

  // Stream controller for broadcasting errors
  final _errorController = StreamController<String>.broadcast();

  // Stream controller for authorization status changes
  final _authStatusController = StreamController<String>.broadcast();

  // Public streams
  Stream<Position> get locationStream => _locationController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<String> get authStatusStream => _authStatusController.stream;

  // Flag to track if bridge is initialized
  bool _isInitialized = false;

  // Initialize the bridge and set up method call handler
  Future<void> initialize() async {
    if (!Platform.isIOS || _isInitialized) return;

    _isInitialized = true;

    // Set up method call handler for incoming calls from native code
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'locationUpdate':
          final args = call.arguments as Map<dynamic, dynamic>;
          final position = Position(
            latitude: args['latitude'],
            longitude: args['longitude'],
            timestamp: DateTime.fromMillisecondsSinceEpoch(args['timestamp'].toInt()),
            accuracy: args['accuracy'],
            altitude: args['altitude'],
            heading: 0.0,
            speed: args['speed'],
            speedAccuracy: args['speedAccuracy'],
            floor: null,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          );
          _locationController.add(position);
          break;
        case 'locationError':
          final args = call.arguments as Map<dynamic, dynamic>;
          _errorController.add(args['message']);
          break;
        case 'authorizationStatus':
          final args = call.arguments as Map<dynamic, dynamic>;
          _authStatusController.add(args['status']);
          break;
      }
    });
  }

  // Start background location updates on iOS
  Future<bool> startBackgroundLocationUpdates() async {
    if (!Platform.isIOS) return false;

    try {
      final result = await _channel.invokeMethod('startBackgroundLocationUpdates');
      return result == true;
    } on PlatformException catch (e) {
      _errorController.add('Error starting background location: ${e.message}');
      return false;
    }
  }

  // Stop background location updates on iOS
  Future<bool> stopBackgroundLocationUpdates() async {
    if (!Platform.isIOS) return false;

    try {
      final result = await _channel.invokeMethod('stopBackgroundLocationUpdates');
      return result == true;
    } on PlatformException catch (e) {
      _errorController.add('Error stopping background location: ${e.message}');
      return false;
    }
  }

  // Check authorization status for location services
  Future<String> checkAuthorizationStatus() async {
    if (!Platform.isIOS) return 'notSupported';

    try {
      final result = await _channel.invokeMethod('checkAuthorizationStatus');
      return result as String;
    } on PlatformException catch (e) {
      _errorController.add('Error checking authorization: ${e.message}');
      return 'error';
    }
  }

  // Dispose resources
  void dispose() {
    if (Platform.isIOS) {
      stopBackgroundLocationUpdates();
    }

    _locationController.close();
    _errorController.close();
    _authStatusController.close();
  }
}