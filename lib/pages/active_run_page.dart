import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'dart:async';
import '/services/location_service.dart';
import 'dart:math';

class ActiveRunPage extends StatefulWidget {
  const ActiveRunPage({Key? key}) : super(key: key);

  @override
  _ActiveRunPageState createState() => _ActiveRunPageState();
}

class _ActiveRunPageState extends State<ActiveRunPage> {
  final LocationService _locationService = LocationService();

  LocationData? _startLocation;
  LocationData? _currentLocation;
  double _distanceCovered = 0.0; // meters
  int _secondsElapsed = 0;
  Timer? _timer;

  bool _isTracking = false;

  /// AUTO-PAUSE FIELDS
  bool _autoPaused = false;    // Whether we’re currently auto-paused
  int _stillCounter = 0;       // Counts consecutive seconds below speed threshold

  // Speed thresholds for pausing/resuming in m/s
  // 0.5 m/s ~ 1.8 km/h (very slow walk)
  // 1.0 m/s ~ 3.6 km/h (normal walk)
  final double _pauseThreshold = 0.5;   // Below this => increment stillCounter
  final double _resumeThreshold = 1.0;  // Above this => resume

  @override
  void initState() {
    super.initState();
    _startRun();
  }

  /// Start location & timer tracking
  void _startRun() async {
    final location = await _locationService.getCurrentLocation();
    if (location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Unable to start tracking. Check location permissions."),
        ),
      );
      return;
    }

    setState(() {
      _startLocation = location;
      _isTracking = true;
      _secondsElapsed = 0;
      _distanceCovered = 0.0;
      _autoPaused = false;
    });

    // Start the timer for elapsed time
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Only increment time if NOT auto-paused
      if (!_autoPaused) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });

    // Listen for location updates
    _locationService.trackLocation().listen((newLocation) {
      if (!_isTracking) return; // If we've ended the run, ignore further updates

      final speed = (newLocation.speed ?? 0.0).clamp(0.0, double.infinity);
      _handleAutoPauseLogic(speed);

      if (_currentLocation != null && !_autoPaused) {
        final distance = _calculateDistance(
          _currentLocation!.latitude!,
          _currentLocation!.longitude!,
          newLocation.latitude!,
          newLocation.longitude!,
        );

        // Filter out random GPS jumps <3m
        if (distance > 3.0) {
          setState(() {
            _distanceCovered += distance;
          });
        }
      }

      // Update current location after distance check
      setState(() {
        _currentLocation = newLocation;
      });
    });
  }

  /// Simple auto-pause logic based on speed
  /// If speed < _pauseThreshold for 5 consecutive seconds => autoPause
  /// If speed > _resumeThreshold => autoResume immediately
  void _handleAutoPauseLogic(double speed) {
    if (_autoPaused) {
      // Attempt to resume if speed is above the resume threshold
      if (speed > _resumeThreshold) {
        setState(() {
          _autoPaused = false;
          _stillCounter = 0; // reset
        });
      }
    } else {
      // If not paused, check if speed is below pause threshold
      if (speed < _pauseThreshold) {
        _stillCounter++;
        if (_stillCounter >= 5) {
          // 5 consecutive seconds => pause
          setState(() {
            _autoPaused = true;
          });
        }
      } else {
        // Speed above threshold => keep active
        _stillCounter = 0;
      }
    }
  }

  /// Calculate distance in meters (Haversine formula)
  double _calculateDistance(double startLat, double startLng,
      double endLat, double endLng) {
    const earthRadius = 6371000.0; // in meters
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

    setState(() {
      _isTracking = false;
    });
    _saveRunData();
  }

  Future<void> _saveRunData() async {
    debugPrint("Run ended. Distance covered: $_distanceCovered meters");
    // TODO: Implement backend logic (Supabase) if needed
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
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
            // Time & Distance
            Text('Time Elapsed: ${_formatTime(_secondsElapsed)}'),
            Text('Distance Covered: ${distanceKm.toStringAsFixed(2)} km'),
            // AutoPaused status
            const SizedBox(height: 8),
            if (_autoPaused)
              const Text(
                'Auto-Paused',
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),
            const SizedBox(height: 16),

            // End Run button
            ElevatedButton(
              onPressed: _endRun,
              child: const Text('End Run'),
            ),
          ],
        ),
      ),
    );
  }
}
