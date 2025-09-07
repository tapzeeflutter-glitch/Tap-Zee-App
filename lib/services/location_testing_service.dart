import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class LocationTestingService {
  static bool _useCustomLocation = false;
  static LatLng? _customLocation;
  static Function(LatLng?)? _onLocationChanged;

  // Predefined test locations
  static final Map<String, LatLng> predefinedLocations = {
    'Galle 1, Sri Lanka': LatLng(6.0329, 80.2168),
    'Galle 2, Sri Lanka': LatLng(6.0329, 80.2169),
    'Galle 3, Sri Lanka': LatLng(6.0229, 80.2168),
    'Galle 4, Sri Lanka': LatLng(6.0330, 80.2168),
  };

  // Getters
  static bool get useCustomLocation => _useCustomLocation;
  static LatLng? get customLocation => _customLocation;

  // Set callback for location changes
  static void setLocationChangeCallback(Function(LatLng?)? callback) {
    _onLocationChanged = callback;
  }

  // Notify listeners of location change
  static void _notifyLocationChanged() {
    _onLocationChanged?.call(_useCustomLocation ? _customLocation : null);
  }

  // Toggle custom location mode
  static void toggleCustomLocation(bool enabled) {
    _useCustomLocation = enabled;
    if (!enabled) {
      _customLocation = null;
    }
    _notifyLocationChanged();
  }

  // Set custom location
  static void setCustomLocation(LatLng location) {
    _customLocation = location;
    _useCustomLocation = true;
    _notifyLocationChanged();
  }

  // Set predefined location
  static void setPredefinedLocation(String locationName) {
    if (predefinedLocations.containsKey(locationName)) {
      setCustomLocation(predefinedLocations[locationName]!);
    }
  }

  // Reset to GPS
  static void resetToGPS() {
    _useCustomLocation = false;
    _customLocation = null;
    _notifyLocationChanged();
  }

  // Get current test location or null if using GPS
  static LatLng? getCurrentTestLocation() {
    return _useCustomLocation ? _customLocation : null;
  }

  // Get nearby locations for testing multi-user scenarios
  static List<String> getNearbyLocations(String baseLocation) {
    List<String> nearby = [];

    // Find locations that are "near" the base location
    for (String location in predefinedLocations.keys) {
      if (location.contains('Near') &&
          location.toLowerCase().contains(
            baseLocation.toLowerCase().split(',')[0],
          )) {
        nearby.add(location);
      }
    }

    return nearby;
  }

  // Get location info for testing display
  static String getLocationDisplayName() {
    if (!_useCustomLocation) {
      return 'Real GPS Location';
    }

    if (_customLocation == null) {
      return 'Custom Location (Not Set)';
    }

    // Try to find a matching predefined location
    for (var entry in predefinedLocations.entries) {
      if ((entry.value.latitude - _customLocation!.latitude).abs() < 0.001 &&
          (entry.value.longitude - _customLocation!.longitude).abs() < 0.001) {
        return 'Test: ${entry.key}';
      }
    }

    return 'Test: Custom (${_customLocation!.latitude.toStringAsFixed(4)}, ${_customLocation!.longitude.toStringAsFixed(4)})';
  }
}

class LocationTestingWidget extends StatefulWidget {
  final Function(LatLng?)? onLocationChanged;

  const LocationTestingWidget({Key? key, this.onLocationChanged})
    : super(key: key);

  @override
  State<LocationTestingWidget> createState() => _LocationTestingWidgetState();
}

class _LocationTestingWidgetState extends State<LocationTestingWidget> {
  bool _useCustomLocation = LocationTestingService.useCustomLocation;
  String? _selectedPredefinedLocation;
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (LocationTestingService.customLocation != null) {
      _latController.text = LocationTestingService.customLocation!.latitude
          .toString();
      _lngController.text = LocationTestingService.customLocation!.longitude
          .toString();
    }
  }

  @override
  void dispose() {
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  void _updateLocation() {
    if (_useCustomLocation) {
      double? lat = double.tryParse(_latController.text);
      double? lng = double.tryParse(_lngController.text);

      if (lat != null && lng != null) {
        LatLng location = LatLng(lat, lng);
        LocationTestingService.setCustomLocation(location);
        widget.onLocationChanged?.call(location);
      }
    } else {
      LocationTestingService.resetToGPS();
      widget.onLocationChanged?.call(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Location Testing',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Toggle Switch
            SwitchListTile(
              title: const Text('Use Custom Location'),
              subtitle: Text(
                _useCustomLocation
                    ? 'Using test location instead of GPS'
                    : 'Using real GPS location',
              ),
              value: _useCustomLocation,
              onChanged: (value) {
                setState(() {
                  _useCustomLocation = value;
                  LocationTestingService.toggleCustomLocation(value);
                });
                _updateLocation();
              },
            ),

            if (_useCustomLocation) ...[
              const SizedBox(height: 16),

              // Multi-User Testing Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border.all(color: Colors.blue.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.group, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Multi-User Testing',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use "Near" locations to test multiple users in the same area. One phone can use GPS while another uses a nearby test location.',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Predefined Locations Dropdown
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Quick Select Location',
                  border: OutlineInputBorder(),
                  helperText: 'Choose "Near" locations for multi-user testing',
                ),
                value: _selectedPredefinedLocation,
                items: LocationTestingService.predefinedLocations.keys
                    .map(
                      (location) => DropdownMenuItem(
                        value: location,
                        child: Text(
                          location,
                          style: TextStyle(
                            color: location.contains('Near')
                                ? Colors.orange.shade700
                                : Colors.black,
                            fontWeight: location.contains('Near')
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedPredefinedLocation = value;
                      LatLng location =
                          LocationTestingService.predefinedLocations[value]!;
                      _latController.text = location.latitude.toString();
                      _lngController.text = location.longitude.toString();
                    });
                    _updateLocation();
                  }
                },
              ),

              const SizedBox(height: 16),

              // Manual Coordinates
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _updateLocation(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _updateLocation(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Current Test Location Display
              if (LocationTestingService.customLocation != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Test Location: ${LocationTestingService.customLocation!.latitude.toStringAsFixed(4)}, ${LocationTestingService.customLocation!.longitude.toStringAsFixed(4)}',
                          style: TextStyle(color: Colors.orange.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
