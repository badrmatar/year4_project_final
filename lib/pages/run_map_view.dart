import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RunMapView extends StatelessWidget {
  final List<dynamic> routeData;

  const RunMapView({Key? key, required this.routeData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<LatLng> points = routeData.map<LatLng>((point) {
      return LatLng(
        (point['latitude'] as num).toDouble(),
        (point['longitude'] as num).toDouble(),
      );
    }).toList();

    final polyline = Polyline(
      polylineId: const PolylineId('run_route'),
      points: points,
      color: Colors.blue,
      width: 5,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Run Route')),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: points.isNotEmpty ? points.first : const LatLng(0, 0),
          zoom: 15,
        ),
        polylines: {polyline},
      ),
    );
  }
}
