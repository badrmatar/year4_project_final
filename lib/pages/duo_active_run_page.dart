import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user.dart';
import '../mixins/run_tracking_mixin.dart';
import '../services/ios_location_bridge.dart';
import '../constants/app_constants.dart';

/// A page that displays and tracks a duo run with two participants.
///
/// This page shows both the user's and their partner's location in real-time,
/// tracks the distance between them, and ends the run if they exceed the
/// maximum allowed distance.
class DuoActiveRunPage extends StatefulWidget {
  /// The challenge ID this duo run is associated with.
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
  StreamSubscription? _iosLocationSubscription;
  StreamSubscription<Position>? _customLocationSubscription;

  // Partner route tracking
  final List<LatLng> _partnerRoutePoints = [];
  Polyline _partnerRoutePolyline = const Polyline(
    polylineId: PolylineId('partner_route'),
    color: AppConstants.partnerRouteColor,
    width: 5,
    points: [],
  );

  // Duo run status variables:
  bool _hasEnded = false;
  bool _isRunning = true;
  bool _isInitializing = true;

  // Create circles for user and partner instead of markers
  final Map<CircleId, Circle> _circles = {};

  final supabase = Supabase.instance.client;

  // iOS bridge for background location
  final IOSLocationBridge _iosBridge = IOSLocationBridge();

  @override
  void initState() {
    super.initState();

    // Initialize iOS location bridge if on iOS
    if (Platform.isIOS) {
      _initializeIOSLocationBridge();
    }

    _initializeRun();
    _startPartnerPolling();
  }

  /// Initializes the iOS location bridge for background tracking.
  Future<void> _initializeIOSLocationBridge() async {
    await _iosBridge.initialize();
    await _iosBridge.startBackgroundLocationUpdates();

    _iosLocationSubscription = _iosBridge.locationStream.listen((position) {
      if (!mounted || _hasEnded) return;

      print("iOS location update received: ${position.latitude}, ${position.longitude}, accuracy: ${position.accuracy}");

      // Update current location if better accuracy or first update
      if (currentLocation == null || position.accuracy < currentLocation!.accuracy) {
        setState(() {
          currentLocation = position;
        });

        // Update the partner tracking system
        _updateDuoWaitingRoom(position);

        // IMPORTANT: Process the location for distance and route drawing
        final currentPoint = LatLng(position.latitude, position.longitude);

        // Add to route points
        setState(() {
          routePoints.add(currentPoint);
          routePolyline = Polyline(
            polylineId: const PolylineId('route'),
            color: AppConstants.selfRouteColor,
            width: 5,
            points: routePoints,
          );
        });

        // Calculate distance if we have a previous point
        if (lastRecordedLocation != null) {
          final segmentDistance = calculateDistance(
            lastRecordedLocation!.latitude,
            lastRecordedLocation!.longitude,
            currentPoint.latitude,
            currentPoint.longitude,
          );

          // Only add distance if segment is greater than 15 meters
          if (segmentDistance > 15.0) {
            print("iOS: Adding distance segment: $segmentDistance meters");
            setState(() {
              distanceCovered += segmentDistance;
              lastRecordedLocation = currentPoint;
            });
          }
        } else {
          // First point
          lastRecordedLocation = currentPoint;
        }

        // Move map camera
        mapController?.animateCamera(CameraUpdate.newLatLng(currentPoint));
      }
    }, onError: (error) {
      print("iOS location bridge error: $error");
    });
  }

  /// Sets up custom location handling for tracking distance.
  void _setupCustomLocationHandling() {
    _customLocationSubscription = locationService.trackLocation().listen((position) {
      if (!isTracking || _hasEnded) return;

      final currentPoint = LatLng(position.latitude, position.longitude);

      // If we have a previous location, calculate distance
      if (lastRecordedLocation != null) {
        // Calculate distance using the mixin's method
        final segmentDistance = calculateDistance(
          lastRecordedLocation!.latitude,
          lastRecordedLocation!.longitude,
          currentPoint.latitude,
          currentPoint.longitude,
        );

        // Handle auto-pause logic (from the mixin)
        final speed = position.speed >= 0 ? position.speed : 0.0;
        if (autoPaused) {
          if (speed > AppConstants.kResumeThreshold) {
            setState(() {
              autoPaused = false;
              stillCounter = 0;
            });
          }
        } else {
          if (speed < AppConstants.kPauseThreshold) {
            stillCounter++;
            if (stillCounter >= 5) {
              setState(() => autoPaused = true);
            }
          } else {
            stillCounter = 0;
          }
        }

        // Update distance only if not paused and segmentDistance > 17 meters
        if (!autoPaused && segmentDistance > 15) {
          setState(() {
            distanceCovered += segmentDistance;
            lastRecordedLocation = currentPoint;
          });
        }
      } else {
        // First location update: initialize lastRecordedLocation
        setState(() {
          lastRecordedLocation = currentPoint;
        });
      }

      // Update route visualization
      setState(() {
        currentLocation = position;
        routePoints.add(currentPoint);
        routePolyline = Polyline(
          polylineId: const PolylineId('route'),
          color: AppConstants.selfRouteColor,
          width: 5,
          points: routePoints,
        );
      });

      // Update duo waiting room with new location
      _updateDuoWaitingRoom(position);

      // Move camera to follow user
      mapController?.animateCamera(CameraUpdate.newLatLng(currentPoint));
    });
  }


  /// Starts polling for partner's status at regular intervals.
  void _startPartnerPolling() {
    _partnerPollingTimer?.cancel();
    _partnerPollingTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) async {
          if (!mounted || _hasEnded) {
            timer.cancel();
            return;
          }
          await _pollPartnerStatus();
        });
  }

  /// Converts a numeric distance to a human-readable distance group.
  String _getDistanceGroup(double distance) {
    if (distance < 100) return "<100";
    if (distance < 200) return "100+";
    if (distance < 300) return "200+";
    if (distance < 400) return "300+";
    if (distance < 500) return "400+";
    return "500+";
  }

  /// Helper method to add or update the self circle on the map.
  /// Not used since we're relying on the default Google Maps blue dot.
  void _addSelfCircle(Position position) {
    // We're not adding a custom circle for self anymore
    // We'll rely on the default blue location dot from Google Maps
  }

  /// Adds or updates the partner's circle on the map and adds to their route.
  void _addPartnerCircle(Position position) {
    final circleId = CircleId('partner');
    final circle = Circle(
      circleId: circleId,
      center: LatLng(position.latitude, position.longitude),
      radius: 15, // Larger radius similar to the default Google Maps blue dot
      fillColor: Colors.green.withOpacity(0.5), // Translucent green
      strokeColor: Colors.white, // White border
      strokeWidth: 2,
    );

    setState(() {
      _circles[circleId] = circle;

      // Add the partner's position to their route
      final partnerPoint = LatLng(position.latitude, position.longitude);
      if (_partnerRoutePoints.isEmpty ||
          _partnerRoutePoints.last != partnerPoint) {
        _partnerRoutePoints.add(partnerPoint);
        _partnerRoutePolyline = Polyline(
          polylineId: const PolylineId('partner_route'),
          color: AppConstants.partnerRouteColor,
          width: 5,
          points: _partnerRoutePoints,
        );
      }
    });
  }

  /// Updates the user's location in the duo waiting room database.
  Future<void> _updateDuoWaitingRoom(Position position) async {
    if (_hasEnded) return;

    final user = Provider.of<UserModel>(context, listen: false);
    try {
      await supabase
          .from('duo_waiting_room')
          .update({
        'current_latitude': position.latitude,
        'current_longitude': position.longitude,
        'last_update': DateTime.now().toIso8601String(),
      })
          .match({
        'team_challenge_id': widget.challengeId,
        'user_id': user.id,
      });
    } catch (e) {
      debugPrint('Error updating duo waiting room: $e');
    }
  }

  /// Polls for the partner's current location and updates the UI.
  ///
  /// This method fetches the partner's location from the database,
  /// updates their marker on the map, and checks if the maximum
  /// distance between partners has been exceeded.
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

        // Create a Position object for the partner
        final partnerPosition = Position(
          latitude: partnerLat.toDouble(),
          longitude: partnerLng.toDouble(),
          timestamp: DateTime.now(),
          accuracy: 10.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          floor: null,
          altitudeAccuracy: 0.0,
          headingAccuracy: 0.0,
        );

        // Add partner circle
        _addPartnerCircle(partnerPosition);

        setState(() {
          _partnerDistance = calculatedDistance;
          _partnerLocation = partnerPosition;
        });

        if (calculatedDistance > AppConstants.kMaxAllowedDistance && !_hasEnded) {
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
      debugPrint('Error in partner polling: $e. Challenge ID: ${widget.challengeId}');
    }
  }

  /// Ends the run when the partner has ended it.
  Future<void> _endRunDueToPartner() async {
    await _endRun(
      reason: 'partner_ended',
      notifyPartner: false,
      message: "Your teammate has ended the run. Run completed.",
    );
  }

  /// Initializes the run by getting the initial position and setting up tracking.
  Future<void> _initializeRun() async {
    try {
      final initialPosition = await locationService.getCurrentLocation();
      if (initialPosition != null && mounted) {
        setState(() {
          currentLocation = initialPosition;
          _isInitializing = false;
        });

        // Update location in waiting room
        _updateDuoWaitingRoom(initialPosition);

        // Start tracking using the mixin
        startRun(initialPosition);

        // Add custom location handling to properly update distance
        _setupCustomLocationHandling();
      }

      // Fallback timer if initialization takes too long
      Timer(const Duration(seconds: 30), () {
        if (_isInitializing && mounted && currentLocation != null) {
          setState(() {
            _isInitializing = false;
          });
          startRun(currentLocation!);
          _setupCustomLocationHandling();
        }
      });
    } catch (e) {
      debugPrint('Error initializing run: $e');
    }
  }

  /// Handles the case when maximum distance between partners is exceeded.
  Future<void> _handleMaxDistanceExceeded() async {
    await _endRun(
      reason: 'max_distance_exceeded',
      notifyPartner: false,
      message: "Distance between teammates exceeded 500m. The run has ended.",
    );

    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('Run Ended'),
            content: const Text(
                'Distance between teammates exceeded 500m. The run has ended.'),
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
    }
  }

  /// Manually ends the run when the user presses the end button.
  Future<void> _endRunManually() async {
    await _endRun(
      reason: 'manual',
      notifyPartner: true,
      message: "Run ended successfully. Your teammate will be notified.",
    );
  }

  /// Ends the run and saves all run data.
  ///
  /// This method handles the common logic for ending a run regardless
  /// of the reason (manual end, partner ended, or maximum distance exceeded).
  /// It cancels all subscriptions, saves the run data, and updates the UI.
  ///
  /// Parameters:
  /// - reason: A string describing why the run ended (for logging)
  /// - notifyPartner: Whether to notify the partner that the run has ended
  /// - message: The message to show to the user
  Future<void> _endRun({
    required String reason,
    bool notifyPartner = false,
    String? message,
  }) async {
    if (_hasEnded) return;

    final user = Provider.of<UserModel>(context, listen: false);

    try {
      // Set flags
      _hasEnded = true;
      isTracking = false;

      // Cancel all subscriptions and timers
      runTimer?.cancel();
      locationSubscription?.cancel();
      _customLocationSubscription?.cancel();
      _partnerPollingTimer?.cancel();

      // Clean up iOS resources if needed
      if (Platform.isIOS) {
        _iosLocationSubscription?.cancel();
        await _iosBridge.stopBackgroundLocationUpdates();
      }

      // Save the run data
      await _saveRunData();

      // Update database records
      final updatePromises = [
        supabase.from('user_contributions').update({
          'active': false,
        }).match({
          'team_challenge_id': widget.challengeId,
          'user_id': user.id,
        })
      ];

      if (notifyPartner) {
        updatePromises.add(
            supabase.from('duo_waiting_room').update({
              'has_ended': true,
            }).match({
              'team_challenge_id': widget.challengeId,
              'user_id': user.id,
            })
        );
      }

      await Future.wait(updatePromises);

      // Notify user and navigate away
      if (mounted) {
        setState(() => _isRunning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message ?? "Run ended."),
            duration: AppConstants.kDefaultSnackbarDuration,
          ),
        );
        await Future.delayed(AppConstants.kNavigationDelay);
        Navigator.pushReplacementNamed(context, '/challenges');
      }
    } catch (e) {
      debugPrint('Error ending run ($reason): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error ending run. Please try again.")),
        );
      }
    }
  }

  /// Saves the run data to the server.
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
      final startTime = (startLocation!.timestamp ??
          DateTime.now().subtract(Duration(seconds: secondsElapsed)))
          .toUtc()
          .toIso8601String();
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

      if (response.statusCode != 201 && mounted) {
        throw Exception("Failed to save run: ${response.body}");
      }
    } catch (e) {
      debugPrint('Error saving run data: $e. Challenge ID: ${widget.challengeId}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("An error occurred: ${e.toString()}")),
        );
      }
    }
  }

  /// Formats seconds into a MM:SS string.
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
    _customLocationSubscription?.cancel();
    _partnerPollingTimer?.cancel();

    // Clean up iOS resources
    if (Platform.isIOS) {
      _iosLocationSubscription?.cancel();
      _iosBridge.dispose();
    }

    mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return _buildInitializingScreen();
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _buildMap(),
          _buildRunMetricsCard(),
          _buildPartnerDistanceCard(),
          if (autoPaused) _buildAutoPausedIndicator(),
          _buildEndRunButton(),
        ],
      ),
    );
  }

  /// Builds the loading screen shown while waiting for GPS.
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

  /// Builds the app bar for the run page.
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Duo Active Run'),
      actions: [
        IconButton(
          icon: const Icon(Icons.stop),
          onPressed: _endRunManually,
        ),
      ],
    );
  }

  /// Builds the Google Map showing both runners.
  Widget _buildMap() {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: currentLocation != null
            ? LatLng(currentLocation!.latitude, currentLocation!.longitude)
            : const LatLng(37.4219999, -122.0840575),
        zoom: 16,
      ),
      myLocationEnabled: true, // Show default blue dot
      myLocationButtonEnabled: true,
      polylines: {routePolyline, _partnerRoutePolyline},
      circles: Set<Circle>.of(_circles.values),
      onMapCreated: (controller) => mapController = controller,
    );
  }

  /// Builds the card showing time and distance.
  Widget _buildRunMetricsCard() {
    final distanceKm = distanceCovered / 1000;

    return Positioned(
      top: AppConstants.kMapMarginTop,
      left: AppConstants.kMapMarginSide,
      child: Card(
        color: Colors.white.withOpacity(0.9),
        child: Padding(
          padding: EdgeInsets.all(AppConstants.kCardPadding),
          child: Column(
            children: [
              Text(
                'Time: ${_formatTime(secondsElapsed)}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Distance: ${distanceKm.toStringAsFixed(2)} km',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the card showing distance to partner.
  Widget _buildPartnerDistanceCard() {
    return Positioned(
      top: AppConstants.kMapMarginTop,
      right: AppConstants.kMapMarginSide,
      child: Card(
        color: Colors.lightBlueAccent.withOpacity(0.9),
        child: Padding(
          padding: EdgeInsets.all(AppConstants.kCardPadding),
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
    );
  }

  /// Builds the indicator shown when the run is auto-paused.
  Widget _buildAutoPausedIndicator() {
    return Positioned(
      top: 90,
      left: AppConstants.kMapMarginSide,
      child: Card(
        color: Colors.redAccent.withOpacity(0.8),
        child: Padding(
          padding: EdgeInsets.all(AppConstants.kCardPadding),
          child: const Text(
            'Auto-Paused',
            style: TextStyle(fontSize: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// Builds the button to end the run.
  Widget _buildEndRunButton() {
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Center(
        child: ElevatedButton(
          onPressed: _endRunManually,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
          ),
          child: const Text(
            'End Run',
            style: TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}