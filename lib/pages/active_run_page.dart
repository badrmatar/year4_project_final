import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../services/location_service.dart';

class ActiveRunPage extends StatefulWidget {
  const ActiveRunPage({Key? key}) : super(key: key);

  @override
  _ActiveRunPageState createState() => _ActiveRunPageState();
}

class _ActiveRunPageState extends State<ActiveRunPage> {
  final LocationService _locationService = LocationService();
  LocationData? _startLocation;
  LocationData? _currentLocation;
  LocationData? _endLocation;
  double _distanceCovered = 0.0;
  int _secondsElapsed = 0;
  Timer? _timer;
  bool _isTracking = false;
  bool _autoPaused = false;
  int _stillCounter = 0;
  final double _pauseThreshold = 0.5; // If speed falls below this, count as "still"
  final double _resumeThreshold = 1.0;  // If speed exceeds this, resume running
  bool _isInitializing = true;
  StreamSubscription<LocationData>? _locationSubscription;

  // New variable to keep track of the last location used for distance calculation.
  LatLng? _lastRecordedLocation;

  // Variables for map and route
  final List<LatLng> _route = [];
  Polyline _routePolyline = Polyline(
    polylineId: const PolylineId('route'),
    color: Colors.orange,
    width: 5,
    points: [],
  );
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _initializeRun();
  }

  Future<void> _initializeRun() async {
    // Start location tracking immediately
    _locationSubscription = _locationService.trackLocation().listen((newLocation) {
      if (mounted) {
        setState(() => _currentLocation = newLocation);
        // When a good accuracy is reached, start the run
        if (_isInitializing &&
            newLocation.accuracy != null &&
            newLocation.accuracy! < 20) {
          _isInitializing = false;
          _startRun(newLocation);
        }
      }
    });

    // Fallback timer in case GPS takes too long
    Timer(const Duration(seconds: 30), () {
      if (_isInitializing && mounted && _currentLocation != null) {
        _isInitializing = false;
        _startRun(_currentLocation!);
      }
    });
  }

  void _startRun(LocationData location) {
    setState(() {
      _startLocation = location;
      _isTracking = true;
      _distanceCovered = 0.0;
      _secondsElapsed = 0;
      _autoPaused = false;
      _route.clear();
      // Initialize the route and lastRecordedLocation using the starting location.
      if (location.latitude != null && location.longitude != null) {
        final startPoint = LatLng(location.latitude!, location.longitude!);
        _route.add(startPoint);
        _routePolyline = _routePolyline.copyWith(pointsParam: _route);
        _lastRecordedLocation = startPoint;
      }
    });

    // Start timer to update elapsed time
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_autoPaused && mounted) {
        setState(() => _secondsElapsed++);
      }
    });

    // Listen for new location updates
    _locationService.trackLocation().listen((newLocation) {
      if (!_isTracking) return;

      final speed = (newLocation.speed ?? 0.0).clamp(0.0, double.infinity);
      _handleAutoPauseLogic(speed);

      // Calculate distance using the last recorded location (instead of _currentLocation)
      if (_lastRecordedLocation != null && !_autoPaused) {
        final distance = _calculateDistance(
          _lastRecordedLocation!.latitude,
          _lastRecordedLocation!.longitude,
          newLocation.latitude!,
          newLocation.longitude!,
        );
        // Only update if movement is significant (e.g. > 3 meters)
        if (distance > 3.0) {
          setState(() {
            _distanceCovered += distance;
            // Update _lastRecordedLocation after adding the distance.
            _lastRecordedLocation = LatLng(newLocation.latitude!, newLocation.longitude!);
          });
        }
      }

      setState(() {
        _currentLocation = newLocation;
        // Add new location to route if valid
        if (newLocation.latitude != null && newLocation.longitude != null) {
          final newPoint = LatLng(newLocation.latitude!, newLocation.longitude!);
          _route.add(newPoint);
          _routePolyline = _routePolyline.copyWith(pointsParam: _route);
        }
      });

      // Animate the map camera to the new location
      if (_mapController != null && newLocation.latitude != null && newLocation.longitude != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(newLocation.latitude!, newLocation.longitude!),
          ),
        );
      }
    });
  }

  // Auto-pause logic:
  // If the run is not paused and the speed is below _pauseThreshold,
  // we increase _stillCounter. When _stillCounter reaches 5, the run is auto-paused.
  // If the run is paused and speed rises above _resumeThreshold, we resume the run.
  void _handleAutoPauseLogic(double speed) {
    if (_autoPaused) {
      if (speed > _resumeThreshold) {
        setState(() {
          _autoPaused = false;
          _stillCounter = 0;
        });
      }
    } else {
      if (speed < _pauseThreshold) {
        _stillCounter++;
        if (_stillCounter >= 5) {
          setState(() => _autoPaused = true);
        }
      } else {
        _stillCounter = 0;
      }
    }
  }

  // Calculates the Haversine distance between two geographic coordinates.
  double _calculateDistance(double startLat, double startLng, double endLat, double endLng) {
    const earthRadius = 6371000.0;
    final dLat = (endLat - startLat) * (pi / 180);
    final dLng = (endLng - startLng) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(startLat * (pi / 180)) *
            cos(endLat * (pi / 180)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  void _endRun() {
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot end run without valid location')),
      );
      return;
    }

    _timer?.cancel();
    setState(() {
      _endLocation = _currentLocation;
      _isTracking = false;
    });
    _saveRunData();
  }

  Future<void> _saveRunData() async {
    debugPrint("Run ended. Distance: $_distanceCovered meters");

    try {
      final user = Provider.of<UserModel>(context, listen: false);

      debugPrint("Debug -> user.id = ${user.id}");
      debugPrint("Debug -> _startLocation = $_startLocation");
      debugPrint("Debug -> _endLocation = $_endLocation");

      if (user.id == 0 || _startLocation == null || _endLocation == null) {
        debugPrint("Missing required data for saving");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Missing required data to save run")),
          );
        }
        return;
      }

      final distance = double.parse(_distanceCovered.toStringAsFixed(2));

      final startTime = DateTime.fromMillisecondsSinceEpoch(
        _startLocation!.time!.toInt(),
      ).toUtc().toIso8601String();

      final endTime = DateTime.fromMillisecondsSinceEpoch(
        _endLocation!.time!.toInt(),
      ).toUtc().toIso8601String();

      // Convert _route to a JSON-friendly list
      final routeJson = _route.map((point) => {
        'latitude': point.latitude,
        'longitude': point.longitude,
      }).toList();

      final requestBody = jsonEncode({
        'user_id': user.id,
        'start_time': startTime,
        'end_time': endTime,
        'start_latitude': _startLocation!.latitude,
        'start_longitude': _startLocation!.longitude,
        'end_latitude': _endLocation!.latitude,
        'end_longitude': _endLocation!.longitude,
        'distance_covered': distance,
        'route': routeJson, // <-- New field added for route data
      });

      debugPrint("Saving run data with body: $requestBody");

      final response = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/create_user_contribution'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: requestBody,
      );

      if (response.statusCode == 201) {
        debugPrint("Successfully saved run data");
        debugPrint("Server response: ${response.body}");

        final responseData = jsonDecode(response.body);
        final data = responseData['data'];

        if (data != null) {
          bool hasChallenge = false;

          if (data['total_distance_km'] != null && data['required_distance_km'] != null) {
            hasChallenge = true;
            if (data['challenge_completed'] == true) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '🎉 Challenge Completed! 🎉',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Team Total: ${data['total_distance_km'].toStringAsFixed(2)} km',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                    duration: const Duration(seconds: 5),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Run saved successfully!'),
                        const SizedBox(height: 4),
                        Text(
                          'Team Progress: ${data['total_distance_km'].toStringAsFixed(2)}/${data['required_distance_km']} km',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Run saved successfully! Distance: ${(distance / 1000).toStringAsFixed(2)} km'),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }

          if (hasChallenge) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/challenges');
              }
            });
          }
        }
      } else {
        debugPrint("Failed to save run: ${response.statusCode}");
        debugPrint("Error details: ${response.body}");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to save run: ${response.body}")),
          );
        }
      }
    } catch (e) {
      debugPrint("Error saving run data: ${e.toString()}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("An error occurred: ${e.toString()}")),
        );
      }
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _showLocationError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Enable location services to track your run"),
        duration: Duration(seconds: 5),
      ),
    );
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = _distanceCovered / 1000;

    if (_isInitializing) {
      return Scaffold(
        body: Container(
          color: Colors.black87,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Waiting for GPS signal...',
                  style: TextStyle(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                CircularProgressIndicator(
                  color: _currentLocation != null ? Colors.green : Colors.white,
                ),
                if (_currentLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text(
                      'Accuracy: ${_currentLocation!.accuracy?.toStringAsFixed(1) ?? "Unknown"} meters',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Active Run')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentLocation != null &&
                  _currentLocation!.latitude != null &&
                  _currentLocation!.longitude != null
                  ? LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!)
                  : const LatLng(37.4219999, -122.0840575),
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            polylines: {_routePolyline},
            onMapCreated: (controller) {
              _mapController = controller;
            },
          ),
          Positioned(
            top: 20,
            left: 20,
            child: Card(
              color: Colors.white70,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Text(
                      'Time: ${_formatTime(_secondsElapsed)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Distance: ${distanceKm.toStringAsFixed(2)} km',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_autoPaused)
            Positioned(
              top: 90,
              left: 20,
              child: Card(
                color: Colors.redAccent.withOpacity(0.8),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'Auto-Paused',
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 20,
            left: MediaQuery.of(context).size.width * 0.5 - 60,
            child: ElevatedButton(
              onPressed: _endRun,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'End Run',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
