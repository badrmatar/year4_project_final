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
  String _debugStatus = "Starting location services...";

  @override
  void initState() {
    super.initState();
    _initializeLocationTracking();
  }

  /// Initialize location tracking with platform-specific handling
  Future<void> _initializeLocationTracking() async {
    setState(() {
      _isInitializing = true;
      _debugStatus = "Checking location services...";
    });

    // For iOS, we should check permission status explicitly first
    if (Platform.isIOS) {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      setState(() => _debugStatus = "Location services enabled: $serviceEnabled");

      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled. Please enable them in Settings.'),
              duration: Duration(seconds: 4),
            ),
          );
          setState(() => _isInitializing = false);
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      setState(() => _debugStatus = "Initial permission status: $permission");

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        // Request permission and check again
        setState(() => _debugStatus = "Requesting permission...");
        permission = await Geolocator.requestPermission();
        setState(() => _debugStatus = "After request, permission status: $permission");

        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission was denied. Please enable it in Settings.'),
                duration: Duration(seconds: 4),
              ),
            );
            setState(() => _isInitializing = false);
          }
          return;
        }
      }

      // On iOS, there's sometimes a delay after granting permissions
      // so we'll add a small delay before trying to get position
      setState(() => _debugStatus = "Permission granted, waiting for systems to initialize...");
      await Future.delayed(const Duration(milliseconds: 1000));
    }

    // Try to get current location
    try {
      setState(() => _debugStatus = "Getting current location...");
      final position = await locationService.getCurrentLocation();

      if (position != null && mounted) {
        setState(() {
          currentLocation = position;
          _debugStatus = "Got location with accuracy: ${position.accuracy}m";
        });

        // Platform specific accuracy requirements
        if (Platform.isIOS) {
          if (position.accuracy < 100) { // More lenient for iOS
            _startRunWithPosition(position);
          } else {
            setState(() => _debugStatus = "Location not accurate enough, waiting for better signal...");
            _waitForBetterAccuracyIOS();
          }
        } else {
          // Android path
          if (position.accuracy < 30) {
            _startRunWithPosition(position);
          } else {
            setState(() => _debugStatus = "Location not accurate enough, waiting for better signal...");
            _waitForBetterAccuracy();
          }
        }
      } else {
        setState(() => _debugStatus = "Couldn't get initial position, trying fallback...");

        // If we still couldn't get position, try one more time with getLastKnownPosition
        if (Platform.isIOS) {
          final lastPosition = await Geolocator.getLastKnownPosition();
          if (lastPosition != null && mounted) {
            setState(() {
              currentLocation = lastPosition;
              _debugStatus = "Using last known position with timestamp: ${lastPosition.timestamp}";
            });
            _startRunWithPosition(lastPosition);
            return;
          }
        }

        // Handle case where we couldn't get a position
        if (mounted) {
          setState(() => _debugStatus = "Failed to get location.");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to get your location. Try restarting the app.'),
              duration: Duration(seconds: 4),
            ),
          );
          setState(() => _isInitializing = false);
        }
      }
    } catch (e) {
      print('Error initializing location: $e');
      if (mounted) {
        setState(() => _debugStatus = "Location error: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location error: ${e.toString()}'),
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() => _isInitializing = false);
      }
    }
  }

  /// Helper to start the run with a position
  void _startRunWithPosition(Position position) {
    if (mounted) {
      setState(() {
        _isInitializing = false;
        _debugStatus = "Starting run!";
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
      setState(() => _debugStatus = "Waiting for better accuracy... Attempt $_locationAttempts");

      final newPosition = await locationService.getCurrentLocation();
      if (newPosition != null && mounted) {
        setState(() {
          currentLocation = newPosition;
          _debugStatus = "New accuracy: ${newPosition.accuracy}m";
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
            _debugStatus = "Timeout waiting for accurate location.";
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
      setState(() => _debugStatus = "iOS: Waiting for better accuracy... Attempt $_locationAttempts");

      final newPosition = await locationService.getCurrentLocation();
      if (newPosition != null && mounted) {
        setState(() {
          currentLocation = newPosition;
          _debugStatus = "iOS: New accuracy: ${newPosition.accuracy}m";
        });

        // On iOS we need to be more lenient with accuracy
        if (newPosition.accuracy < 100 || _locationAttempts > 7) {
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
            _debugStatus = "iOS: Timeout waiting for location.";
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
                const SizedBox(height: 16),
                // Debug status
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _debugStatus,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                if (currentLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Location: ${currentLocation!.latitude.toStringAsFixed(6)}, ${currentLocation!.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                if (currentLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Accuracy: ${currentLocation!.accuracy.toStringAsFixed(1)} meters',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                const SizedBox(height: 10),
                FutureBuilder<LocationPermission>(
                  future: Geolocator.checkPermission(),
                  builder: (context, snapshot) {
                    return Text(
                      'Permission status: ${snapshot.data?.toString() ?? "checking..."}',
                      style: const TextStyle(color: Colors.white70),
                    );
                  },
                ),
                Text(
                  'Attempt ${_locationAttempts + 1}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    _locationAttempts = 0;
                    _initializeLocationTracking(); // Re-try
                  },
                  child: const Text('Retry Location'),
                ),
                if (Platform.isIOS && currentLocation != null)
                  ElevatedButton(
                    onPressed: () {
                      // Force start with current location even if not ideal
                      _startRunWithPosition(currentLocation!);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    child: const Text('Force Start with Current Location'),
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
            onMapCreated: (controller) {
              mapController = controller;

              // For iOS, immediately move camera to current location
              if (Platform.isIOS && currentLocation != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(currentLocation!.latitude, currentLocation!.longitude),
                    15,
                  ),
                );
              }
            },
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