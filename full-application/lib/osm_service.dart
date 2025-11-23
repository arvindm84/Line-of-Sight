import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class POI {
  final String name;
  final String category;
  final String type;
  final double distance;

  POI({
    required this.name,
    required this.category,
    required this.type,
    required this.distance,
  });
}

class OSMService {
  final String overpassEndpoint = 'https://overpass-api.de/api/interpreter';

  Future<List<POI>> getNearbyPOIs(double lat, double lon, {int radius = 100}) async {
    // Query logic ported from openstreetmap.js
    final query = '''
      [out:json][timeout:25];
      (
        node(around:$radius,$lat,$lon)["tourism"="attraction"];
        way(around:$radius,$lat,$lon)["tourism"="attraction"];
        node(around:$radius,$lat,$lon)["historic"];
        way(around:$radius,$lat,$lon)["historic"];
        node(around:$radius,$lat,$lon)["amenity"~"museum|theatre|cinema|library|restaurant|cafe|bar|pub|fast_food"];
        way(around:$radius,$lat,$lon)["amenity"~"museum|theatre|cinema|library|restaurant|cafe|bar|pub|fast_food"];
        node(around:$radius,$lat,$lon)["shop"];
        way(around:$radius,$lat,$lon)["shop"];
        node(around:$radius,$lat,$lon)["leisure"~"park|playground|garden"];
        way(around:$radius,$lat,$lon)["leisure"~"park|playground|garden"];
      );
      out body;
      >;
      out skel qt;
    ''';

    try {
      final response = await http.post(
        Uri.parse(overpassEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'data=${Uri.encodeComponent(query)}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List;

        List<POI> pois = [];

        for (var el in elements) {
          if (el['tags'] != null && el['tags']['name'] != null) {
            final tags = el['tags'];
            String category = 'landmark';

            // Logic from categorizePOIs in JS
            if (tags['tourism'] != null) category = 'attraction';
            else if (tags['historic'] != null) category = 'historic';
            else if (['restaurant', 'cafe', 'bar'].contains(tags['amenity'])) category = 'food';
            else if (tags['shop'] != null) category = 'shop';
            else if (tags['leisure'] != null) category = 'recreation';
            else if (tags['amenity'] != null) category = 'amenity';

            // Calculate distance using Geolocator (replaces Haversine function in JS)
            double? elLat = el['lat'];
            double? elLon = el['lon'];

            // Handle "ways" (shapes) which might define center differently in raw OSM,
            // but for simplicity we skip complex way geometry parsing here if lat/lon missing
            if (elLat != null && elLon != null) {
              double dist = Geolocator.distanceBetween(lat, lon, elLat, elLon);

              pois.add(POI(
                name: tags['name'],
                category: category,
                type: tags['tourism'] ?? tags['amenity'] ?? 'unknown',
                distance: dist,
              ));
            }
          }
        }

        // Sort by distance
        pois.sort((a, b) => a.distance.compareTo(b.distance));
        return pois;
      }
    } catch (e) {
      print("OSM Error: $e");
    }
    return [];
  }
}