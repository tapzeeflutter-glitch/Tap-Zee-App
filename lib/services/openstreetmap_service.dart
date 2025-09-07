import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

/// OpenStreetMap service for geocoding, reverse geocoding, and place search
class OpenStreetMapService {
  static const String _nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
  static const String _overpassBaseUrl =
      'https://overpass-api.de/api/interpreter';

  /// Search for places using Nominatim API
  static Future<List<PlaceResult>> searchPlaces(
    String query, {
    LatLng? center,
    double? radius,
    int limit = 10,
  }) async {
    try {
      String url =
          '$_nominatimBaseUrl/search?q=${Uri.encodeQueryComponent(query)}&format=json&limit=$limit&addressdetails=1';

      if (center != null) {
        url += '&lat=${center.latitude}&lon=${center.longitude}';
        if (radius != null) {
          url +=
              '&bounded=1&viewbox=${center.longitude - radius},${center.latitude + radius},${center.longitude + radius},${center.latitude - radius}';
        }
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'TapZee-Flutter-App/1.0'},
      );

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        return data.map((item) => PlaceResult.fromJson(item)).toList();
      } else {
        throw Exception('Failed to search places: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching places: $e');
    }
  }

  /// Reverse geocoding - get address from coordinates
  static Future<PlaceResult?> reverseGeocode(LatLng location) async {
    try {
      String url =
          '$_nominatimBaseUrl/reverse?lat=${location.latitude}&lon=${location.longitude}&format=json&addressdetails=1';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'TapZee-Flutter-App/1.0'},
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> data = json.decode(response.body);
        return PlaceResult.fromJson(data);
      } else {
        throw Exception('Failed to reverse geocode: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error reverse geocoding: $e');
    }
  }

  /// Find nearby points of interest (POIs)
  static Future<List<PointOfInterest>> findNearbyPOIs(
    LatLng center,
    double radiusInMeters, {
    List<String> amenities = const [
      'restaurant',
      'cafe',
      'hospital',
      'school',
      'bank',
    ],
  }) async {
    try {
      String amenityFilter = amenities.map((a) => '"$a"').join(',');

      String query =
          '''
        [out:json][timeout:25];
        (
          node["amenity"~"^($amenityFilter)\$"](around:$radiusInMeters,${center.latitude},${center.longitude});
          way["amenity"~"^($amenityFilter)\$"](around:$radiusInMeters,${center.latitude},${center.longitude});
          relation["amenity"~"^($amenityFilter)\$"](around:$radiusInMeters,${center.latitude},${center.longitude});
        );
        out center meta;
      ''';

      final response = await http.post(
        Uri.parse(_overpassBaseUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'TapZee-Flutter-App/1.0',
        },
        body: query,
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> data = json.decode(response.body);
        List<dynamic> elements = data['elements'] ?? [];

        return elements
            .map((element) => PointOfInterest.fromOverpassJson(element))
            .toList();
      } else {
        throw Exception('Failed to find POIs: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error finding POIs: $e');
    }
  }

  /// Get route between two points using OpenRouteService (free alternative)
  static Future<RouteResult?> getRoute(
    LatLng start,
    LatLng end, {
    String profile =
        'driving-car', // driving-car, foot-walking, cycling-regular
  }) async {
    try {
      // Note: This requires OpenRouteService API key for production use
      // For demo purposes, we'll create a simple straight line route
      return RouteResult(
        coordinates: [start, end],
        distance: Geolocator.distanceBetween(
          start.latitude,
          start.longitude,
          end.latitude,
          end.longitude,
        ),
        duration: 0, // Would be calculated by routing service
      );
    } catch (e) {
      throw Exception('Error getting route: $e');
    }
  }

  /// Calculate distance between two points
  static double calculateDistance(LatLng point1, LatLng point2) {
    return Geolocator.distanceBetween(
      point1.latitude,
      point1.longitude,
      point2.latitude,
      point2.longitude,
    );
  }

  /// Format distance for display
  static String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()}m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)}km';
    }
  }
}

/// Place search result from Nominatim
class PlaceResult {
  final String displayName;
  final LatLng location;
  final String? type;
  final Map<String, dynamic>? address;
  final String? placeId;

  PlaceResult({
    required this.displayName,
    required this.location,
    this.type,
    this.address,
    this.placeId,
  });

  factory PlaceResult.fromJson(Map<String, dynamic> json) {
    return PlaceResult(
      displayName: json['display_name'] ?? '',
      location: LatLng(
        double.parse(json['lat'].toString()),
        double.parse(json['lon'].toString()),
      ),
      type: json['type'],
      address: json['address'],
      placeId: json['place_id']?.toString(),
    );
  }

  String get shortName {
    if (address != null) {
      return address!['name'] ??
          address!['house_number'] ??
          address!['road'] ??
          displayName.split(',').first;
    }
    return displayName.split(',').first;
  }

  String get fullAddress {
    return displayName;
  }
}

/// Point of Interest from Overpass API
class PointOfInterest {
  final String name;
  final LatLng location;
  final String amenity;
  final Map<String, dynamic> tags;
  final String id;

  PointOfInterest({
    required this.name,
    required this.location,
    required this.amenity,
    required this.tags,
    required this.id,
  });

  factory PointOfInterest.fromOverpassJson(Map<String, dynamic> json) {
    double lat, lon;

    if (json['lat'] != null && json['lon'] != null) {
      lat = json['lat'].toDouble();
      lon = json['lon'].toDouble();
    } else if (json['center'] != null) {
      lat = json['center']['lat'].toDouble();
      lon = json['center']['lon'].toDouble();
    } else {
      lat = 0.0;
      lon = 0.0;
    }

    Map<String, dynamic> tags = json['tags'] ?? {};

    return PointOfInterest(
      name: tags['name'] ?? tags['brand'] ?? 'Unknown',
      location: LatLng(lat, lon),
      amenity: tags['amenity'] ?? 'unknown',
      tags: tags,
      id: json['id']?.toString() ?? '',
    );
  }

  String get displayName {
    if (tags['brand'] != null && tags['name'] != null) {
      return '${tags['brand']} - ${tags['name']}';
    }
    return name;
  }

  String get category {
    switch (amenity) {
      case 'restaurant':
        return 'Restaurant';
      case 'cafe':
        return 'Cafe';
      case 'hospital':
        return 'Hospital';
      case 'school':
        return 'School';
      case 'bank':
        return 'Bank';
      case 'fuel':
        return 'Gas Station';
      case 'pharmacy':
        return 'Pharmacy';
      case 'atm':
        return 'ATM';
      default:
        return amenity.toUpperCase();
    }
  }

  IconData get icon {
    switch (amenity) {
      case 'restaurant':
        return Icons.restaurant;
      case 'cafe':
        return Icons.local_cafe;
      case 'hospital':
        return Icons.local_hospital;
      case 'school':
        return Icons.school;
      case 'bank':
        return Icons.account_balance;
      case 'fuel':
        return Icons.local_gas_station;
      case 'pharmacy':
        return Icons.local_pharmacy;
      case 'atm':
        return Icons.atm;
      default:
        return Icons.place;
    }
  }
}

/// Route result
class RouteResult {
  final List<LatLng> coordinates;
  final double distance; // in meters
  final double duration; // in seconds

  RouteResult({
    required this.coordinates,
    required this.distance,
    required this.duration,
  });

  String get formattedDistance {
    return OpenStreetMapService.formatDistance(distance);
  }

  String get formattedDuration {
    int minutes = (duration / 60).round();
    if (minutes < 60) {
      return '${minutes}min';
    } else {
      int hours = minutes ~/ 60;
      int remainingMinutes = minutes % 60;
      return '${hours}h ${remainingMinutes}min';
    }
  }
}
