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
import '../mixins/run_tracking_mixin.dart';

class DuoActiveRunPage extends StatefulWidget {
  final int challengeId;

  const DuoActiveRunPage({Key? key, required this.challengeId})
      : super(key: key);

  @override
  _DuoActiveRunPageState createState() => _DuoActiveRunPageState();
}

class _DuoActiveRunPageState extends State<DuoActiveRunPage>
    with RunTrackingMixin {
  // Duo-specific partner tracking variables:
  Position? _partnerLocation;
  double _partnerDistance = 0.0;
  Timer? _partnerPollingTimer;
  static const double MAX_ALLOWED_DISTANCE = 5000; // in meters

  // Duo run status variables:
  bool _hasEnded = false;
  bool _isRunning = true;
  bool _isInitializing = true;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _initializeRun();
    _startPartnerPolling();
  }

  void _startPartnerPolling() {
    _partnerPollingTimer?.cancel();
    _partnerPollingTimer =
        Timer.periodic(const Duration(seconds: 2), (timer) async {
          if (!mounted || _hasEnded) {
            timer.cancel();
            return;
          }
          await _pollPartnerStatus();
        });
  }

  String _getDistanceGroup(double distance) {
    if (distance < 100) return "<100";
    if (distance < 200) return "100+";
    if (distance < 300) return "200+";
    if (distance < 400) return "300+";
    if (distance < 500) return "400+";
    return "500+";
  }

  Future<void> _pollPartnerStatus() async {
    if (currentLocation == null || !mounted) return;
    try {
      final user = Provider.of<UserModel>(context, listen: false);
      final results = await supabase
          .from('duo_waiting_room')
          .select('has_ended, current_latitude, current_longitude')
          .eq('team_challenge_id', widget.challengeId)
          .neq('user_id', user.id);

      if (!mounted) return;
      if (results is List && results.isNotEmpty) {
        final data = results.first as Map<String, dynamic>;
        // If partner ended run, end our run
        if (data['has_ended'] == true) {
          await _endRunDueToPartner();
          return;
        }
        final partnerLat = data['current_latitude'] as num;
        final partnerLng = data['current_longitude'] as num;
        final calculatedDistance = Geolocator.distanceBetween(
          currentLocation!.latitude,
          currentLocation!.longitude,
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
            'altitudeAccuracy': 0.0,
          });
        });
        if (calculatedDistance > MAX_ALLOWED_DISTANCE && !_hasEnded) {
          await supabase.from('duo_waiting_room').update({
            'has_ended': true,
          }).match({
            'team_challenge_id': widget.challengeId,
            'user_id': user.id,
          });
          await _handleMaxDistanceExceeded();
          return;
        }
      }
    } catch (e) {
      debugPrint('Error in partner polling: $e');
    }
  }

  Future<void> _endRunDueToPartner() async {
    if (_hasEnded) return;
    final user = Provider.of<UserModel>(context, listen: false);
    try {
      _hasEnded = true;
      isTracking = false;
      runTimer?.cancel();
      locationSubscription?.cancel();
      _partnerPollingTimer?.cancel();

      await _saveRunData();
      await supabase.from('user_contributions').update({
        'active': false,
      }).match({
        'team_challenge_id': widget.challengeId,
        'user_id': user.id,
      });

      if (mounted) {
        setState(() {
          _isRunning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Your teammate has ended the run. Run completed."),
            duration: Duration(seconds: 3),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        Navigator.pushReplacementNamed(context, '/challenges');
      }
    } catch (e) {
      debugPrint('Error ending run due to partner: $e');
    }
  }

  Future<void> _initializeRun() async {
    try {
      final initialPosition = await locationService.getCurrentLocation();
      if (initialPosition != null && mounted) {
        setState(() {
          currentLocation = initialPosition;
          _isInitializing = false;
        });
        startRun(initialPosition); // Using mixin's method
      }
      // Fallback timer
      Timer(const Duration(seconds: 30), () {
        if (_isInitializing && mounted && currentLocation != null) {
          setState(() {
            _isInitializing = false;
          });
          startRun(currentLocation!);
        }
      });
    } catch (e) {
      debugPrint('Error initializing run: $e');
    }
  }

  Future<void> _handleMaxDistanceExceeded() async {
    if (_hasEnded) return;
    isTracking = false;
    _hasEnded = true;
    runTimer?.cancel();
    locationSubscription?.cancel();
    _partnerPollingTimer?.cancel();
    final user = Provider.of<UserModel>(context, listen: false);
    try {
      await _saveRunData();
      await supabase.from('user_contributions').update({
        'active': false,
      }).match({
        'team_challenge_id': widget.challengeId,
        'user_id': user.id,
      });
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              title: const Text('Run Ended'),
              content: const Text('Distance between teammates exceeded 500m. The run has ended.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        await Future.delayed(const Duration(seconds: 2));
        Navigator.pushReplacementNamed(context, '/challenges');
      }
    } catch (e) {
      debugPrint('Error handling max distance exceeded: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error ending run due to max distance.")),
        );
      }
    }
  }

  Future<void> _endRunManually() async {
    if (_hasEnded) return;
    final user = Provider.of<UserModel>(context, listen: false);
    try {
      _hasEnded = true;
      isTracking = false;
      runTimer?.cancel();
      locationSubscription?.cancel();
      _partnerPollingTimer?.cancel();
      await _saveRunData();
      await Future.wait([
        supabase.from('user_contributions').update({
          'active': false,
        }).match({
          'team_challenge_id': widget.challengeId,
          'user_id': user.id,
        }),
        supabase.from('duo_waiting_room').update({
          'has_ended': true,
        }).match({
          'team_challenge_id': widget.challengeId,
          'user_id': user.id,
        }),
      ]);
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Run ended successfully. Your teammate will be notified."),
            duration: Duration(seconds: 3),
          ),
        );
        await Future.delayed(const Duration(seconds: 2));
        Navigator.pushReplacementNamed(context, '/challenges');
      }
    } catch (e) {
      debugPrint('Error ending run: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error ending run. Please try again.")),
        );
      }
    }
  }

  Future<void> _saveRunData() async {
    try {
      final user = Provider.of<UserModel>(context, listen: false);
      if (user.id == 0 || startLocation == null || currentLocation == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Missing required data to save run")),
          );
        }
        return;
      }
      final distance = double.parse(distanceCovered.toStringAsFixed(2));
      final startTime = (startLocation!.timestamp ?? DateTime.now()).toUtc().toIso8601String();
      final endTime = DateTime.now().toUtc().toIso8601String();
      final routeJson = routePoints
          .map((point) => {'latitude': point.latitude, 'longitude': point.longitude})
          .toList();
      final requestBody = jsonEncode({
        'user_id': user.id,
        'start_time': startTime,
        'end_time': endTime,
        'start_latitude': startLocation!.latitude,
        'start_longitude': startLocation!.longitude,
        'end_latitude': currentLocation!.latitude,
        'end_longitude': currentLocation!.longitude,
        'distance_covered': distance,
        'route': routeJson,
        'journey_type': 'duo',
      });

      final response = await http.post(
        Uri.parse('${dotenv.env['SUPABASE_URL']}/functions/v1/create_user_contribution'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${dotenv.env['BEARER_TOKEN']}',
        },
        body: requestBody,
      );

      if (response.statusCode == 201 && mounted) {
        final responseData = jsonDecode(response.body);
        final data = responseData['data'];
        if (data != null) {
          if (data['challenge_completed'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
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
              ),
            );
          } else {
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
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save run: ${response.body}")),
        );
      }
    } catch (e) {
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

  @override
  void dispose() {
    isTracking = false;
    _hasEnded = true;
    runTimer?.cancel();
    locationSubscription?.cancel();
    _partnerPollingTimer?.cancel();
    mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = distanceCovered / 1000;
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
                  color: currentLocation != null ? Colors.green : Colors.white,
                ),
                if (currentLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text(
                      'Accuracy: ${currentLocation!.accuracy.toStringAsFixed(1)} meters',
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
      appBar: AppBar(
        title: const Text('Duo Active Run'),
        actions: [
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: _endRunManually,
          ),
        ],
      ),
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
            onMapCreated: (controller) => mapController = controller,
          ),
          Positioned(
            top: 20,
            left: 20,
            child: Card(
              color: Colors.white.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
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
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 20,
            right: 20,
            child: Card(
              color: Colors.lightBlueAccent.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Partner Distance: ${_getDistanceGroup(_partnerDistance)} m',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          if (autoPaused)
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
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: _endRunManually,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: const Text(
                  'End Run',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
