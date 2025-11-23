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
  bool _isCameraActive = false; // Controls camera display
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
      _statusText = "Ready";
    });

    // Start periodic scan (every 5 seconds) - runs in background
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
      // Fetch POIs based on current location (continues in background)
      final results = await _osmService.getNearbyPOIs(
          _currentPosition!.latitude,
          _currentPosition!.longitude
      );

      if (mounted) {
        setState(() {
          // Limit to top 5 locations
          _nearbyPOIs = results.take(5).toList();
        });
      }
    } catch (e) {
      print("Scan error: $e");
    }
  }

  void _toggleCamera() {
    setState(() {
      _isCameraActive = !_isCameraActive;
    });
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
      body: SafeArea(
        child: Column(
          children: [
            // TOP SECTION: Camera Feed (fills naturally without aspect ratio constraints)
            Expanded(
              flex: 4,
              child: Container(
                color: Colors.black,
                child: _isCameraActive && controller != null && controller!.value.isInitialized
                    ? ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width,
                              height: MediaQuery.of(context).size.width * controller!.value.aspectRatio,
                              child: CameraPreview(controller!),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt,
                              size: 80,
                              color: Colors.white30,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isCameraActive ? 'Starting camera...' : 'Camera inactive',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            
            // Divider
            Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF667eea),
                    const Color(0xFF764ba2),
                  ],
                ),
              ),
            ),
            
            // BOTTOM SECTION: Start/Stop Button
            Expanded(
              flex: 1,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1A1A1A),
                      const Color(0xFF2A2A2A),
                    ],
                  ),
                ),
                child: Center(
                  child: ElevatedButton(
                    onPressed: _toggleCamera,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ).copyWith(
                      backgroundColor: MaterialStateProperty.resolveWith<Color>(
                        (Set<MaterialState> states) {
                          return Colors.transparent;
                        },
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isCameraActive
                              ? [
                                  const Color(0xFFea5455),
                                  const Color(0xFFf07167),
                                ]
                              : [
                                  const Color(0xFF667eea),
                                  const Color(0xFF764ba2),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: (_isCameraActive 
                                ? const Color(0xFFea5455) 
                                : const Color(0xFF667eea)).withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isCameraActive ? Icons.stop : Icons.play_arrow,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _isCameraActive ? 'STOP' : 'START',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
