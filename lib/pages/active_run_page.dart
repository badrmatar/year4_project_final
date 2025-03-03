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
import 'dart:async'; // Provides Timer, Future, etc.
import 'dart:convert'; // Provides jsonEncode, jsonDecode, etc.

import '../models/user.dart';
import '../mixins/run_tracking_mixin.dart';
import '../widgets/run_metrics_card.dart'; // Import the reusable metrics card widget

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
  @override
  void initState() {
    super.initState();

    // Request an initial location but only start the run when accuracy is good
    locationService.getCurrentLocation().then((position) {
      if (position != null && mounted) {
        setState(() {
          currentLocation = position;
        });

        // Only start the run if accuracy is below 30 meters
        if (position.accuracy < 30) {
          startRun(position);
        } else {
          // Show message that we're waiting for better GPS accuracy
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Waiting for better GPS accuracy...'),
              duration: Duration(seconds: 3),
            ),
          );

          // Keep checking for better accuracy
          _waitForBetterAccuracy();
        }
      }
    });
  }

// Helper method to wait for better accuracy
  void _waitForBetterAccuracy() {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final newPosition = await locationService.getCurrentLocation();
      if (newPosition != null && mounted) {
        setState(() {
          currentLocation = newPosition;
        });

        // Start the run once we have good accuracy
        if (newPosition.accuracy < 30) {
          timer.cancel();
          startRun(newPosition);

          // Inform the user
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS signal acquired! Starting run...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });

    // Add a timeout to avoid waiting forever
    Future.delayed(const Duration(seconds: 45), () {
      if (mounted && !isTracking) {
        // If we haven't started after 45 seconds, use whatever accuracy we have
        if (currentLocation != null) {
          startRun(currentLocation!);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Starting run with current accuracy (${currentLocation!.accuracy.toStringAsFixed(1)}m)'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    });
  }

  /// Called when the user taps the "End Run" button.
  void _endRunAndSave() {
    if (currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot end run without a valid location')),
      );
      return;
    }
    endRun();
    _saveRunData();
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
        // Navigate after a delay.
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

  /// Formats seconds into a mm:ss string.
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
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
          // Use the reusable RunMetricsCard widget.
          Positioned(
            top: 20,
            left: 20,
            child: RunMetricsCard(
              time: _formatTime(secondsElapsed),
              distance: '${(distanceKm).toStringAsFixed(2)} km',
            ),
          ),
          // Auto-Paused indicator (kept inline for now)
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
      // Center the button at the bottom
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
