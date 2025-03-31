import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

class IOSLocationBridge {
  static final IOSLocationBridge _instance = IOSLocationBridge._internal();

  factory IOSLocationBridge() => _instance;

  IOSLocationBridge._internal();

  final MethodChannel _channel = const MethodChannel('com.duorun.location/background');

  final _locationController = StreamController<Position>.broadcast();

  final _errorController = StreamController<String>.broadcast();

  final _authStatusController = StreamController<String>.broadcast();

  Stream<Position> get locationStream => _locationController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<String> get authStatusStream => _authStatusController.stream;

  //check bridge
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (!Platform.isIOS || _isInitialized) return;

    _isInitialized = true;
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

  void dispose() {
    if (Platform.isIOS) {
      stopBackgroundLocationUpdates();
    }

    _locationController.close();
    _errorController.close();
    _authStatusController.close();
  }
}