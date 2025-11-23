import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'osm_service.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } catch (e) {
    _cameras = [];
  }
  runApp(const VisualGuideApp());
}

class VisualGuideApp extends StatelessWidget {
  const VisualGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visual Guide',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1A1A),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? controller;
  final OSMService _osmService = OSMService();

  // State variables
  String _statusText = "Initializing...";
  List<POI> _nearbyPOIs = [];
  bool _isScanning = false;
  Timer? _scanTimer;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _requestPermissions();
    await _initCamera();
    await _startLocationTracking();

    setState(() {
      _isScanning = true;
      _statusText = "Scanning active";
    });

    // Start periodic scan (every 5 seconds, same as main.js)
    _scanTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _performScan();
    });

    // Perform first scan immediately
    _performScan();
  }

  Future<void> _requestPermissions() async {
    await [Permission.camera, Permission.location].request();
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) return;

    // Select back camera (environment)
    controller = CameraController(_cameras.first, ResolutionPreset.high);
    await controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _startLocationTracking() async {
    // Porting LocationService logic
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _statusText = "Location services disabled");
      return;
    }

    // Listen to location stream
    Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10
        )
    ).listen((Position position) {
      _currentPosition = position;
    });
  }

  Future<void> _performScan() async {
    if (!mounted || _currentPosition == null) return;

    try {
      // Fetch POIs based on current location
      final results = await _osmService.getNearbyPOIs(
          _currentPosition!.latitude,
          _currentPosition!.longitude
      );

      if (mounted) {
        setState(() {
          _nearbyPOIs = results;
        });
      }
    } catch (e) {
      print("Scan error: $e");
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    _scanTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Camera Layer
          if (controller != null && controller!.value.isInitialized)
            SizedBox.expand(
              child: CameraPreview(controller!),
            )
          else
            const Center(child: CircularProgressIndicator()),

          // 2. Status Overlay (Top)
          Positioned(
            top: 50,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusText,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),

          // 3. Output Panel (Right/Bottom - Replicating style.css #output-panel)
          Positioned(
            top: 120,
            right: 20,
            bottom: 100,
            width: 300,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Nearby Locations",
                    style: TextStyle(
                      color: Color(0xFF667eea),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _nearbyPOIs.isEmpty
                        ? const Text("Searching...", style: TextStyle(color: Colors.grey))
                        : ListView.builder(
                      itemCount: _nearbyPOIs.length,
                      itemBuilder: (context, index) {
                        final poi = _nearbyPOIs[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF667eea).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "${poi.name} (${poi.category}) - ${poi.distance.round()}m",
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}