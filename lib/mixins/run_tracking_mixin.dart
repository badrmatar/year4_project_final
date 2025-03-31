import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import '../services/location_service.dart';

mixin RunTrackingMixin<T extends StatefulWidget> on State<T> {

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

  final List<LatLng> routePoints = [];
  Polyline routePolyline = const Polyline(
    polylineId: PolylineId('route'),
    color: Colors.orange,
    width: 5,
    points: [],
  );
  GoogleMapController? mapController;

  int stillCounter = 0;
  final double pauseThreshold = 0.5;
  final double resumeThreshold = 1.0;
  LatLng? lastRecordedLocation;

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

    runTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!autoPaused && mounted) {
        setState(() => secondsElapsed++);
      }
    });

    locationSubscription = locationService.trackLocation().listen((position) {
      if (!isTracking) return;

      final speed = position.speed.clamp(0.0, double.infinity);
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
      setState(() {
        currentLocation = position;
        final newPoint = LatLng(position.latitude, position.longitude);
        routePoints.add(newPoint);
        routePolyline = routePolyline.copyWith(pointsParam: routePoints);
      });

      mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );
    });
  }
  
  void endRun() {
    runTimer?.cancel();
    locationSubscription?.cancel();
    isTracking = false;
    endLocation = currentLocation;
  }

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

  @override
  void dispose() {
    runTimer?.cancel();
    locationSubscription?.cancel();
    super.dispose();
  }
}
