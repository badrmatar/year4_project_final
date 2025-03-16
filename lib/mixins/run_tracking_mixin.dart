import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import '../services/location_service.dart';

mixin RunTrackingMixin<T extends StatefulWidget> on State<T> {
  // Common variables:
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

  // Mapping route points:
  final List<LatLng> routePoints = [];
  Polyline routePolyline = const Polyline(
    polylineId: PolylineId('route'),
    color: Colors.orange,
    width: 5,
    points: [],
  );
  GoogleMapController? mapController;

  // Auto-pause variables:
  int stillCounter = 0;
  final double pauseThreshold = 0.5;
  final double resumeThreshold = 1.0;
  LatLng? lastRecordedLocation;

  /// Start run: initialize all variables and start tracking.
  void startRun(Position initialPosition) {
    setState(() {
      startLocation = initialPosition;
      isTracking = true;
      distanceCovered = 0.0;
      secondsElapsed = 0;
      autoPaused = false;
      routePoints.clear();

      final startPoint = LatLng(initialPosition.latitude, initialPosition.longitude);
      routePoints.add(startPoint);
      routePolyline = routePolyline.copyWith(pointsParam: routePoints);
      lastRecordedLocation = startPoint;
    });

    // Start timer for elapsed time.
    runTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!autoPaused && mounted) {
        setState(() => secondsElapsed++);
      }
    });

    // Subscribe to location updates.
    locationSubscription = locationService.trackLocation().listen((position) {
      if (!isTracking) return;

      // Update auto-pause logic.
      final speed = position.speed.clamp(0.0, double.infinity);
      _handleAutoPauseLogic(speed);

      // Calculate distance if not auto-paused.
      if (lastRecordedLocation != null && !autoPaused) {
        final newDistance = calculateDistance(
          lastRecordedLocation!.latitude,
          lastRecordedLocation!.longitude,
          position.latitude,
          position.longitude,
        );
        if (newDistance > 15.0) {
          setState(() {
            distanceCovered += newDistance;
            lastRecordedLocation = LatLng(position.latitude, position.longitude);
          });
        }
      }

      // Update route points and current location.
      setState(() {
        currentLocation = position;
        final newPoint = LatLng(position.latitude, position.longitude);
        routePoints.add(newPoint);
        routePolyline = routePolyline.copyWith(pointsParam: routePoints);
      });

      // Optionally animate the map camera.
      mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
    });
  }

  /// Stop the run.
  void endRun() {
    runTimer?.cancel();
    locationSubscription?.cancel();
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

  /// Auto-pause logic based on speed.
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

  @override
  void dispose() {
    runTimer?.cancel();
    locationSubscription?.cancel();
    super.dispose();
  }
}
