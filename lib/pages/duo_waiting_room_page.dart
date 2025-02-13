// lib/pages/duo_waiting_room.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';
import '../services/location_service.dart';

class DuoWaitingRoom extends StatefulWidget {
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
  Timer? _statusCheckTimer;
  Position? _currentLocation;
  Map<String, dynamic>? _teammateInfo;
  double? _teammateDistance;
  bool _isInitializing = true;
  bool _hasJoinedWaitingRoom = false;
  static const double REQUIRED_PROXIMITY = 200; // in meters

  // Local flags for status
  bool _isReady = false;
  bool _hasTeammate = false;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    try {
      // Clean up any existing entries first
      await _cleanupExistingEntries();

      final initialPosition = await _locationService.getCurrentLocation();
      if (initialPosition != null && mounted) {
        setState(() {
          _currentLocation = initialPosition;
          _isInitializing = false;
        });
        await _joinWaitingRoom();
        _startLocationTracking();
        _startStatusChecking();
      }
    } catch (e) {
      debugPrint('Error initializing location: $e');
    }
  }

  Future<void> _cleanupExistingEntries() async {
    try {
      final user = Provider.of<UserModel>(context, listen: false);
      // First, delete any existing entries for this user
      await supabase
          .from('duo_waiting_room')
          .delete()
          .match({
        'user_id': user.id,
        'team_challenge_id': widget.teamChallengeId,
      });

      // Also clean up any stale entries for this challenge
      final staleTime = DateTime.now().subtract(const Duration(seconds: 30));
      await supabase
          .from('duo_waiting_room')
          .delete()
          .match({
        'team_challenge_id': widget.teamChallengeId,
      })
          .lt('last_update', staleTime.toIso8601String());

    } catch (e) {
      debugPrint('Error cleaning up existing entries: $e');
    }
  }

  Future<void> _joinWaitingRoom() async {
    if (_currentLocation == null) return;

    final user = Provider.of<UserModel>(context, listen: false);
    try {
      // Create new waiting room entry
      await supabase
          .from('duo_waiting_room')
          .insert({
        'user_id': user.id,
        'team_challenge_id': widget.teamChallengeId,
        'current_latitude': _currentLocation!.latitude,
        'current_longitude': _currentLocation!.longitude,
        'is_ready': false,
        'has_ended': false,
        'max_distance_exceeded': false,
        'last_update': DateTime.now().toIso8601String(),
      });

      setState(() {
        _hasJoinedWaitingRoom = true;
      });
    } catch (e) {
      debugPrint('Error joining waiting room: $e');
    }
  }

  void _startLocationTracking() {
    _locationSubscription = _locationService.trackLocation().listen((position) {
      if (mounted) {
        setState(() => _currentLocation = position);
        _updateLocationInWaitingRoom();
      }
    });
  }

  void _startStatusChecking() {
    // Cancel existing timer if any
    _statusCheckTimer?.cancel();

    // Start new status check timer - checking more frequently (every 500ms)
    _statusCheckTimer = Timer.periodic(
      const Duration(milliseconds: 500),
          (_) => _checkWaitingRoomStatus(),
    );
  }

  Future<void> _checkWaitingRoomStatus() async {
    if (!_hasJoinedWaitingRoom) return;

    try {
      final user = Provider.of<UserModel>(context, listen: false);

      // Get all active waiting room entries for this challenge
      final response = await supabase
          .from('duo_waiting_room')
          .select('*, users(name)')
          .eq('team_challenge_id', widget.teamChallengeId)
          .eq('has_ended', false);  // Only get active entries

      final rows = response as List;

      // Find teammate's entry
      Map<String, dynamic>? teammateEntry;
      bool bothUsersPresent = false;

      if (rows.length == 2) {
        bothUsersPresent = true;
        // Find the teammate's entry (not current user's entry)
        try {
          teammateEntry = rows.firstWhere(
                (row) => row['user_id'] != user.id,
          ) as Map<String, dynamic>;
        } catch (e) {
          teammateEntry = null;
          bothUsersPresent = false;
        }
      }

      // Check if teammate's data is fresh (less than 10 seconds old)
      if (teammateEntry != null) {
        final lastUpdate = DateTime.parse(teammateEntry['last_update']);
        final timeDiff = DateTime.now().difference(lastUpdate).inSeconds;
        debugPrint('Time since teammate update: $timeDiff seconds');

        if (timeDiff >= 15) {  // Increased from 10 to 15 seconds for more tolerance
          debugPrint('Teammate data considered stale');
          teammateEntry = null;  // Data is stale, treat as no teammate
          bothUsersPresent = false;
        }
      }

      // Update location more frequently when teammate is found
      if (bothUsersPresent && _currentLocation != null) {
        _updateLocationInWaitingRoom();
      }

      if (mounted) {
        setState(() {
          _hasTeammate = bothUsersPresent;  // Only true when both users are present with fresh data
          _teammateInfo = teammateEntry;
        });
      }

      // Update teammate distance if we have their location
      if (teammateEntry != null && _currentLocation != null) {
        final partnerLat = teammateEntry['current_latitude'] as num;
        final partnerLng = teammateEntry['current_longitude'] as num;
        final distance = Geolocator.distanceBetween(
          _currentLocation!.latitude,
          _currentLocation!.longitude,
          partnerLat.toDouble(),
          partnerLng.toDouble(),
        );

        if (mounted) {
          setState(() {
            _teammateDistance = distance;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _teammateDistance = null;
          });
        }
      }

      // Check if both users are ready and have fresh data
      if (bothUsersPresent) {
        final allReady = rows.every((row) => row['is_ready'] == true);
        final allRecent = rows.every((row) {
          final updatedAt = DateTime.parse(row['last_update']);
          return DateTime.now().difference(updatedAt).inSeconds < 10;
        });

        if (allReady && allRecent) {
          await _navigateToActiveRun();
        }
      }
    } catch (e) {
      debugPrint('Error checking waiting room status: $e');
    }
  }

  Future<void> _updateLocationInWaitingRoom() async {
    if (_currentLocation == null || !_hasJoinedWaitingRoom) return;

    final user = Provider.of<UserModel>(context, listen: false);
    try {
      debugPrint('Updating location in waiting room');
      await supabase
          .from('duo_waiting_room')
          .update({
        'current_latitude': _currentLocation!.latitude,
        'current_longitude': _currentLocation!.longitude,
        'last_update': DateTime.now().toIso8601String(),
      })
          .match({
        'user_id': user.id,
        'team_challenge_id': widget.teamChallengeId,
      });
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  Future<void> _setReady() async {
    final user = Provider.of<UserModel>(context, listen: false);
    try {
      await supabase
          .from('duo_waiting_room')
          .update({
        'is_ready': true,
        'last_update': DateTime.now().toIso8601String(),
      })
          .match({
        'user_id': user.id,
        'team_challenge_id': widget.teamChallengeId,
      });

      if (mounted) {
        setState(() {
          _isReady = true;
        });
      }
    } catch (e) {
      debugPrint('Error setting ready status: $e');
    }
  }

  Future<void> _navigateToActiveRun() async {
    _statusCheckTimer?.cancel();
    _locationSubscription?.cancel();

    if (mounted) {
      await Navigator.pushReplacementNamed(
        context,
        '/active_run',
        arguments: {
          'journey_type': 'duo',
          'team_challenge_id': widget.teamChallengeId,
        },
      );
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _statusCheckTimer?.cancel();
    _cleanupExistingEntries();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return _buildLoadingScreen();
    }

    return WillPopScope(
      onWillPop: () async {
        await _cleanupExistingEntries();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Waiting for Teammate'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _cleanupExistingEntries();
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
                if (_hasTeammate) _buildTeammateInfo(),
                const SizedBox(height: 40),
                // Only show Ready button when teammate is present and user isn't ready
                if (_hasTeammate && !_isReady)
                  ElevatedButton(
                    onPressed: _setReady,
                    child: const Text('Ready'),
                  )
                else if (_isReady)
                  const Text(
                    'You are ready! Waiting for teammate...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  )
                else
                  const Text(
                    'Waiting for teammate to join...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
              ],
            ),
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
              _hasTeammate ? 'Teammate found!' : 'Waiting for teammate...',
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