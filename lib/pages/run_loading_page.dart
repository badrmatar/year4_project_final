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

  bool _isWaitingForSignal = true;
  bool _hasGoodSignal = false;
  int _elapsedSeconds = 0;
  String _statusMessage = "Acquiring GPS signal...";
  LocationQuality _currentQuality = LocationQuality.unusable;
  Position? _bestPosition;
  double _signalQualityPercentage = 0;
  Timer? _elapsedTimer;
  Timer? _autoStartTimer;

  // Define the thresholds
  static const int AUTO_START_SECONDS = 5;
  static const double ACCEPTABLE_ACCURACY = 60.0; // meters
  static const double GOOD_ACCURACY = 50.0; // meters for "good signal" indicator

  @override
  void initState() {
    super.initState();
    _initializeLocationTracking();

    // Timer to update elapsed time display
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });

        // Check if we should auto-start after AUTO_START_SECONDS
        if (_elapsedSeconds >= AUTO_START_SECONDS && _bestPosition != null) {
          if (_bestPosition!.accuracy <= ACCEPTABLE_ACCURACY) {
            // Cancel timers to avoid multiple calls
            _autoStartTimer?.cancel();
            _autoStartTimer = Timer(const Duration(milliseconds: 500), () {
              if (mounted) {
                _startRun();
              }
            });
          }
        }
      }
    });
  }

  Future<void> _initializeLocationTracking() async {
    final initialPosition = await _locationService.getCurrentLocation();
    if (initialPosition != null) {
      setState(() {
        _bestPosition = initialPosition;
        _currentQuality = _locationService.currentQuality;
        _updateSignalQuality(_currentQuality);
      });

      _locationService.initializeKalmanFilter(initialPosition);
      _locationService.startQualityMonitoring();
      _monitorLocationQuality();
    } else {
      setState(() {
        _statusMessage = "Unable to get initial location";
        _isWaitingForSignal = false;
      });
    }
  }

  void _updateSignalQuality(LocationQuality quality) {
    switch (quality) {
      case LocationQuality.excellent:
        _signalQualityPercentage = 1.0;
        break;
      case LocationQuality.good:
        _signalQualityPercentage = 0.75;
        break;
      case LocationQuality.fair:
        _signalQualityPercentage = 0.5;
        break;
      case LocationQuality.poor:
        _signalQualityPercentage = 0.25;
        break;
      case LocationQuality.unusable:
        _signalQualityPercentage = 0.1;
        break;
    }
  }

  void _monitorLocationQuality() {
    _locationService.qualityStream.listen((quality) {
      if (!mounted) return;

      setState(() {
        _currentQuality = quality;
        _updateSignalQuality(quality);
        _statusMessage = _locationService.getQualityDescription(quality);
      });

      if (_locationService.lastPosition != null) {
        setState(() {
          _bestPosition = _locationService.lastPosition;
        });

        // Enable "good signal" indicator when accuracy is under GOOD_ACCURACY
        if (_bestPosition != null && _bestPosition!.accuracy < GOOD_ACCURACY) {
          setState(() {
            _isWaitingForSignal = false;
            _hasGoodSignal = true;
            _statusMessage = "GPS signal acquired! Ready to start.";
          });
        }

        // Auto-start check if we've hit the time threshold and have acceptable accuracy
        if (_elapsedSeconds >= AUTO_START_SECONDS &&
            _bestPosition != null &&
            _bestPosition!.accuracy <= ACCEPTABLE_ACCURACY) {
          _autoStartTimer?.cancel();
          _autoStartTimer = Timer(const Duration(milliseconds: 500), () {
            if (mounted) {
              _startRun();
            }
          });
        }
      }
    });
  }

  void _startRun() {
    if (_bestPosition == null) return;

    // Cancel timers to prevent further callbacks
    _elapsedTimer?.cancel();
    _autoStartTimer?.cancel();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ActiveRunPage(
          initialPosition: _bestPosition!,
          journeyType: widget.journeyType,
          challengeId: widget.challengeId,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _locationService.stopQualityMonitoring();
    _elapsedTimer?.cancel();
    _autoStartTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('GPS Signal Check'),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // GPS Signal Indicator
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[900],
                boxShadow: [
                  BoxShadow(
                    color: _locationService.getQualityColor(_currentQuality).withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.gps_fixed,
                      size: 48,
                      color: _locationService.getQualityColor(_currentQuality),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _elapsedSeconds.toString() + "s",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Signal strength indicator
                    Container(
                      width: 120,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.grey[800],
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _signalQualityPercentage,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: _locationService.getQualityColor(_currentQuality),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Status message
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            if (_bestPosition != null) ...[
              const SizedBox(height: 16),
              Text(
                'Accuracy: ${_bestPosition!.accuracy.toStringAsFixed(1)}m',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
              if (_elapsedSeconds >= AUTO_START_SECONDS)
                Text(
                  _bestPosition!.accuracy <= ACCEPTABLE_ACCURACY
                      ? 'Auto-starting run with current accuracy...'
                      : 'Waiting for better accuracy (need < ${ACCEPTABLE_ACCURACY}m)',
                  style: TextStyle(
                    color: _bestPosition!.accuracy <= ACCEPTABLE_ACCURACY ? Colors.green : Colors.orange,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else
                Text(
                  _bestPosition!.accuracy < GOOD_ACCURACY
                      ? 'Good accuracy achieved!'
                      : 'Waiting for better accuracy (need < ${GOOD_ACCURACY}m)',
                  style: TextStyle(
                    color: _bestPosition!.accuracy < GOOD_ACCURACY ? Colors.green : Colors.orange,
                    fontSize: 14,
                  ),
                ),
            ],
            const SizedBox(height: 48),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Cancel button
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(width: 16),
                // Start run button - enabled if we have good accuracy
                ElevatedButton.icon(
                  onPressed: _hasGoodSignal ? _startRun : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start Run'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    disabledBackgroundColor: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}