// lib/pages/duo_waiting_room.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';
import '../services/location_service.dart';

class DuoWaitingRoom extends StatefulWidget {
  /// Use a valid team challenge ID that exists in the team_challenges table.
  final int teamChallengeId;

  const DuoWaitingRoom({
    Key? key,
    required this.teamChallengeId,
  }) : super(key: key);

  @override
  State<DuoWaitingRoom> createState() => _DuoWaitingRoomState();
}

class _DuoWaitingRoomState extends State<DuoWaitingRoom> {
  final LocationService _locationService = LocationService();
  final supabase = Supabase.instance.client;

  StreamSubscription<Position>? _locationSubscription;
  Timer? _teammateCheckTimer;
  Timer? _readyPollingTimer;
  Position? _currentLocation;
  Map<String, dynamic>? _teammateInfo;
  double? _teammateDistance;
  bool _isInitializing = true;
  static const double REQUIRED_PROXIMITY = 200; // in meters

  // Local flag to indicate that the user has pressed "Ready"
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    // Get the initial location.
    final initialPosition = await _locationService.getCurrentLocation();
    if (initialPosition != null) {
      setState(() {
        _currentLocation = initialPosition;
        _isInitializing = false;
      });
      _startLocationTracking();
      _createWaitingRoomEntry();
      _startReadyPolling();
    }
  }

  void _startLocationTracking() {
    // Listen for location changes.
    _locationSubscription = _locationService.trackLocation().listen((position) {
      setState(() => _currentLocation = position);
      _updateLocationInWaitingRoom();
    });

    // Start checking for a teammate every 2 seconds.
    _teammateCheckTimer = Timer.periodic(
      const Duration(seconds: 2),
          (_) => _checkForTeammate(),
    );
  }

  /// Poll your own waiting room row to check if both users are ready.
  void _startReadyPolling() {
    _readyPollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        // Query the waiting room rows for the given team challenge.
        final response = await supabase
            .from('duo_waiting_room')
            .select('user_id, is_ready')
            .eq('team_challenge_id', widget.teamChallengeId);
        // Since the response is a PostgrestList, we cast it directly as a List.
        final rows = response as List;
        if (rows.isNotEmpty && rows.length >= 2) {
          final bothReady = rows.every((row) => row['is_ready'] == true);
          if (bothReady) {
            _readyPollingTimer?.cancel();
            _navigateToActiveRun();
          }
        }
      } catch (e) {
        debugPrint('Error polling ready status: $e');
      }
    });
  }

  Future<void> _createWaitingRoomEntry() async {
    if (_currentLocation == null) return;
    final user = Provider.of<UserModel>(context, listen: false);
    try {
      // Upsert the waiting room entry using the valid team challenge ID.
      // Initialize the 'is_ready' flag to false.
      await supabase.from('duo_waiting_room').upsert({
        'user_id': user.id,
        'team_challenge_id': widget.teamChallengeId,
        'current_latitude': _currentLocation!.latitude,
        'current_longitude': _currentLocation!.longitude,
        'is_ready': false,
      });
    } catch (e) {
      debugPrint('Error creating waiting room entry: $e');
    }
  }

  Future<void> _updateLocationInWaitingRoom() async {
    if (_currentLocation == null) return;
    final user = Provider.of<UserModel>(context, listen: false);
    try {
      await supabase.from('duo_waiting_room').update({
        'current_latitude': _currentLocation!.latitude,
        'current_longitude': _currentLocation!.longitude,
      }).match({
        'user_id': user.id,
        'team_challenge_id': widget.teamChallengeId,
      });
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  Future<void> _checkForTeammate() async {
    if (_currentLocation == null) return;
    final user = Provider.of<UserModel>(context, listen: false);
    try {
      // Use maybeSingle() to get at most one partner row.
      final partnerResponse = await supabase
          .from('duo_waiting_room')
          .select('*, users(name)')
          .eq('team_challenge_id', widget.teamChallengeId)
          .neq('user_id', user.id)
          .maybeSingle();

      if (partnerResponse == null) return;

      final data = partnerResponse as Map<String, dynamic>;
      final partnerLat = data['current_latitude'] as num;
      final partnerLng = data['current_longitude'] as num;
      final distance = Geolocator.distanceBetween(
        _currentLocation!.latitude,
        _currentLocation!.longitude,
        partnerLat.toDouble(),
        partnerLng.toDouble(),
      );

      setState(() {
        _teammateInfo = data;
        _teammateDistance = distance;
      });
      // Optionally, you can update the UI to show partner info even before ready.
    } catch (e) {
      debugPrint('Error checking for teammate: $e');
    }
  }

  /// Called when the user presses the "Ready" button.
  Future<void> _setReady() async {
    final user = Provider.of<UserModel>(context, listen: false);
    try {
      await supabase.from('duo_waiting_room').update({
        'is_ready': true,
      }).match({
        'user_id': user.id,
        'team_challenge_id': widget.teamChallengeId,
      });
      setState(() {
        _isReady = true;
      });
    } catch (e) {
      debugPrint('Error setting ready status: $e');
    }
  }

  void _navigateToActiveRun() {
    _teammateCheckTimer?.cancel();
    _readyPollingTimer?.cancel();
    Navigator.pushReplacementNamed(
      context,
      '/active_run',
      arguments: {
        'journey_type': 'duo',
        'team_challenge_id': widget.teamChallengeId,
      },
    );
  }

  Future<void> _cleanupWaitingRoom() async {
    final user = Provider.of<UserModel>(context, listen: false);
    try {
      await supabase.from('duo_waiting_room').delete().match({
        'user_id': user.id,
        'team_challenge_id': widget.teamChallengeId,
      });
    } catch (e) {
      debugPrint('Error cleaning up waiting room: $e');
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _teammateCheckTimer?.cancel();
    _readyPollingTimer?.cancel();
    _cleanupWaitingRoom();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return _buildLoadingScreen();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Waiting for Teammate'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            _cleanupWaitingRoom();
            Navigator.pop(context);
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatusCard(),
              const SizedBox(height: 20),
              if (_teammateInfo != null) _buildTeammateInfo(),
              const SizedBox(height: 40),
              // Show the Ready button if not already set.
              if (!_isReady)
                ElevatedButton(
                  onPressed: _setReady,
                  child: const Text('Ready'),
                )
              else
                const Text(
                  'You are ready! Waiting for teammate...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Initializing GPS...'),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_searching, size: 50),
            const SizedBox(height: 16),
            Text(
              _teammateInfo == null
                  ? 'Waiting for teammate...'
                  : 'Teammate found!',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure you are within ${REQUIRED_PROXIMITY}m of each other',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeammateInfo() {
    final teammateName = _teammateInfo?['users']?['name'] ?? 'Teammate';
    final distance = _teammateDistance?.toStringAsFixed(1) ?? '?';
    final isInRange =
        _teammateDistance != null && _teammateDistance! <= REQUIRED_PROXIMITY;
    return Card(
      elevation: 4,
      color: isInRange ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              teammateName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Distance: ${distance}m',
              style: TextStyle(
                color: isInRange ? Colors.green : Colors.orange,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isInRange ? 'Ready to start soon...' : 'Getting closer...',
              style: TextStyle(
                color: isInRange ? Colors.green : Colors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
