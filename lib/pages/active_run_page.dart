import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../models/user.dart';
import '../services/location_service.dart';

class ActiveRunPage extends StatefulWidget {
  final Position initialPosition;
  final String journeyType;
  final int challengeId;

  const ActiveRunPage({
    Key? key,
    required this.initialPosition,
    required this.journeyType,
    required this.challengeId,
  }) : super(key: key);

  @override
  ActiveRunPageState createState() => ActiveRunPageState();
}

class ActiveRunPageState extends State<ActiveRunPage> {
  final LocationService _locationService = LocationService();
  GoogleMapController? _mapController;

  // Run state variables
  bool _isTracking = false;
  bool _autoPaused = false;
  bool _manuallyPaused = false;
  int _secondsElapsed = 0;
  double _distanceCovered = 0.0;
  double _currentSpeed = 0.0;

  // Path variables
  List<LatLng> _routePoints = [];
  Set<Polyline> _polylines = {};
  Timer? _runTimer;

  // Auto-pause detection
  int _stillCount = 0;
  static const _pauseThreshold = 0.5;  // m/s
  static const _resumeThreshold = 1.0;

  // Location subscription
  StreamSubscription<Position>? _locationSubscription;
  Map<String, dynamic>? _runSummary;

  LatLng? _lastRecordedLocation;
  final Map<MarkerId, Marker> _markers = {};
  @override
  void initState() {
    super.initState();
    _initializeRun();
  }

  Future<void> _initializeRun() async {
    // Start with initial position
    _addRoutePoint(LatLng(
        widget.initialPosition.latitude,
        widget.initialPosition.longitude
    ));

    // Start run timer
    _runTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_autoPaused && !_manuallyPaused && mounted) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });

    // Start tracking
    _startLocationTracking();

    setState(() {
      _isTracking = true;
      _lastRecordedLocation = LatLng(
          widget.initialPosition.latitude,
          widget.initialPosition.longitude
      );
    });
  }

  void _startLocationTracking() {
    //loc setting stup
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
    _locationSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings
    ).listen(_handleNewLocation);
  }

  void _handleNewLocation(Position position) {
    if (!_isTracking || _manuallyPaused) return;
    final currentPoint = LatLng(position.latitude, position.longitude);
    if (_lastRecordedLocation != null) {
      final segmentDistance = _calculateDistance(
        _lastRecordedLocation!.latitude,
        _lastRecordedLocation!.longitude,
        currentPoint.latitude,
        currentPoint.longitude,
      );

      // Adjust speed
      final speed = position.speed >= 0 ? position.speed : 0.0;
      if (segmentDistance > 15) {
        setState(() {
          _distanceCovered += segmentDistance;
          _currentSpeed = speed;

          // Update last recorded location
          _lastRecordedLocation = currentPoint;
        });
      }
    }

    // Add point to route and move camera
    _addRoutePoint(currentPoint);
    _animateToUser(position);
  }


  void _addRoutePoint(LatLng point) {
    setState(() {
      _routePoints.add(point);

      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          color: Colors.blue,
          width: 5,
          points: _routePoints,
        ),
      };
    });
  }

  void _animateToUser(Position position) {
    _mapController?.animateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude))
    );
  }


  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000.0; // meters
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);

    final double a =
        sin(dLat / 2) * sin(dLat / 2) +
            cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
                sin(dLon / 2) * sin(dLon / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180.0);
  }

  void _togglePause() {
    setState(() {
      _manuallyPaused = !_manuallyPaused;
    });
  }

  Future<void> _endRunAndSave() async {
    if (_routePoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot end run without any location data')),
      );
      return;
    }

    // Stop tracking
    _locationSubscription?.cancel();
    _runTimer?.cancel();

    setState(() {
      _isTracking = false;
    });

    // loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Saving your run..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      await _saveRunData();

      // loading dialog pop
      if (mounted) Navigator.of(context).pop();
      Navigator.of(context).pushReplacementNamed('/challenges');
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving run: ${e.toString()}")),
        );
      }
    }
  }

  Future<void> _saveRunData() async {
    final user = Provider.of<UserModel>(context, listen: false);

    if (user.id == 0 || _routePoints.isEmpty) {
      throw Exception("Missing required data to save run");
    }

    final startPoint = _routePoints.first;
    final endPoint = _routePoints.last;
    final distance = double.parse(_distanceCovered.toStringAsFixed(2));
    final startTime = widget.initialPosition.timestamp?.toUtc().toIso8601String()
        ?? DateTime.now().subtract(Duration(seconds: _secondsElapsed)).toUtc().toIso8601String();
    final endTime = DateTime.now().toUtc().toIso8601String();

    final routeJson = _routePoints
        .map((point) => {'latitude': point.latitude, 'longitude': point.longitude})
        .toList();

    final requestBody = {
      'user_id': user.id,
      'start_time': startTime,
      'end_time': endTime,
      'start_latitude': startPoint.latitude,
      'start_longitude': startPoint.longitude,
      'end_latitude': endPoint.latitude,
      'end_longitude': endPoint.longitude,
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
        final data = jsonDecode(response.body);

        setState(() {
          _runSummary = {
            'distanceKm': distance / 1000,
            'durationSeconds': _secondsElapsed,
            'completed': data['data']['challenge_completed'] ?? false,
            'teamProgress': data['data']['total_distance_km'] ?? 0,
            'requiredDistance': data['data']['required_distance_km'] ?? 0,
          };
        });
      } else {
        throw Exception("Failed to save run: ${response.body}");
      }
    } catch (e) {
      throw Exception("An error occurred: ${e.toString()}");
    }
  }

  void _showRunSummary() {
    if (_runSummary == null) return;

    // Format duration
    final duration = Duration(seconds: _secondsElapsed);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    final durationText = hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    // Format distance
    final distanceText = '${(_runSummary!['distanceKm'] as double).toStringAsFixed(2)} km';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'Run Completed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_runSummary!['completed'] == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text(
                        '🎉 Challenge Complete! 🎉',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Stats
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Map preview of the run (if mapController is available)
                      if (_mapController != null)
                        Container(
                          height: 200,
                          margin: const EdgeInsets.only(bottom: 20),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: _routePoints.isNotEmpty
                                    ? _routePoints[_routePoints.length ~/ 2]
                                    : LatLng(
                                    widget.initialPosition.latitude,
                                    widget.initialPosition.longitude
                                ),
                                zoom: 15,
                              ),
                              polylines: _polylines,
                              zoomControlsEnabled: false,
                              myLocationEnabled: false,
                              myLocationButtonEnabled: false,
                              onMapCreated: (controller) {},
                            ),
                          ),
                        ),

                      // Primary stats grid
                      GridView.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 15,
                        crossAxisSpacing: 15,
                        childAspectRatio: 1.5,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildStatCard('Distance', distanceText, Icons.straighten),
                          _buildStatCard('Duration', durationText, Icons.timer),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Challenge progress
                      const Text(
                        'Challenge Progress',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),

                      const SizedBox(height: 10),

                      LinearProgressIndicator(
                        value: _runSummary!['teamProgress'] / _runSummary!['requiredDistance'],
                        minHeight: 20,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(_runSummary!['completed'] ? Colors.green : Colors.blue),
                        borderRadius: BorderRadius.circular(10),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        '${(_runSummary!["teamProgress"] as double).toStringAsFixed(2)}/${_runSummary!["requiredDistance"].toStringAsFixed(2)} km',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),

                      const SizedBox(height: 20),
                      Center(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop(); // Close summary
                            Navigator.of(context).pushReplacementNamed('/challenges');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                          ),
                          child: const Text(
                            'Back to Challenges',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.blue, size: 16),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
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
    _locationSubscription?.cancel();
    _runTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = _distanceCovered / 1000;

    return Scaffold(
      body: Stack(
        children: [
          // Maip full screen
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: LatLng(
                widget.initialPosition.latitude,
                widget.initialPosition.longitude,
              ),
              zoom: 16,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            polylines: _polylines,
            markers: Set<Marker>.of(_markers.values),
            onMapCreated: (controller) => _mapController = controller,
          ),

          // Status bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: MediaQuery.of(context).padding.top,
              color: Colors.black.withOpacity(0.5),
            ),
          ),

          // back button
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.black.withOpacity(0.5),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('End Run?'),
                          content: const Text('Are you sure you want to end your run?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _endRunAndSave();
                              },
                              child: const Text('End Run'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Expanded(
                    child: Text(
                      'Active Run',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _manuallyPaused ? Icons.play_arrow : Icons.pause,
                      color: Colors.white,
                    ),
                    onPressed: _togglePause,
                  ),
                ],
              ),
            ),
          ),

          // Stats
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status indicators
                  if (_autoPaused || _manuallyPaused)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _manuallyPaused ? Colors.orange : Colors.red,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _manuallyPaused ? 'PAUSED' : 'AUTO-PAUSED',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('DISTANCE', '${distanceKm.toStringAsFixed(2)} km'),
                      _buildStatItem('TIME', _formatTime(_secondsElapsed)),
                    ],
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _endRunAndSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        'END RUN',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}