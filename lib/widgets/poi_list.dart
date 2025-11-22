import 'package:flutter/material.dart';
import '../models/poi.dart';

class POIListWidget extends StatelessWidget {
  final List<POI> pois;

  const POIListWidget({super.key, required this.pois});

  @override
  Widget build(BuildContext context) {
    if (pois.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: const Text(
          'No nearby locations found',
          style: TextStyle(color: Colors.white, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        shrinkWrap: true,
        itemCount: pois.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              pois[index].displayText,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          );
        },
      ),
    );
  }
}
