// lib/pages/duo_active_run_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user.dart';
import '../services/location_service.dart';

class DuoActiveRunPage extends StatefulWidget {
  final int challengeId;

  const DuoActiveRunPage({Key? key, required this.challengeId})
      : super(key: key);

  @override
  _DuoActiveRunPageState createState() => _DuoActiveRunPageState();
}

class _DuoActiveRunPageState extends State<DuoActiveRunPage> {
  final LocationService _locationService = LocationService();
  final supabase = Supabase.instance.client;

  // Run tracking variables
  Position? _startLocation;
  Position? _currentLocation;
  Position? _endLocation;
  double _distanceCovered = 0.0;
  int _secondsElapsed = 0;
  Timer? _timer;
  bool _isTracking = false;
  bool _autoPaused = false;
  bool _isInitializing = true;
  StreamSubscription<Position>? _locationSubscription;

  final List<LatLng> _route = [];
  Polyline _routePolyline = const Polyline(
    polylineId: PolylineId('route'),
    color: Colors.orange,
    width: 5,
    points: [],
  );
  GoogleMapController? _mapController;

  int _stillCounter = 0;
  final double _pauseThreshold = 0.5;
  final double _resumeThreshold = 1.0;
  LatLng? _lastRecordedLocation;

  // Duo-specific: partner tracking
  Position? _partnerLocation;
  double _partnerDistance = 0.0;
  Timer? _partnerPollingTimer;
  static const double MAX_ALLOWED_DISTANCE = 500; // Auto-end if >500m

  @override
  void initState() {
    super.initState();
    _initializeRun();
    _startPartnerPolling();
  }

  Future<void> _initializeRun() async {
    final initialPosition = await _locationService.getCurrentLocation();
    if (initialPosition != null) {
      setState(() {
        _currentLocation = initialPosition;
        _isInitializing = false;
      });
      _startRun(initialPosition);
    }
    _locationSubscription =
        _locationService.trackLocation().listen((position) {
          setState(() {
            _currentLocation = position;
          });
          if (_isInitializing && position.accuracy < 20) {
            _isInitializing = false;
            _startRun(position);
          }
        });
    // Fallback timer in case GPS is slow.
    Timer(const Duration(seconds: 3000), () {
      if (_isInitializing && mounted && _currentLocation != null) {
        _isInitializing = false;
        _startRun(_currentLocation!);
      }
    });
  }

  void _startRun(Position position) {
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
      if (!_autoPaused && mounted) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });

    _locationService.trackLocation().listen((position) {
      if (!_isTracking) return;

      final speed = position.speed.clamp(0.0, double.infinity);
      _handleAutoPauseLogic(speed);

      if (_lastRecordedLocation != null && !_autoPaused) {
        final distance = _calculateDistance(
          _lastRecordedLocation!.latitude,
          _lastRecordedLocation!.longitude,
          position.latitude,
          position.longitude,
        );
        if (distance > 20.0) {
          setState(() {
            _distanceCovered += distance;
            _lastRecordedLocation =
                LatLng(position.latitude, position.longitude);
          });
        }
      }

      setState(() {
        _currentLocation = position;
        final newPoint = LatLng(position.latitude, position.longitude);
        _route.add(newPoint);
        _routePolyline = _routePolyline.copyWith(pointsParam: _route);
      });

      _mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ),
      );
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
          setState(() {
            _autoPaused = true;
          });
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

  // Partner polling: every 2 seconds, check partner's location
  void _startPartnerPolling() {
    _partnerPollingTimer =
        Timer.periodic(const Duration(seconds: 2), (timer) async {
          if (_currentLocation == null) return;
          final user = Provider.of<UserModel>(context, listen: false);
          try {
            // Query the duo_waiting_room and get all matching rows.
            final results = await supabase
                .from('duo_waiting_room')
                .select()
                .eq('team_challenge_id', widget.challengeId)
                .neq('user_id', user.id);
            if (results is List && results.isNotEmpty) {
              final data = results.first as Map<String, dynamic>;
              final partnerLat = data['current_latitude'] as num;
              final partnerLng = data['current_longitude'] as num;
              final calculatedDistance = Geolocator.distanceBetween(
                _currentLocation!.latitude,
                _currentLocation!.longitude,
                partnerLat.toDouble(),
                partnerLng.toDouble(),
              );
              setState(() {
                _partnerDistance = calculatedDistance;
                _partnerLocation = Position.fromMap({
                  'latitude': partnerLat.toDouble(),
                  'longitude': partnerLng.toDouble(),
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                  'accuracy': 0.0,
                  'altitude': 0.0,
                  'heading': 0.0,
                  'speed': 0.0,
                  'speedAccuracy': 0.0,
                  'altitudeAccuracy': 0.0, // Required parameter
                });
              });
              // Auto-end the run if partner is more than 500m away.
              if (calculatedDistance > MAX_ALLOWED_DISTANCE) {
                _handleMaxDistanceExceeded();
              }
            }
          } catch (e) {
            debugPrint('Error checking partner location: $e');
          }
        });
  }

  void _handleMaxDistanceExceeded() {
    endRun();
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Run Ended'),
            content: const Text(
                'Your partner is more than 500m away. The run has ended.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.pushReplacementNamed(context, '/challenges');
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  void endRun() {
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot end run without valid location')),
      );
      return;
    }
    _timer?.cancel();
    _partnerPollingTimer?.cancel();
    setState(() {
      _endLocation = _currentLocation;
      _isTracking = false;
    });
    _saveRunData();
  }

  Future<void> _saveRunData() async {
    try {
      final user = Provider.of<UserModel>(context, listen: false);
      if (user.id == 0 || _startLocation == null || _endLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Missing required data to save run")),
        );
        return;
      }
      final distance = double.parse(_distanceCovered.toStringAsFixed(2));
      final startTime =
      (_startLocation!.timestamp ?? DateTime.now()).toUtc().toIso8601String();
      final endTime =
      (_endLocation!.timestamp ?? DateTime.now()).toUtc().toIso8601String();
      final routeJson = _route
          .map((point) => {
        'latitude': point.latitude,
        'longitude': point.longitude,
      })
          .toList();
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
        'journey_type': 'duo',
        // If you later accumulate duo-specific metrics, include them here.
      });
      final response = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/create_user_contribution'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: requestBody,
      );
      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        final data = responseData['data'];
        if (data != null) {
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
          Future.delayed(const Duration(seconds: 2), () {
            Navigator.pushReplacementNamed(context, '/challenges');
          });
        }
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
    _timer?.cancel();
    _locationSubscription?.cancel();
    _partnerPollingTimer?.cancel();
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
    return Scaffold(
      appBar: AppBar(title: const Text('Duo Active Run')),
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
            onMapCreated: (controller) => _mapController = controller,
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
          Positioned(
            top: 20,
            right: 20,
            child: Card(
              color: Colors.lightBlueAccent,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Partner Distance: ${_partnerDistance.toStringAsFixed(1)} m',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
              onPressed: endRun,
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
