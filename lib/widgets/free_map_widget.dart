import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class FreeMapWidget extends StatefulWidget {
  final LatLng? initialLocation;
  final List<LatLng>? markers;
  final Function(LatLng)? onTap;
  final double zoom;

  const FreeMapWidget({
    Key? key,
    this.initialLocation,
    this.markers,
    this.onTap,
    this.zoom = 13.0,
  }) : super(key: key);

  @override
  _FreeMapWidgetState createState() => _FreeMapWidgetState();
}

class _FreeMapWidgetState extends State<FreeMapWidget> {
  late MapController mapController;
  LatLng? currentLocation;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    mapController = MapController();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        if (mounted) {
          setState(() {
            currentLocation = LatLng(position.latitude, position.longitude);
            isLoading = false;
          });

          // Move map to current location if no initial location provided
          if (widget.initialLocation == null) {
            mapController.move(currentLocation!, widget.zoom);
          }
        }
      } else {
        // Use default location (Colombo, Sri Lanka)
        if (mounted) {
          setState(() {
            currentLocation = LatLng(6.9271, 79.8612);
            isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error getting location: $e');
      if (mounted) {
        setState(() {
          currentLocation = LatLng(6.9271, 79.8612); // Default to Colombo
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading map...'),
          ],
        ),
      );
    }

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        center:
            widget.initialLocation ??
            currentLocation ??
            LatLng(6.9271, 79.8612), // Colombo, Sri Lanka default
        zoom: widget.zoom,
        onTap: (tapPosition, point) {
          if (widget.onTap != null) {
            widget.onTap!(point);
          }
        },
        interactiveFlags: InteractiveFlag.all,
      ),
      children: [
        // Free OpenStreetMap tiles
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.tapzee',
          maxZoom: 19,
          backgroundColor: Colors.grey[200],
        ),

        // Current location marker
        if (currentLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: currentLocation!,
                width: 60,
                height: 60,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.8),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(Icons.person, color: Colors.white, size: 25),
                ),
              ),
            ],
          ),

        // Custom markers
        if (widget.markers != null && widget.markers!.isNotEmpty)
          MarkerLayer(
            markers: widget.markers!
                .map(
                  (point) => Marker(
                    point: point,
                    width: 50,
                    height: 50,
                    child: GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('User Marker'),
                            content: Text(
                              'User at:\nLat: 	{point.latitude}\nLng: 	{point.longitude}',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Close'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  @override
  void dispose() {
    mapController.dispose();
    super.dispose();
  }
}

// Helper class for map utilities
class MapUtils {
  static double calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  static LatLng getCenterPoint(List<LatLng> points) {
    if (points.isEmpty) return LatLng(0, 0);

    double latitude =
        points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    double longitude =
        points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;

    return LatLng(latitude, longitude);
  }

  static double getZoomForDistance(double distanceInMeters) {
    if (distanceInMeters > 50000) return 8.0;
    if (distanceInMeters > 20000) return 10.0;
    if (distanceInMeters > 10000) return 12.0;
    if (distanceInMeters > 5000) return 14.0;
    if (distanceInMeters > 1000) return 16.0;
    return 18.0;
  }
}
