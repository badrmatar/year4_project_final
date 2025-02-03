import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
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
  final double _pauseThreshold = 0.5;
  final double _resumeThreshold = 1.0;
  bool _isInitializing = true;
  StreamSubscription<LocationData>? _locationSubscription;

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
        if (_isInitializing && newLocation.accuracy != null && newLocation.accuracy! < 20) {
          // Once we have a good accuracy, start the run
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
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_autoPaused && mounted) {
        setState(() => _secondsElapsed++);
      }
    });

    _locationService.trackLocation().listen((newLocation) {
      if (!_isTracking) return;

      final speed = (newLocation.speed ?? 0.0).clamp(0.0, double.infinity);
      _handleAutoPauseLogic(speed);

      if (_currentLocation != null && !_autoPaused) {
        final distance = _calculateDistance(
          _currentLocation!.latitude!,
          _currentLocation!.longitude!,
          newLocation.latitude!,
          newLocation.longitude!,
        );

        if (distance > 3.0) {
          setState(() => _distanceCovered += distance);
        }
      }

      setState(() => _currentLocation = newLocation);
    });
  }

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

  // lib/pages/active_run_page.dart


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

      final requestBody = jsonEncode({
        'user_id': user.id,
        'start_time': startTime,
        'end_time': endTime,
        'start_latitude': _startLocation!.latitude,
        'start_longitude': _startLocation!.longitude,
        'end_latitude': _endLocation!.latitude,
        'end_longitude': _endLocation!.longitude,
        'distance_covered': distance,
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
            // No challenge, just show simple success message
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Run saved successfully! Distance: ${(distance / 1000).toStringAsFixed(2)} km'),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }

          // Only navigate to challenges page if there was a challenge
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
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Time Elapsed: ${_formatTime(_secondsElapsed)}',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 16),
            Text(
              'Distance Covered: ${distanceKm.toStringAsFixed(2)} km',
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 8),
            if (_autoPaused)
              const Text(
                'Auto-Paused',
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _endRun,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text(
                'End Run',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}