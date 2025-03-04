// lib/pages/active_run_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../models/user.dart';
import '../mixins/run_tracking_mixin.dart';
import '../widgets/run_metrics_card.dart';

class ActiveRunPage extends StatefulWidget {
  final String journeyType;
  final int challengeId;

  const ActiveRunPage({
    Key? key,
    required this.journeyType,
    required this.challengeId,
  }) : super(key: key);

  @override
  ActiveRunPageState createState() => ActiveRunPageState();
}

class ActiveRunPageState extends State<ActiveRunPage> with RunTrackingMixin {
  // --- Configuration thresholds ---
  final double _targetAccuracy = 35.0; // We require accuracy under 35m
  final Duration _minWaitingDuration = const Duration(seconds: 3);
  final Duration _fallbackDuration = const Duration(seconds: 30);

  // --- State variables for waiting ---
  bool _hasGoodFix = false;
  bool _isWaiting = true;
  DateTime _waitingStartTime = DateTime.now();
  StreamSubscription<Position>? _fixSubscription;
  String _loadingDebug = "Initializing GPS...";

  @override
  void initState() {
    super.initState();
    // Reset state for a new run.
    resetRunState();
    // Begin waiting for a fresh fix.
    _startWaitingForFix();
    // Fallback: If no acceptable fix is obtained within fallback time, use the latest reading.
    Timer(_fallbackDuration, () {
      if (!_hasGoodFix && currentLocation != null) {
        _fixSubscription?.cancel();
        _hasGoodFix = true;
        startRun(currentLocation!);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Fallback: Run started with accuracy: ${currentLocation!.accuracy.toStringAsFixed(1)}m'),
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() {
          _isWaiting = false;
        });
      }
    });
  }

  /// Reset all state variables so that a new run starts fresh.
  void resetRunState() {
    setState(() {
      _isWaiting = true;
      _hasGoodFix = false;
      _waitingStartTime = DateTime.now();
      currentLocation = null;
      // Also clear routePoints and reset elapsed time.
      routePoints.clear();
      routePolyline = routePolyline.copyWith(pointsParam: routePoints);
      secondsElapsed = 0;
      distanceCovered = 0.0;
    });
  }

  /// Subscribes to the location stream and waits until a fresh reading is acquired.
  void _startWaitingForFix() {
    _fixSubscription = locationService.trackLocation().listen((position) {
      // Only consider readings acquired after waiting started.
      if (position.timestamp == null || !position.timestamp!.isAfter(_waitingStartTime)) {
        return;
      }
      // Update current location and debug message.
      setState(() {
        currentLocation = position;
        _loadingDebug = "Current Accuracy: ${position.accuracy.toStringAsFixed(1)}m";
      });
      final elapsed = DateTime.now().difference(_waitingStartTime);
      // When at least 3 seconds have elapsed and accuracy is good enough, accept the fix.
      if (elapsed >= _minWaitingDuration && position.accuracy < _targetAccuracy) {
        _fixSubscription?.cancel();
        _hasGoodFix = true;
        startRun(position);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Run started with accuracy: ${position.accuracy.toStringAsFixed(1)}m'),
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() {
          _isWaiting = false;
        });
      }
    }, onError: (error) {
      setState(() {
        _loadingDebug = "Error: $error";
      });
    });
  }

  /// Called when the user taps "End Run".
  void _endRunAndSave() {
    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot end run without a valid location')),
      );
      return;
    }
    endRun();
    _saveRunData();
    // Reset state for the next run.
    resetRunState();
  }

  Future<void> _saveRunData() async {
    final user = Provider.of<UserModel>(context, listen: false);
    if (user.id == 0 || startLocation == null || endLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing required data to save run")),
      );
      return;
    }
    final distance = double.parse(distanceCovered.toStringAsFixed(2));
    final startTime =
    (startLocation!.timestamp ?? DateTime.now()).toUtc().toIso8601String();
    final endTime =
    (endLocation!.timestamp ?? DateTime.now()).toUtc().toIso8601String();
    final routeJson = routePoints
        .map((point) => {'latitude': point.latitude, 'longitude': point.longitude})
        .toList();

    final requestBody = {
      'user_id': user.id,
      'start_time': startTime,
      'end_time': endTime,
      'start_latitude': startLocation!.latitude,
      'start_longitude': startLocation!.longitude,
      'end_latitude': endLocation!.latitude,
      'end_longitude': endLocation!.longitude,
      'distance_covered': distance,
      'route': routeJson,
      'journey_type': widget.journeyType,
    };

    try {
      final response = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/create_user_contribution'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: jsonEncode(requestBody),
      );
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Run saved successfully!')),
        );
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.pushReplacementNamed(context, '/challenges');
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save run: ${response.body}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("An error occurred: ${e.toString()}")),
      );
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _fixSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // While waiting for a good fix, show the loading page.
    if (_isWaiting) {
      return Scaffold(
        appBar: AppBar(title: const Text('Waiting for GPS Fix')),
        body: Container(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.green),
                const SizedBox(height: 20),
                Text(
                  _loadingDebug,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 10),
                if (currentLocation != null)
                  Text(
                    'Lat: ${currentLocation!.latitude.toStringAsFixed(6)}\nLng: ${currentLocation!.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Once a good fix is obtained, show the main map page.
    final distanceKm = distanceCovered / 1000;
    return Scaffold(
      appBar: AppBar(title: const Text('Active Run')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: currentLocation != null
                  ? LatLng(currentLocation!.latitude, currentLocation!.longitude)
                  : const LatLng(37.4219999, -122.0840575),
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            polylines: {routePolyline},
            onMapCreated: (controller) => mapController = controller,
          ),
          Positioned(
            top: 20,
            left: 20,
            child: RunMetricsCard(
              time: _formatTime(secondsElapsed),
              distance: '${(distanceKm).toStringAsFixed(2)} km',
            ),
          ),
          if (autoPaused)
            const Positioned(
              top: 90,
              left: 20,
              child: Card(
                color: Colors.redAccent,
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'Auto-Paused',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: ElevatedButton(
        onPressed: _endRunAndSave,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        child: const Text(
          'End Run',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
