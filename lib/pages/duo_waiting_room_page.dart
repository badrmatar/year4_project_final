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
  static const double STARTING_PROXIMITY = 100; // in meters - distance required to start

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
      // userentry delete
      await supabase
          .from('duo_waiting_room')
          .delete()
          .match({
        'user_id': user.id,
        'team_challenge_id': widget.teamChallengeId,
      });
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
      //    new waiting room entry
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
    // timer cancrl
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
      final response = await supabase
          .from('duo_waiting_room')
          .select('*, users(name)')
          .eq('team_challenge_id', widget.teamChallengeId)
          .eq('has_ended', false);

      final rows = response as List;
      Map<String, dynamic>? teammateEntry;
      bool bothUsersPresent = false;

      if (rows.length == 2) {
        bothUsersPresent = true;
        try {
          teammateEntry = rows.firstWhere(
                (row) => row['user_id'] != user.id,
          ) as Map<String, dynamic>;
        } catch (e) {
          teammateEntry = null;
          bothUsersPresent = false;
        }
      }
      if (teammateEntry != null) {
        final lastUpdate = DateTime.parse(teammateEntry['last_update']);
        final timeDiff = DateTime.now().difference(lastUpdate).inSeconds;
        debugPrint('Time since teammate update: $timeDiff seconds');

        if (timeDiff >= 15) {
          debugPrint('Teammate data considered stale');
          teammateEntry = null;
          bothUsersPresent = false;
        }
      }
      if (bothUsersPresent && _currentLocation != null) {
        _updateLocationInWaitingRoom();
      }

      if (mounted) {
        setState(() {
          _hasTeammate = bothUsersPresent;
          _teammateInfo = teammateEntry;
        });
      }
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

      if (bothUsersPresent) {
        final allReady = rows.every((row) => row['is_ready'] == true);
        final allRecent = rows.every((row) {
          final updatedAt = DateTime.parse(row['last_update']);
          return DateTime.now().difference(updatedAt).inSeconds < 10;
        });

        // check if they are close
        final isCloseEnough = _teammateDistance != null && _teammateDistance! <= STARTING_PROXIMITY;

        if (allReady && allRecent && isCloseEnough) {
          await _navigateToActiveRun();
        } else if (allReady && allRecent && !isCloseEnough) {
          // If they're ready but too far apart, reset ready status
          await supabase
              .from('duo_waiting_room')
              .update({
            'is_ready': false,
            'last_update': DateTime.now().toIso8601String(),
          })
              .match({
            'user_id': user.id,
            'team_challenge_id': widget.teamChallengeId,
          });

          setState(() {
            _isReady = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("You moved too far from your teammate. Please get closer and try again."),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
          }
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
    if (_teammateDistance == null || _teammateDistance! > STARTING_PROXIMITY) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You need to be within 100m of your teammate to start"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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
        '/duo_active_run',
        arguments: {
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
                // Build the appropriate widget based on conditions
                _buildActionWidget(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionWidget() {
    if (_hasTeammate && !_isReady) {
      if (_teammateDistance != null && _teammateDistance! <= STARTING_PROXIMITY) {
        return ElevatedButton(
          onPressed: _setReady,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('Ready'),
        );
      } else {
        return const Text(
          'You need to be within 100m of your teammate to start',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        );
      }
    } else if (_isReady) {
      return const Text(
        'You are ready! Waiting for teammate...',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      );
    } else {
      return const Text(
        'Waiting for teammate to join...',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      );
    }
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
              'Make sure you are within ${STARTING_PROXIMITY}m of each other to start',
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
    final isInProximity = _teammateDistance != null && _teammateDistance! <= STARTING_PROXIMITY; // 100 meters threshold
    final isInRange = _teammateDistance != null && _teammateDistance! <= REQUIRED_PROXIMITY;

    return Card(
      elevation: 4,
      color: isInProximity ? Colors.green.shade50 : Colors.orange.shade50,
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
                color: isInProximity ? Colors.green : Colors.orange,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (isInProximity)
              Text(
                'Ready to start!',
                style: TextStyle(
                  color: Colors.green,
                ),
              )
            else
              Text(
                'You are too far from your partner!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (!isInProximity)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Please get closer (< 100m) to begin',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.red,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}