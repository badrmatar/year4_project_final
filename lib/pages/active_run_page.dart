// lib/pages/active_run_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../models/user.dart';
import '../mixins/run_tracking_mixin.dart';
import '../services/location_service.dart';

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
  bool _isInitializing = true;
  int _locationAttempts = 0;
  String _debugStatus = "Starting location services...";
  List<Position> _positionSamples = [];
  Timer? _locationSamplingTimer;
  StreamSubscription<Position>? _locationSamplingSubscription;

  // We want to start only if we have an accuracy below 50m.
  final double _acceptableAccuracyThreshold = 50.0;
  // Allow the location to be "fresh" within 10 seconds.
  final int _freshnessThresholdSeconds = 10;

  // For our custom marker and accuracy circle.
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _initializeLocationTracking();
  }

  /// Batch sampling: we allow a 10‑second window to collect several samples,
  /// then we pick the best (lowest accuracy) reading.
  void _batchSampleLocation(LocationSettings locationSettings) {
    setState(() => _debugStatus = "Batch sampling location for 10 seconds...");
    _positionSamples.clear();
    _locationAttempts = 0;
    _locationSamplingSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((position) {
          _locationAttempts++;
          // Only add valid readings (we allow any reading > 0 and up to 1000m)
          if (position.accuracy > 0 && position.accuracy <= 1000) {
            _positionSamples.add(position);
          }
          setState(() {
            _debugStatus = "Sample #$_locationAttempts: ${position.accuracy.toStringAsFixed(1)}m";
          });
        }, onError: (error) {
          setState(() => _debugStatus = "Location error: $error");
        });
    // After 10 seconds, cancel sampling and process the collected samples.
    Future.delayed(const Duration(seconds: 10), () {
      _locationSamplingSubscription?.cancel();
      if (_positionSamples.isNotEmpty) {
        // Choose the best sample (lowest accuracy value).
        Position bestSample = _getBestPosition(_positionSamples);
        setState(() {
          _debugStatus =
          "Best sample: ${bestSample.accuracy.toStringAsFixed(1)}m collected over $_locationAttempts samples";
        });
        if (bestSample.accuracy <= _acceptableAccuracyThreshold) {
          _startRunWithPosition(bestSample);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  "GPS accuracy is not good enough (${bestSample.accuracy.toStringAsFixed(1)}m). Please try again in an open area."),
              duration: const Duration(seconds: 5),
            ),
          );
          _initializeLocationTracking();
        }
      } else {
        setState(() {
          _debugStatus = "No valid location samples collected.";
        });
        _initializeLocationTracking();
      }
    });
  }

  /// Helper to choose the best reading from a list (lowest accuracy is best)
  Position _getBestPosition(List<Position> positions) {
    positions.sort((a, b) => a.accuracy.compareTo(b.accuracy));
    return positions.first;
  }

  /// Initialize location tracking: check services, permissions, etc.
  Future<void> _initializeLocationTracking() async {
    setState(() {
      _isInitializing = true;
      _debugStatus = "Checking location services...";
      _positionSamples = [];
    });

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

    // Start batch sampling. On iOS, flush any cached location first.
    final LocationSettings locationSettings = Platform.isIOS
        ? AppleSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
      activityType: ActivityType.fitness,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
    )
        : AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      forceLocationManager: true,
    );

    if (Platform.isIOS) {
      setState(() => _debugStatus = "Resetting iOS location cache...");
      Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.lowest,
          timeLimit: const Duration(seconds: 2))
          .catchError((_) {})
          .then((_) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            _batchSampleLocation(locationSettings);
          }
        });
      });
    } else {
      _batchSampleLocation(locationSettings);
    }
  }

  /// Attempt a direct high-accuracy reading as a fallback.
  Future<void> _tryDirectLocationAcquisition() async {
    try {
      setState(() => _debugStatus = "Trying direct location acquisition...");
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best, timeLimit: const Duration(seconds: 20));
      if (mounted) {
        setState(() {
          currentLocation = position;
          _debugStatus = "Direct method accuracy: ${position.accuracy.toStringAsFixed(1)}m";
        });
        if (position.accuracy <= _acceptableAccuracyThreshold) {
          _startRunWithPosition(position);
        } else {
          setState(() {
            _isInitializing = false;
            _debugStatus =
            "GPS accuracy of ${position.accuracy.toStringAsFixed(1)}m exceeds threshold";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS accuracy is too poor. Please try again in an open area with clear sky view.'),
              duration: Duration(seconds: 5),
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

  /// Verify the chosen position (from batch sampling) and start the run.
  /// This function also requests one fresh reading to confirm accuracy.
  void _startRunWithPosition(Position position) async {
    if (!mounted) return;
    setState(() => _debugStatus = "Verifying position before starting...");
    try {
      final freshPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 20),
      );
      final currentUtc = DateTime.now().toUtc();
      final posTimeUtc = freshPosition.timestamp?.toUtc();
      // If the fresh reading is within our freshness threshold, use it.
      if (posTimeUtc != null &&
          currentUtc.difference(posTimeUtc).inSeconds <= _freshnessThresholdSeconds &&
          freshPosition.accuracy <= _acceptableAccuracyThreshold) {
        position = freshPosition;
        setState(() => _debugStatus = "Using fresh verified position!");
      } else {
        setState(() => _debugStatus =
        "Fresh reading is either stale or inaccurate (${freshPosition.accuracy.toStringAsFixed(1)}m).");
      }
    } catch (e) {
      setState(() => _debugStatus =
      "Error getting fresh reading: $e. Using best available position (${position.accuracy.toStringAsFixed(1)}m).");
    }

    if (position.accuracy > _acceptableAccuracyThreshold) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'GPS reading not accurate enough (accuracy: ${position.accuracy.toStringAsFixed(1)}m). Please try again in an open area.'),
          duration: const Duration(seconds: 5),
        ),
      );
      _initializeLocationTracking();
      return;
    }

    setState(() {
      _isInitializing = false;
      _debugStatus = "Starting run!";
    });
    // Use the mixin's startRun method to begin tracking.
    startRun(position);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
        Text('Starting run with accuracy: ${position.accuracy.toStringAsFixed(1)}m'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Called when the user taps "End Run"
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

  /// Save the run data to the backend.
  Future<void> _saveRunData() async {
    final user = Provider.of<UserModel>(context, listen: false);
    if (user.id == 0 || startLocation == null || endLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing required data to save run")),
      );
      return;
    }
    final distance = double.parse(distanceCovered.toStringAsFixed(2));
    final startTime = (startLocation!.timestamp ?? DateTime.now())
        .toUtc()
        .toIso8601String();
    final endTime = (endLocation!.timestamp ?? DateTime.now())
        .toUtc()
        .toIso8601String();
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

  /// Formats seconds into a mm:ss string.
  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _locationSamplingTimer?.cancel();
    _locationSamplingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Update custom marker and accuracy circle from our verified currentLocation.
    if (currentLocation != null) {
      final currentLatLng = LatLng(currentLocation!.latitude, currentLocation!.longitude);
      _markers = {
        Marker(
          markerId: const MarkerId("current"),
          position: currentLatLng,
          infoWindow: InfoWindow(
            title: 'Your Location',
            snippet: 'Accuracy: ${currentLocation!.accuracy.toStringAsFixed(1)}m',
          ),
        )
      };
      _circles = {
        Circle(
          circleId: const CircleId("accuracy"),
          center: currentLatLng,
          radius: currentLocation!.accuracy,
          fillColor: Colors.blue.withOpacity(0.2),
          strokeColor: Colors.blue,
          strokeWidth: 2,
        )
      };
    }

    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('Active Run')),
        body: Container(
          color: Colors.black.withOpacity(0.7),
          child: Center(
            child: SingleChildScrollView(
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
                      _initializeLocationTracking();
                    },
                    child: const Text('Retry Location'),
                  ),
                  if (currentLocation != null)
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            'Current accuracy: ${currentLocation!.accuracy.toStringAsFixed(1)}m\nWaiting for accuracy < 50m',
                            style: TextStyle(
                                color: currentLocation!.accuracy <= _acceptableAccuracyThreshold
                                    ? Colors.green
                                    : Colors.orange,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'No time limit - will start automatically\nwhen accuracy is below 50m',
                          style: TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () {
                            _locationAttempts = 0;
                            _positionSamples.clear();
                            _initializeLocationTracking();
                          },
                          child: const Text('Restart GPS Search'),
                        ),
                      ],
                    ),
                ],
              ),
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
            // Disable the default location indicator.
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            markers: _markers,
            circles: _circles,
            polylines: {routePolyline},
            onMapCreated: (controller) {
              mapController = controller;
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
          Positioned(
            top: 20,
            left: 20,
            child: Card(
              color: Colors.white.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Time: ${_formatTime(secondsElapsed)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Distance: ${distanceKm.toStringAsFixed(2)} km',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Accuracy: ${currentLocation?.accuracy.toStringAsFixed(1) ?? "N/A"} m',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: currentLocation != null &&
                                currentLocation!.accuracy <= _acceptableAccuracyThreshold
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          currentLocation != null &&
                              currentLocation!.accuracy <= _acceptableAccuracyThreshold
                              ? Icons.check_circle
                              : Icons.error_outline,
                          color: currentLocation != null &&
                              currentLocation!.accuracy <= _acceptableAccuracyThreshold
                              ? Colors.green
                              : Colors.red,
                          size: 14,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
