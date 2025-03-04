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

  // Strict accuracy thresholds
  final double _goodAccuracyThreshold = 20.0;     // Ideal accuracy
  final double _acceptableAccuracyThreshold = 50.0; // Maximum allowed accuracy

  // Freshness threshold in seconds
  final int _freshnessThresholdSeconds = 10;

  // Set for our custom markers and circles.
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _initializeLocationTracking();
  }

  /// Helper to check if an accuracy value is valid
  bool _isValidAccuracy(double accuracy) {
    if (accuracy == 1440.0) return false;
    if (Platform.isIOS) {
      if (accuracy == 65.0) return false;
      if (accuracy == 10.0 && _locationAttempts <= 2) return false;
      if (accuracy == 100.0) return false;
      if (accuracy > 200.0) return false;
    } else {
      if (accuracy > 500.0) return false;
    }
    return true;
  }

  /// Helper to find the position with best accuracy from a list
  Position _getBestPosition(List<Position> positions) {
    if (positions.isEmpty) throw Exception("No positions to choose from");
    final validPositions =
    positions.where((pos) => _isValidAccuracy(pos.accuracy)).toList();
    if (validPositions.isEmpty) {
      positions.sort((a, b) => a.accuracy.compareTo(b.accuracy));
      return positions.first;
    }
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

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    setState(() => _debugStatus = "Location services enabled: $serviceEnabled");
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Location services are disabled. Please enable them in Settings.'),
            duration: Duration(seconds: 4),
          ),
        );
        setState(() => _isInitializing = false);
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    setState(() => _debugStatus = "Initial permission status: $permission");
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _debugStatus = "Requesting permission...");
      permission = await Geolocator.requestPermission();
      setState(() => _debugStatus = "After request, permission status: $permission");
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Location permission was denied. Please enable it in Settings.'),
              duration: Duration(seconds: 4),
            ),
          );
          setState(() => _isInitializing = false);
        }
        return;
      }
    }
    _startLocationSamplingUntilGoodAccuracy();
  }

  /// Start continuous sampling of location UNTIL good accuracy is found
  void _startLocationSamplingUntilGoodAccuracy() {
    _locationSamplingTimer?.cancel();
    _locationSamplingSubscription?.cancel();
    setState(() => _debugStatus = "Setting up location tracking...");

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
            _beginContinuousLocationSampling(locationSettings);
          }
        });
      });
    } else {
      _beginContinuousLocationSampling(locationSettings);
    }
  }

  /// Begin continuous sampling of location
  void _beginContinuousLocationSampling(LocationSettings locationSettings) {
    setState(() => _debugStatus = "Waiting for GPS accuracy < 50m...");
    _positionSamples.clear();
    _locationAttempts = 0;
    _locationSamplingSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
              (position) {
            if (!mounted) {
              _locationSamplingSubscription?.cancel();
              return;
            }
            _locationAttempts++;
            setState(() {
              currentLocation = position;
              _debugStatus =
              "Sample #$_locationAttempts: ${position.accuracy.toStringAsFixed(1)}m";
            });
            if (_isValidAccuracy(position.accuracy)) {
              _positionSamples.add(position);
            }
            if (position.accuracy <= _acceptableAccuracyThreshold) {
              _locationSamplingSubscription?.cancel();
              _startRunWithPosition(position);
              return;
            }
            if (position.accuracy == 1440.0) {
              setState(() {
                _debugStatus =
                "Received default iOS value (1440m). Waiting for better signal...";
              });
            } else if (position.accuracy > _acceptableAccuracyThreshold) {
              setState(() {
                _debugStatus =
                "Accuracy: ${position.accuracy.toStringAsFixed(1)}m - need < 50m";
              });
            }
          },
          onError: (error) {
            setState(() => _debugStatus = "Location error: $error");
          },
        );
  }

  /// Try to get a direct location as a fallback
  Future<void> _tryDirectLocationAcquisition() async {
    try {
      setState(() => _debugStatus = "Trying direct location acquisition...");
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 15));
      if (mounted) {
        setState(() {
          currentLocation = position;
          _debugStatus =
          "Direct method accuracy: ${position.accuracy.toStringAsFixed(1)}m";
        });
        if (_isValidAccuracy(position.accuracy) &&
            position.accuracy <= _acceptableAccuracyThreshold) {
          _startRunWithPosition(position);
        } else {
          setState(() {
            _isInitializing = false;
            _debugStatus =
            "GPS accuracy of ${position.accuracy.toStringAsFixed(1)}m exceeds the required 50m threshold";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'GPS accuracy is too poor (must be under 50m). Please try again in an open area with clear sky view.'),
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

  /// Helper to start the run with a position, but verify it first
  void _startRunWithPosition(Position position) async {
    if (!mounted) return;
    setState(() => _debugStatus = "Verifying position before starting...");
    try {
      final finalPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 10),
      );
      final currentUtc = DateTime.now().toUtc();
      final positionTimeUtc = finalPosition.timestamp?.toUtc();
      if (positionTimeUtc != null &&
          currentUtc.difference(positionTimeUtc).inSeconds >
              _freshnessThresholdSeconds) {
        if (finalPosition.accuracy <= _acceptableAccuracyThreshold &&
            _isValidAccuracy(finalPosition.accuracy)) {
          position = finalPosition;
          setState(() =>
          _debugStatus = "Using verified position (ignoring staleness)!");
        } else {
          setState(() => _debugStatus =
          "Verified position is stale (${currentUtc.difference(positionTimeUtc).inSeconds}s old) and inaccurate.");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "Location reading is stale. Please wait for a fresh reading."),
              duration: Duration(seconds: 5),
            ),
          );
          _initializeLocationTracking();
          return;
        }
      } else {
        if (finalPosition.accuracy <= _acceptableAccuracyThreshold &&
            _isValidAccuracy(finalPosition.accuracy)) {
          position = finalPosition;
          setState(() => _debugStatus = "Using verified position!");
        } else {
          setState(() => _debugStatus =
          "Verified position accuracy ${finalPosition.accuracy.toStringAsFixed(1)}m exceeds threshold.");
        }
      }
    } catch (e) {
      setState(() => _debugStatus =
      "Using best available position (${position.accuracy.toStringAsFixed(1)}m) due to error: $e");
    }

    if (position.accuracy > _acceptableAccuracyThreshold) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'GPS reading is not accurate enough (accuracy: ${position.accuracy.toStringAsFixed(1)}m). Please try again in an open area.'),
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
    // Start the run using the mixin’s method.
    startRun(position);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Starting run with accuracy: ${position.accuracy.toStringAsFixed(1)}m'),
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

  /// Save the run data to the backend
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

  /// Formats seconds into a mm:ss string
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
    // Update custom markers and circles based on currentLocation.
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
          radius: currentLocation!.accuracy, // This represents the accuracy radius
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
            // Disable default location indicators.
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
