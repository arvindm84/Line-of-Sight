class POI {
  final String name;
  final String category;
  final String type;
  final String? cuisine;
  final String? shopType;
  final double latitude;
  final double longitude;
  double distance;

  POI({
    required this.name,
    required this.category,
    required this.type,
    this.cuisine,
    this.shopType,
    required this.latitude,
    required this.longitude,
    this.distance = 0.0,
  });

  factory POI.fromJson(Map<String, dynamic> json) {
    final tags = json['tags'] as Map<String, dynamic>? ?? {};
    
    String category = 'landmark';
    String type = 'unknown';
    String? cuisine;
    String? shopType;

    if (tags.containsKey('tourism')) {
      category = 'attraction';
      type = tags['tourism'] as String;
    } else if (tags.containsKey('historic')) {
      category = 'historic';
      type = tags['historic'] as String;
    } else if (tags.containsKey('amenity')) {
      final amenity = tags['amenity'] as String;
      if (['restaurant', 'cafe', 'bar'].contains(amenity)) {
        category = 'food';
        type = amenity;
        cuisine = tags['cuisine'] as String?;
      } else {
        category = 'amenity';
        type = amenity;
      }
    } else if (tags.containsKey('shop')) {
      category = 'shop';
      shopType = tags['shop'] as String;
      type = 'shop';
    } else if (tags.containsKey('leisure')) {
      category = 'recreation';
      type = tags['leisure'] as String;
    }

    double lat = 0.0;
    double lon = 0.0;

    if (json.containsKey('lat') && json.containsKey('lon')) {
      lat = (json['lat'] as num).toDouble();
      lon = (json['lon'] as num).toDouble();
    } else if (json.containsKey('center')) {
      final center = json['center'] as Map<String, dynamic>;
      lat = (center['lat'] as num).toDouble();
      lon = (center['lon'] as num).toDouble();
    }

    return POI(
      name: tags['name'] as String? ?? 'Unknown',
      category: category,
      type: type,
      cuisine: cuisine,
      shopType: shopType,
      latitude: lat,
      longitude: lon,
    );
  }

  String get displayText {
    final buffer = StringBuffer(name);

    if (category == 'food' && cuisine != null && cuisine!.isNotEmpty) {
      buffer.write(' ($cuisine $type)');
    } else if (category == 'shop' && shopType != null && shopType!.isNotEmpty) {
      buffer.write(' ($shopType)');
    } else if (type != category) {
      buffer.write(' ($type)');
    }

    if (distance > 0) {
      buffer.write(' - ${distance.round()}m');
    }

    return buffer.toString();
  }
}
