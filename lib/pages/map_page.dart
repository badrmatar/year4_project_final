import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class CurrentLocationMapPage extends StatefulWidget {
  @override
  _CurrentLocationMapPageState createState() => _CurrentLocationMapPageState();
}

class _CurrentLocationMapPageState extends State<CurrentLocationMapPage> {
  GoogleMapController? _mapController;
  LatLng? _currentLatLng; // This will store the user's current location
  bool _isLoading = true; // To show a progress indicator while fetching location

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
      // Handle location null scenario - permissions denied or service off
      setState(() {
        _isLoading = false;
      });
      // You could show a dialog or fall back to a default location here.
    }
  }

  Future<Position?> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled. You could request them to enable it.
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // User denied permission.
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are permanently denied.
      return null;
    }

    // Permissions granted and services enabled, get the position.
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
              onMapCreated: (controller) => _mapController = controller,
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
          // Display the saved location variables
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
