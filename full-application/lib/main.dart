import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'osm_service.dart';
import 'gemini_service.dart';
import 'fish_audio_service.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables
  await dotenv.load(fileName: ".env");
  
  try {
    _cameras = await availableCameras();
    _log("Main", "Available cameras: ${_cameras.length}");
  } catch (e) {
    _log("Main", "Error getting cameras: $e");
    _cameras = [];
  }
  runApp(const VisualGuideApp());
}

void _log(String category, String message) {
  final timestamp = DateTime.now().toIso8601String();
  print("[$timestamp] [$category] $message");
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
  late final GeminiService _geminiService;
  late final FishAudioService _fishAudioService;

  // State variables
  String _statusText = "Initializing...";
  List<POI> _nearbyPOIs = [];
  bool _isScanning = false;
  bool _isCameraActive = false;
  Timer? _osmTimer;
  Timer? _geminiTimer;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _log("Init", "Starting initialization sequence...");
    
    // Initialize Gemini service with API key
    final geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (geminiApiKey.isEmpty) {
      setState(() => _statusText = "Error: Missing Gemini API key");
      _log("Init", "Error: Missing Gemini API key");
      return;
    }
    _geminiService = GeminiService(geminiApiKey);
    
    // Initialize Fish Audio service with API key
    final fishApiKey = dotenv.env['FISH_AUDIO_KEY'] ?? '';
    if (fishApiKey.isEmpty) {
      setState(() => _statusText = "Error: Missing Fish Audio API key");
      _log("Init", "Error: Missing Fish Audio API key");
      return;
    }
    _fishAudioService = FishAudioService(fishApiKey);
    
    await _requestPermissions();
    await _initCamera();
    await _startLocationTracking();

    setState(() {
      _isScanning = true;
      _statusText = "Ready";
    });

    // Start OSM POI scanning every 5 seconds
    _osmTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchPOIs();
    });

    // Start Gemini + Fish Audio pipeline every 60 seconds
    _geminiTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      _processWithGeminiAndAudio();
    });

    // Perform first POI fetch immediately
    _fetchPOIs();
    
    // Perform first Gemini/Audio processing after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      _processWithGeminiAndAudio();
    });
    
    _log("Init", "Initialization complete.");
  }

  Future<void> _requestPermissions() async {
    _log("Perms", "Requesting permissions...");
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.location,
    ].request();
    _log("Perms", "Camera: ${statuses[Permission.camera]}, Location: ${statuses[Permission.location]}");
  }

  Future<void> _initCamera() async {
    if (_cameras.isEmpty) {
      _log("Camera", "No cameras available");
      return;
    }

    // Select back camera (rear-facing)
    final backCamera = _cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );
    
    _log("Camera", "Selected camera: ${backCamera.name} (${backCamera.lensDirection})");

    // Try initializing with medium resolution first for better compatibility
    controller = CameraController(
      backCamera, 
      ResolutionPreset.medium,
      enableAudio: false,
    );
    
    try {
      await controller!.initialize();
      _log("Camera", "Camera initialized successfully");
      
      if (mounted) {
        setState(() {
          _isCameraActive = true;
        });
      }
    } catch (e) {
      _log("Camera", "Camera initialization error (medium): $e");
      // Fallback to low resolution
      try {
        controller = CameraController(
          backCamera, 
          ResolutionPreset.low,
          enableAudio: false,
        );
        await controller!.initialize();
        _log("Camera", "Camera initialized successfully (low res)");
        if (mounted) {
          setState(() {
            _isCameraActive = true;
          });
        }
      } catch (e2) {
         _log("Camera", "Camera initialization error (low): $e2");
      }
    }
  }

  Future<void> _startLocationTracking() async {
    _log("Location", "Starting location tracking...");
    
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _log("Location", "Location services are disabled");
      setState(() => _statusText = "Location services disabled. Please enable location.");
      return;
    }

    // Check location permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _log("Location", "Location permission denied");
        setState(() => _statusText = "Location permission denied");
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _log("Location", "Location permission denied forever");
      setState(() => _statusText = "Location permission permanently denied");
      return;
    }

    // Get initial position with timeout
    try {
      _log("Location", "Getting initial position...");
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      _log("Location", "Initial position: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}");
    } catch (e) {
      _log("Location", "Error getting initial position: $e");
    }

    // Listen to location stream
    // Removed distanceFilter to ensure we get updates even for small movements during testing
    Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            // distanceFilter: 10 // Commented out for debugging
        )
    ).listen((Position position) {
      _currentPosition = position;
      _log("Location", "Position update: ${position.latitude}, ${position.longitude}");
    }, onError: (e) {
      _log("Location", "Stream error: $e");
    });
  }

  /// Fetch POIs from OpenStreetMap (called every 5 seconds)
  Future<void> _fetchPOIs() async {
    if (!mounted) return;
    
    if (_currentPosition == null) {
      _log("OSM", "No location available yet, skipping POI fetch");
      return;
    }

    _log("OSM", "Fetching POIs for ${_currentPosition!.latitude}, ${_currentPosition!.longitude}");

    try {
      final results = await _osmService.getNearbyPOIs(
          _currentPosition!.latitude,
          _currentPosition!.longitude
      );
      _log("OSM", "Found ${results.length} POIs");

      final top5 = results.take(5).toList();
      
      if (top5.isEmpty) {
        _log("OSM", "No POIs found nearby");
        return;
      }
      
      _log("OSM", "Top 5: ${top5.map((p) => p.name).toList()}");

      // Update state with the latest POIs
      if (mounted) {
        setState(() {
          _nearbyPOIs = top5;
        });
      }
    } catch (e) {
      _log("OSM", "Fetch error: $e");
    }
  }

  /// Process POIs with Gemini and Fish Audio (called every 60 seconds)
  Future<void> _processWithGeminiAndAudio() async {
    if (!mounted) return;

    if (_nearbyPOIs.isEmpty) {
      _log("Pipeline", "No POIs available to process");
      return;
    }

    _log("Pipeline", "Starting Gemini + Fish Audio pipeline...");
    _log("Pipeline", "Processing ${_nearbyPOIs.length} POIs");

    try {
      // Step 2: Convert to conversational text using Gemini
      _log("Pipeline", "Sending to Gemini...");
      final conversationalText = await _geminiService.convertToConversation(_nearbyPOIs);
      _log("Pipeline", "Gemini response: $conversationalText");

      // Step 3: Convert text to speech using Fish Audio
      _log("Pipeline", "Sending to Fish Audio...");
      await _fishAudioService.textToSpeech(conversationalText);
      _log("Pipeline", "Fish Audio TTS complete");
      
      _log("Pipeline", "Pipeline complete");
    } catch (e) {
      _log("Pipeline", "Error: $e");
    }
  }

  void _toggleCamera() {
    if (controller == null || !controller!.value.isInitialized) {
      _log("Camera", "Cannot toggle: Controller not initialized");
      return;
    }
    
    setState(() {
      _isCameraActive = !_isCameraActive;
    });
    _log("Camera", "Toggled camera: $_isCameraActive");
  }

  @override
  void dispose() {
    controller?.dispose();
    _osmTimer?.cancel();
    _geminiTimer?.cancel();
    _fishAudioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 7,
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
                            if (_statusText.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  _statusText,
                                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
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
              flex: 3,
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
