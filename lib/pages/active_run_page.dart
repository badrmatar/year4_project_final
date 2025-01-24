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
  double _distanceCovered = 0.0;
  int _secondsElapsed = 0;
  Timer? _timer;
  bool _isTracking = false;
  bool _autoPaused = false;
  int _stillCounter = 0;
  final double _pauseThreshold = 0.5;
  final double _resumeThreshold = 1.0;

  @override
  void initState() {
    super.initState();
    _startRun();
  }

  void _startRun() async {
    final location = await _locationService.getCurrentLocation();
    if (location == null) {
      _showLocationError();
      return;
    }

    setState(() {
      _startLocation = location;
      _isTracking = true;
      _distanceCovered = 0.0;
      _secondsElapsed = 0;
      _autoPaused = false;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_autoPaused) {
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
    _timer?.cancel();
    _timer = null;
    setState(() => _isTracking = false);
    _saveRunData();
  }

  Future<void> _saveRunData() async {
    debugPrint("Run ended. Distance: $_distanceCovered meters");

    try {
      final user = Provider.of<UserModel>(context, listen: false);
      if (user.id == 0 || _startLocation == null) {
        debugPrint("Missing required data for saving");
        return;
      }

      final distance = double.parse(_distanceCovered.toStringAsFixed(2));
      final startTime = DateTime.fromMillisecondsSinceEpoch(
          _startLocation!.time!.toInt()
      ).toUtc().toIso8601String();

      final response = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/create_user_contribution'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: jsonEncode({
          'team_challenge_id': 1,
          'user_id': user.id,
          'start_time': startTime,
          'start_latitude': _startLocation!.latitude,
          'start_longitude': _startLocation!.longitude,
          'distance_covered': distance,
          'active': false,
        }),
      );

      if (response.statusCode == 201) {
        debugPrint("Successfully saved run data");
        debugPrint("Server response: ${response.body}");
      } else {
        debugPrint("Failed to save run: ${response.statusCode}");
        debugPrint("Error details: ${response.body}");
      }
    } catch (e) {
      debugPrint("Error saving run data: ${e.toString()}");
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = _distanceCovered / 1000;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Run'),
      ),
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