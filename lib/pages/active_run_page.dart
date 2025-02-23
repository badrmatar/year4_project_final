import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
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

class ActiveRunPageState extends State<ActiveRunPage> {
  // Protected members accessible to child classes
  @protected
  final LocationService locationService = LocationService();

  @protected
  Position? get currentLocation => _currentLocation;
  @protected
  Position? _startLocation;
  @protected
  Position? _currentLocation;
  @protected
  Position? _endLocation;
  @protected
  double _distanceCovered = 0.0;
  @protected
  int _secondsElapsed = 0;
  @protected
  Timer? _timer;
  @protected
  bool _isTracking = false;
  @protected
  bool _autoPaused = false;
  @protected
  bool _isInitializing = true;
  @protected
  StreamSubscription<Position>? _locationSubscription;

  // Protected map-related variables
  @protected
  final List<LatLng> _route = [];
  @protected
  Polyline _routePolyline = const Polyline(
    polylineId: PolylineId('route'),
    color: Colors.orange,
    width: 5,
    points: [],
  );
  @protected
  GoogleMapController? _mapController;

  // Private variables
  int _stillCounter = 0;
  final double _pauseThreshold = 0.5;
  final double _resumeThreshold = 1.0;
  LatLng? _lastRecordedLocation;

  @override
  void initState() {
    super.initState();
    _initializeRun();
  }

  Future<void> _initializeRun() async {
    // Check for location permissions before subscribing.
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Location permission not granted. Please allow location access to start run.')),
          );
        }
        return;
      }
    }

    // Get the initial location.
    final initialPosition = await locationService.getCurrentLocation();
    if (initialPosition != null && mounted) {
      setState(() {
        _currentLocation = initialPosition;
      });
      if (initialPosition.accuracy < 20) {
        _isInitializing = false;
        _startRun(initialPosition);
      }
    }

    // Subscribe to the location stream with error handling.
    _locationSubscription = locationService.trackLocation().listen(
          (newPosition) {
        if (!mounted) return;
        setState(() => _currentLocation = newPosition);
        if (_isInitializing && newPosition.accuracy < 25) {
          if (mounted) {
            setState(() {
              _isInitializing = false;
            });
          }
          _startRun(newPosition);
        }
      },
      onError: (error) async {
        debugPrint('Location stream error: $error');
        // Re-check permission if an error occurs.
        LocationPermission newPermission = await Geolocator.checkPermission();
        if (newPermission == LocationPermission.denied ||
            newPermission == LocationPermission.deniedForever) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Location permission is required to start a run.')),
            );
          }
        } else {
          // Permission is granted now – cancel the current subscription and reinitialize.
          await _locationSubscription?.cancel();
          if (mounted) {
            _initializeRun();
          }
        }
      },
    );

    // Fallback: If after 30 seconds we are still initializing, start with the last known location.
    Timer(const Duration(seconds: 30), () {
      if (_isInitializing && mounted && _currentLocation != null) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
          });
        }
        _startRun(_currentLocation!);
      }
    });
  }

  @protected
  void _startRun(Position position) {
    if (!mounted) return;
    setState(() {
      _startLocation = position;
      _isTracking = true;
      _distanceCovered = 0.0;
      _secondsElapsed = 0;
      _autoPaused = false;
      _route.clear();

      final startPoint = LatLng(position.latitude, position.longitude);
      _route.add(startPoint);
      _routePolyline = _routePolyline.copyWith(pointsParam: _route);
      _lastRecordedLocation = startPoint;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (!_autoPaused) {
        setState(() => _secondsElapsed++);
      }
    });

    // Start listening to location updates for the run.
    locationService.trackLocation().listen((newPosition) {
      if (!_isTracking || !mounted) return;

      final speed = newPosition.speed.clamp(0.0, double.infinity);
      _handleAutoPauseLogic(speed);

      if (_lastRecordedLocation != null && !_autoPaused) {
        final distance = _calculateDistance(
          _lastRecordedLocation!.latitude,
          _lastRecordedLocation!.longitude,
          newPosition.latitude,
          newPosition.longitude,
        );

        if (distance > 20.0 && mounted) {
          setState(() {
            _distanceCovered += distance;
            _lastRecordedLocation = LatLng(newPosition.latitude, newPosition.longitude);
          });
        }
      }

      if (mounted) {
        setState(() {
          _currentLocation = newPosition;
          final newPoint = LatLng(newPosition.latitude, newPosition.longitude);
          _route.add(newPoint);
          _routePolyline = _routePolyline.copyWith(pointsParam: _route);
        });

        _mapController?.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(newPosition.latitude, newPosition.longitude),
          ),
        );
      }
    });
  }

  void _handleAutoPauseLogic(double speed) {
    if (_autoPaused) {
      if (speed > _resumeThreshold && mounted) {
        setState(() {
          _autoPaused = false;
          _stillCounter = 0;
        });
      }
    } else {
      if (speed < _pauseThreshold) {
        _stillCounter++;
        if (_stillCounter >= 5 && mounted) {
          setState(() => _autoPaused = true);
        }
      } else {
        _stillCounter = 0;
      }
    }
  }

  double _calculateDistance(
      double startLat, double startLng, double endLat, double endLng) {
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

  @protected
  void endRun() {
    if (_currentLocation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot end run without valid location')),
        );
      }
      return;
    }

    _timer?.cancel();
    if (mounted) {
      setState(() {
        _endLocation = _currentLocation;
        _isTracking = false;
      });
    }
    _saveRunData();
  }

  Future<void> _saveRunData() async {
    try {
      final user = Provider.of<UserModel>(context, listen: false);

      if (user.id == 0 || _startLocation == null || _endLocation == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Missing required data to save run")),
          );
        }
        return;
      }

      final distance = double.parse(_distanceCovered.toStringAsFixed(2));
      final startTime =
      (_startLocation!.timestamp ?? DateTime.now()).toUtc().toIso8601String();
      final endTime =
      (_endLocation!.timestamp ?? DateTime.now()).toUtc().toIso8601String();

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
        'route': routeJson,
        'journey_type': widget.journeyType,
      });

      final response = await http.post(
        Uri.parse(
            '${dotenv.env['SUPABASE_URL']}/functions/v1/create_user_contribution'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: requestBody,
      );

      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        final data = responseData['data'];

        if (data != null && mounted) {
          bool hasChallenge = false;

          if (data['total_distance_km'] != null &&
              data['required_distance_km'] != null) {
            hasChallenge = true;
            _showChallengeStatus(data);
          } else {
            _showRunSaved(distance);
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to save run: ${response.body}")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("An error occurred: ${e.toString()}")),
        );
      }
    }
  }

  void _showChallengeStatus(Map<String, dynamic> data) {
    if (!mounted) return;

    if (data['challenge_completed'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎉 Challenge Completed! 🎉',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
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
      ));
    }
  }

  void _showRunSaved(double distance) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Run saved successfully! Distance: ${(distance / 1000).toStringAsFixed(2)} km'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _locationSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = _distanceCovered / 1000;

    if (_isInitializing) {
      return _buildInitializingScreen();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Active Run')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentLocation != null
                  ? LatLng(_currentLocation!.latitude, _currentLocation!.longitude)
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
          _buildMetricsCard(distanceKm),
          if (_autoPaused) _buildAutoPausedCard(),
          _buildEndRunButton(),
        ],
      ),
    );
  }

  Widget _buildInitializingScreen() {
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
                    'Accuracy: ${_currentLocation!.accuracy.toStringAsFixed(1)} meters',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsCard(double distanceKm) {
    return Positioned(
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
    );
  }

  Widget _buildAutoPausedCard() {
    return Positioned(
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
    );
  }

  Widget _buildEndRunButton() {
    return Positioned(
      bottom: 20,
      left: MediaQuery.of(context).size.width * 0.5 - 60,
      child: ElevatedButton(
        onPressed: endRun,
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
