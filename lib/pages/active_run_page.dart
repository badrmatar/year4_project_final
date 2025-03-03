// lib/pages/active_run_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io'; // Added for Platform checks
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

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
  bool _isInitializing = true; // Track initialization state
  int _locationAttempts = 0; // Count location acquisition attempts

  @override
  void initState() {
    super.initState();
    _initializeLocationTracking();
  }

  /// Initialize location tracking with platform-specific handling
  Future<void> _initializeLocationTracking() async {
    setState(() {
      _isInitializing = true;
    });

    // Request an initial location with platform-specific handling
    try {
      final position = await locationService.getCurrentLocation();
      if (position != null && mounted) {
        setState(() {
          currentLocation = position;
        });

        // Platform specific accuracy requirements
        if (Platform.isIOS) {
          if (position.accuracy < 50) {
            // For iOS, be more lenient with initial accuracy
            _startRunWithPosition(position);
          } else {
            _waitForBetterAccuracyIOS();
          }
        } else {
          // Android path
          if (position.accuracy < 30) {
            _startRunWithPosition(position);
          } else {
            _waitForBetterAccuracy();
          }
        }
      } else {
        // Handle case where we couldn't get a position
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to get your location. Please check app permissions.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      print('Error initializing location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location error: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Helper to start the run with a position
  void _startRunWithPosition(Position position) {
    if (mounted) {
      setState(() {
        _isInitializing = false;
      });
      startRun(position);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Starting run with accuracy: ${position.accuracy.toStringAsFixed(1)}m'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Helper method to wait for better accuracy on Android
  void _waitForBetterAccuracy() {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      _locationAttempts++;
      final newPosition = await locationService.getCurrentLocation();
      if (newPosition != null && mounted) {
        setState(() {
          currentLocation = newPosition;
        });

        // Start the run once we have good accuracy or made several attempts
        if (newPosition.accuracy < 30 || _locationAttempts > 10) {
          timer.cancel();
          _startRunWithPosition(newPosition);
        }
      }

      // Safety timeout - use whatever we have after 30 seconds
      if (_locationAttempts > 15) {
        timer.cancel();
        if (mounted && currentLocation != null) {
          _startRunWithPosition(currentLocation!);
        } else {
          setState(() {
            _isInitializing = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get accurate location after multiple attempts.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    });
  }

  /// Special method for iOS with different accuracy requirements
  void _waitForBetterAccuracyIOS() {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      _locationAttempts++;
      final newPosition = await locationService.getCurrentLocation();
      if (newPosition != null && mounted) {
        setState(() {
          currentLocation = newPosition;
        });

        // On iOS we might need to be more lenient with accuracy
        if (newPosition.accuracy < 50 || _locationAttempts > 7) {
          timer.cancel();
          _startRunWithPosition(newPosition);
        }
      }

      // Safety timeout after fewer attempts for iOS
      if (_locationAttempts > 10) {
        timer.cancel();
        if (currentLocation != null && mounted) {
          _startRunWithPosition(currentLocation!);
        } else {
          setState(() {
            _isInitializing = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services seem unavailable. Please check permissions.'),
              duration: Duration(seconds: 3),
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
    // Show loading screen during initialization
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Active Run')),
        body: Container(
          color: Colors.black.withOpacity(0.7),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Waiting for GPS signal...',
                  style: TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                CircularProgressIndicator(
                  color: currentLocation != null ? Colors.green : Colors.white,
                ),
                if (currentLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text(
                      'Accuracy: ${currentLocation!.accuracy.toStringAsFixed(1)} meters',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  'Attempt ${_locationAttempts + 1}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      );
    }

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