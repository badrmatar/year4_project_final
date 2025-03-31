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

  static const int AUTO_START_SECONDS = 5;
  static const double ACCEPTABLE_ACCURACY = 60.0; // meters
  static const double GOOD_ACCURACY = 50.0;

  @override
  void initState() {
    super.initState();
    _initializeLocationTracking();

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });

        try {
          final newPosition = await _locationService.refreshCurrentLocation();
          if (mounted && newPosition != null) {
            setState(() {

              if (_bestPosition == null || newPosition.accuracy < _bestPosition!.accuracy) {
                _bestPosition = newPosition;
                print('New improved position: accuracy ${newPosition.accuracy}m');
              }
            });
          }
        } catch (e) {
          print('Error getting fresh location: $e');
        }

        // (Auto-start has now been made redundant)
        if (_elapsedSeconds >= AUTO_START_SECONDS && _bestPosition != null) {
          if (_bestPosition!.accuracy <= ACCEPTABLE_ACCURACY) {
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
    });

    _locationService.positionStream.listen((position) {
      if (!mounted) return;
      print('Position update: lat=${position.latitude}, lng=${position.longitude}, acc=${position.accuracy}m');

      setState(() {
        if (_bestPosition == null || position.accuracy < _bestPosition!.accuracy) {
          _bestPosition = position;
          print('New best position! Accuracy: ${position.accuracy}m');
          if (position.accuracy < GOOD_ACCURACY) {
            _isWaitingForSignal = false;
            _hasGoodSignal = true;
            _statusMessage = "GPS signal acquired! Ready to start.";
          } else if (position.accuracy < ACCEPTABLE_ACCURACY) {
            _isWaitingForSignal = false;
            _hasGoodSignal = false;
            _statusMessage = "Acceptable GPS signal. Can auto-start soon.";
          }
        }

        if (_bestPosition != null) {
          if (_elapsedSeconds >= AUTO_START_SECONDS && _bestPosition!.accuracy <= ACCEPTABLE_ACCURACY) {
            _statusMessage = "Auto-starting with accuracy: ${_bestPosition!.accuracy.toStringAsFixed(1)}m";
          }
        }
      });

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
    });
  }

  void _startRun() {
    if (_bestPosition == null) return;
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
    // cleanup
    _locationService.stopQualityMonitoring();
    _elapsedTimer?.cancel();
    _autoStartTimer?.cancel();

    print('RunLoadingPage disposed, all resources cleaned up');
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
              // Display current accuracy
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _bestPosition!.accuracy),
                duration: const Duration(milliseconds: 500),
                builder: (context, value, child) {
                  return Text(
                    'Current Accuracy: ${value.toStringAsFixed(1)}m',
                    style: TextStyle(
                      color: value <= GOOD_ACCURACY ? Colors.green :
                      value <= ACCEPTABLE_ACCURACY ? Colors.orange : Colors.red,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
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
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                child: Column(
                  children: [
                    Text(
                      '${_elapsedSeconds < AUTO_START_SECONDS ? "Checking GPS signal..." :
                      _bestPosition!.accuracy <= ACCEPTABLE_ACCURACY ?
                      "Starting run with current accuracy..." :
                      "Still trying to improve accuracy..."}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    if (_elapsedSeconds < AUTO_START_SECONDS)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Auto-start in ${AUTO_START_SECONDS - _elapsedSeconds} seconds',
                          style: const TextStyle(color: Colors.amber, fontSize: 14),
                        ),
                      ),

                    if (_elapsedSeconds >= AUTO_START_SECONDS && _bestPosition!.accuracy > ACCEPTABLE_ACCURACY)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Need ${(_bestPosition!.accuracy - ACCEPTABLE_ACCURACY).toStringAsFixed(1)}m better accuracy',
                          style: const TextStyle(color: Colors.orange, fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),

              if (_elapsedSeconds >= AUTO_START_SECONDS && _bestPosition!.accuracy > ACCEPTABLE_ACCURACY)
                Container(
                  width: 200,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8.0),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: LinearProgressIndicator(
                    value: _elapsedSeconds % 3 / 3,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                ),
            ],
            const SizedBox(height: 48),
            // Only show cancel button
            Center(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Cancel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[800],
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}