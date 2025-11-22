import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../services/osm_service.dart';
import '../models/poi.dart';
import '../widgets/poi_list.dart';

class MainScreen extends StatefulWidget {
  final CameraDescription camera;

  const MainScreen({super.key, required this.camera});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late CameraController _cameraController;
  final LocationService _locationService = LocationService();
  final OSMService _osmService = OSMService();
  
  List<POI> _pois = [];
  String _statusText = 'Initializing...';
  bool _isInitialized = false;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _cameraController = CameraController(
        widget.camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _cameraController.initialize();

      setState(() => _statusText = 'Getting location...');
      await _locationService.getCurrentPosition();

      _locationService.getPositionStream().listen((position) {
        print('Location: ${position.latitude}, ${position.longitude}');
      });

      setState(() {
        _isInitialized = true;
        _statusText = '';
      });

      _scanTimer = Timer.periodic(const Duration(seconds: 5), (_) => _scan());
      _scan();

    } catch (e) {
      setState(() => _statusText = 'Error: $e');
    }
  }

  Future<void> _scan() async {
    final position = _locationService.lastPosition;
    if (position == null) return;

    try {
      print('Scanning...');
      
      final pois = await _osmService.getNearbyPOIs(
        position.latitude,
        position.longitude,
      );

      for (final poi in pois) {
        poi.distance = LocationService.calculateDistance(
          position.latitude,
          position.longitude,
          poi.latitude,
          poi.longitude,
        );
      }

      pois.sort((a, b) => a.distance.compareTo(b.distance));
      setState(() => _pois = pois.take(10).toList());
      
    } catch (e) {
      print('Scan error: $e');
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (_isInitialized)
            SizedBox.expand(child: CameraPreview(_cameraController))
          else
            Container(color: Colors.black),

          if (_statusText.isNotEmpty)
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusText,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: POIListWidget(pois: _pois),
          ),
        ],
      ),
    );
  }
}
