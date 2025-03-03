// lib/pages/active_run_page.dart (partial update)
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
  List<Position> _positionSamples = []; // Track multiple position samples
  Timer? _locationSamplingTimer; // Timer for sampling locations

  // Accuracy thresholds tailored for each platform
  final double _goodAccuracyThreshold = Platform.isIOS ? 65.0 : 20.0;
  final double _acceptableAccuracyThreshold = Platform.isIOS ? 100.0 : 40.0;

  @override
  void initState() {
    super.initState();
    _initializeLocationTracking();
  }

  /// Helper to determine if accuracy is valid (not the suspicious 1440 value)
  bool _isValidAccuracy(double accuracy) {
    // Filter out the suspicious 1440m value
    if (accuracy == 1440.0) return false;

    // Also filter out other abnormally high values
    if (accuracy > 500.0) return false;

    return true;
  }

  /// Helper to find the position with best accuracy from a list
  Position _getBestPosition(List<Position> positions) {
    if (positions.isEmpty) throw Exception("No positions to choose from");

    // Filter out suspicious accuracy values
    final validPositions = positions.where((pos) => _isValidAccuracy(pos.accuracy)).toList();

    if (validPositions.isEmpty) {
      // If all had suspicious values, use all positions instead
      positions.sort((a, b) => a.accuracy.compareTo(b.accuracy));
      return positions.first;
    }

    // Sort by accuracy (lower is better)
    validPositions.sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return validPositions.first;
  }

  /// Initialize location tracking with improved accuracy handling
  Future<void> _initializeLocationTracking() async {
    setState(() {
      _isInitializing = true;
      _debugStatus = "Checking location services...";
      _positionSamples = [];
    });

    // Check if location services are enabled
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

    // Check permission status
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

    // Start collecting location samples
    _startLocationSampling();

    // Set a backup timeout
    Timer(const Duration(seconds: 30), () {
      if (_isInitializing && mounted) {
        _locationSamplingTimer?.cancel();
        _evaluateAndStartRun(true); // Force start with what we have
      }
    });
  }

  /// Start continuous sampling of location to find good accuracy
  void _startLocationSampling() {
    _locationSamplingTimer?.cancel();

    // Create proper location settings by platform
    final LocationSettings locationSettings = Platform.isIOS
        ? AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      activityType: ActivityType.fitness,
      pauseLocationUpdatesAutomatically: false,
    )
        : AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
    );

    setState(() => _debugStatus = "Collecting location samples...");

    // Declare the subscription variable
    StreamSubscription<Position>? subscription;

    // Set a timer to cancel this subscription after max attempts
    _locationSamplingTimer = Timer(const Duration(seconds: 15), () {
      subscription?.cancel();
      if (mounted && _isInitializing) {
        _evaluateAndStartRun(false);
      }
    });

    // Subscribe to location stream to collect samples
    subscription = Geolocator.getPositionStream(
        locationSettings: locationSettings
    ).listen(
            (position) {
          if (!mounted) {
            subscription?.cancel();
            return;
          }

          _locationAttempts++;
          setState(() {
            currentLocation = position;
            _debugStatus = "Sample #$_locationAttempts: ${position.accuracy.toStringAsFixed(1)}m";
          });

          // Only add valid readings to our samples
          if (_isValidAccuracy(position.accuracy)) {
            _positionSamples.add(position);
          }

          // If we got a good accuracy reading, we can start
          if (position.accuracy <= _goodAccuracyThreshold) {
            subscription?.cancel();
            _evaluateAndStartRun(false);
            return;
          }

          // After collecting multiple samples, evaluate if we have enough
          if (_positionSamples.length >= 5 || _locationAttempts >= 10) {
            subscription?.cancel();
            _evaluateAndStartRun(false);
            return;
          }
        },
        onError: (error) {
          setState(() => _debugStatus = "Location error: $error");
          // Don't cancel on error, keep trying
        }
    );
  }

  /// Evaluate collected samples and start run if possible
  void _evaluateAndStartRun(bool forceStart) {
    if (!mounted || !_isInitializing) return;

    if (_positionSamples.isEmpty && currentLocation == null) {
      // No positions collected - try using direct getCurrentPosition
      setState(() => _debugStatus = "No samples collected, trying direct method...");
      _tryDirectLocationAcquisition();
      return;
    }

    // If we have valid samples, find the best one
    if (_positionSamples.isNotEmpty) {
      Position bestPosition = _getBestPosition(_positionSamples);
      setState(() => _debugStatus = "Best accuracy: ${bestPosition.accuracy.toStringAsFixed(1)}m");

      // Start if accuracy is good enough or we've been forced to start
      if (bestPosition.accuracy <= _acceptableAccuracyThreshold || forceStart) {
        _startRunWithPosition(bestPosition);
        return;
      }
    }

    // If we have currentLocation but not good samples
    if (currentLocation != null && (forceStart || _positionSamples.isEmpty)) {
      _startRunWithPosition(currentLocation!);
      return;
    }

    // If we get here and forceStart is true, use whatever we have
    if (forceStart && currentLocation != null) {
      _startRunWithPosition(currentLocation!);
      return;
    }

    // If we get here, we don't have good enough data
    setState(() {
      _isInitializing = false;
      _debugStatus = "Could not get accurate location";
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not get accurate location. Try again outdoors with clear sky view.'),
        duration: Duration(seconds: 4),
      ),
    );
  }

  /// Try to get location directly as a fallback
  void _tryDirectLocationAcquisition() async {
    try {
      setState(() => _debugStatus = "Trying direct location acquisition...");

      // Use a longer timeout and best accuracy
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 15)
      );

      if (mounted) {
        setState(() {
          currentLocation = position;
          _debugStatus = "Direct method accuracy: ${position.accuracy.toStringAsFixed(1)}m";
        });

        // If accuracy is acceptable or it's our last resort
        if (_isValidAccuracy(position.accuracy) || _locationAttempts > 15) {
          _startRunWithPosition(position);
        } else {
          setState(() {
            _isInitializing = false;
            _debugStatus = "Could not get accurate location";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS accuracy is poor. Try again in an open area.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _debugStatus = "Location error: $e";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error getting location: ${e.toString()}'),
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
  void dispose() {
    _locationSamplingTimer?.cancel();
    super.dispose();
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
                if (_positionSamples.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Samples collected: ${_positionSamples.length}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    _locationAttempts = 0;
                    _positionSamples.clear();
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