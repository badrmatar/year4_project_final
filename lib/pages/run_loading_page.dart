import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import 'active_run_page.dart';

class RunLoadingPage extends StatefulWidget {
  final String journeyType;
  final int challengeId;
  const RunLoadingPage({
    Key? key,
    required this.journeyType,
    required this.challengeId,
  }) : super(key: key);

  @override
  _RunLoadingPageState createState() => _RunLoadingPageState();
}

class _RunLoadingPageState extends State<RunLoadingPage> {
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  String _accuracyDisplay = "Waiting for GPS fix...";
  late DateTime _startTime;

  // Configuration: must wait at least 3 seconds and get a reading under 50m.
  final Duration _minWait = const Duration(seconds: 3);
  final double _targetAccuracy = 50.0;

  @override
  void initState() {
    super.initState();
    // Reset state for a new run.
    _startTime = DateTime.now();
    _subscribeForFix();
    // Fallback: after 30 seconds, if no fix, use latest available reading.
    Timer(const Duration(seconds: 30), () {
      if (_currentPosition != null) {
        _positionSubscription?.cancel();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveRunPage(
              initialPosition: _currentPosition!,
              journeyType: widget.journeyType,
              challengeId: widget.challengeId,
            ),
          ),
        );
      }
    });
  }

  void _subscribeForFix() {
    _positionSubscription = _locationService.trackLocation().listen((position) {
      // Only consider readings acquired after the loading page started.
      if (position.timestamp == null || !position.timestamp!.isAfter(_startTime)) {
        return;
      }
      setState(() {
        _currentPosition = position;
        _accuracyDisplay =
        "Current Accuracy: ${position.accuracy.toStringAsFixed(1)}m";
      });
      final elapsed = DateTime.now().difference(_startTime);
      if (elapsed >= _minWait && position.accuracy < _targetAccuracy) {
        // Good fix obtained. Cancel subscription and navigate to the run page.
        _positionSubscription?.cancel();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ActiveRunPage(
              initialPosition: position,
              journeyType: widget.journeyType,
              challengeId: widget.challengeId,
            ),
          ),
        );
      }
    }, onError: (error) {
      setState(() {
        _accuracyDisplay = "Error: $error";
      });
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Acquiring GPS Fix')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.green),
            const SizedBox(height: 20),
            Text(
              _accuracyDisplay,
              style: const TextStyle(color: Colors.white, fontSize: 20),
            ),
            const SizedBox(height: 10),
            if (_currentPosition != null)
              Text(
                'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}\nLng: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
