import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class CurrentLocationMapPage extends StatefulWidget {
  @override
  _CurrentLocationMapPageState createState() => _CurrentLocationMapPageState();
}

class _CurrentLocationMapPageState extends State<CurrentLocationMapPage> {
  GoogleMapController? _mapController;
  LatLng? _currentLatLng;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    Position? position = await _determinePosition();
    if (position != null) {
      setState(() {
        _currentLatLng = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<Position?> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Current Location'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _currentLatLng == null
              ? Center(
                  child: Text(
                    'Unable to get location.\nCheck permissions or enable GPS.',
                    textAlign: TextAlign.center,
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: GoogleMap(
                        onMapCreated: (controller) =>
                            _mapController = controller,
                        initialCameraPosition: CameraPosition(
                          target: _currentLatLng!,
                          zoom: 15,
                        ),
                        markers: {
                          Marker(
                            markerId: MarkerId('currentLocation'),
                            position: _currentLatLng!,
                            infoWindow: InfoWindow(title: 'You are here'),
                          ),
                        },
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Saved Location: ${_currentLatLng!.latitude}, ${_currentLatLng!.longitude}',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
    );
  }
}
