import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/poi.dart';

class OSMService {
  static const String _overpassEndpoint = 'https://overpass-api.de/api/interpreter';

  Future<List<POI>> getNearbyPOIs(double lat, double lon, {int radiusMeters = 100}) async {
    try {
      final query = _buildOverpassQuery(lat, lon, radiusMeters);
      
      final response = await http.post(
        Uri.parse(_overpassEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'data': query},
      );

      if (response.statusCode != 200) {
        throw Exception('Overpass API error: ${response.statusCode}');
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? [];

      final pois = <POI>[];
      for (final element in elements) {
        final elementMap = element as Map<String, dynamic>;
        final tags = elementMap['tags'] as Map<String, dynamic>? ?? {};
        
        if (tags.containsKey('name')) {
          try {
            pois.add(POI.fromJson(elementMap));
          } catch (e) {
            continue;
          }
        }
      }

      print('Found ${pois.length} POIs');
      return pois;
    } catch (e) {
      print('Error querying POIs: $e');
      return [];
    }
  }

  String _buildOverpassQuery(double lat, double lon, int radius) {
    return '''
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
  }
}
