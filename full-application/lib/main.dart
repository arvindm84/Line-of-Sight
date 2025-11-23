// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:camera/camera.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'osm_service.dart';
// import 'gemini_service.dart';
// import 'fish_audio_service.dart';
//
// late List<CameraDescription> _cameras;
//
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//
//   // Load environment variables
//   await dotenv.load(fileName: ".env");
//
//   try {
//     _cameras = await availableCameras();
//     _log("Main", "Available cameras: ${_cameras.length}");
//   } catch (e) {
//     _log("Main", "Error getting cameras: $e");
//     _cameras = [];
//   }
//   runApp(const VisualGuideApp());
// }
//
// void _log(String category, String message) {
//   final timestamp = DateTime.now().toIso8601String();
//   print("[$timestamp] [$category] $message");
// }
//
// class VisualGuideApp extends StatelessWidget {
//   const VisualGuideApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Visual Guide',
//       theme: ThemeData.dark().copyWith(
//         scaffoldBackgroundColor: const Color(0xFF1A1A1A),
//       ),
//       home: const HomeScreen(),
//     );
//   }
// }
//
// class HomeScreen extends StatefulWidget {
//   const HomeScreen({super.key});
//
//   @override
//   State<HomeScreen> createState() => _HomeScreenState();
// }
//
// class _HomeScreenState extends State<HomeScreen> {
//   CameraController? controller;
//   final OSMService _osmService = OSMService();
//   late final GeminiService _geminiService;
//   late final FishAudioService _fishAudioService;
//
//   // State variables
//   String _statusText = "Initializing...";
//   List<POI> _nearbyPOIs = [];
//   bool _isScanning = false;
//   bool _isCameraActive = false;
//   Timer? _osmTimer;
//   Timer? _geminiTimer;
//   Position? _currentPosition;
//
//   @override
//   void initState() {
//     super.initState();
//     _initialize();
//   }
//
//   Future<void> _initialize() async {
//     _log("Init", "Starting initialization sequence...");
//
//     // Debug: Print loaded keys (not values)
//     _log("Init", "Loaded env keys: ${dotenv.env.keys.toList()}");
//
//     // Initialize Gemini service with API key
//     // Check for both common names just in case
//     final geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? dotenv.env['GEMINI_KEY'] ?? '';
//     if (geminiApiKey.isEmpty) {
//       setState(() => _statusText = "Error: Missing Gemini API key");
//       _log("Init", "Error: Missing Gemini API key. Available keys: ${dotenv.env.keys}");
//       return;
//     }
//     _geminiService = GeminiService(geminiApiKey);
//
//     // Initialize Fish Audio service with API key
//     final fishApiKey = dotenv.env['FISH_AUDIO_API_KEY'] ?? dotenv.env['FISH_API_KEY'] ?? '';
//     if (fishApiKey.isEmpty) {
//       setState(() => _statusText = "Error: Missing Fish Audio API key");
//       _log("Init", "Error: Missing Fish Audio API key. Available keys: ${dotenv.env.keys}");
//       return;
//     }
//     _fishAudioService = FishAudioService(fishApiKey);
//
//     await _requestPermissions();
//     await _initCamera();
//     await _startLocationTracking();
//
//     setState(() {
//       _isScanning = true;
//       _statusText = "Ready";
//     });
//
//     // Start OSM POI scanning every 5 seconds
//     _osmTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
//       _fetchPOIs();
//     });
//
//     // Start Gemini + Fish Audio pipeline every 60 seconds
//     _geminiTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
//       _processWithGeminiAndAudio();
//     });
//
//     // Perform first POI fetch immediately
//     _fetchPOIs();
//
//     // Perform first Gemini/Audio processing after a short delay
//     Future.delayed(const Duration(seconds: 2), () {
//       _processWithGeminiAndAudio();
//     });
//
//     _log("Init", "Initialization complete.");
//   }
//
//   Future<void> _requestPermissions() async {
//     _log("Perms", "Requesting permissions...");
//     Map<Permission, PermissionStatus> statuses = await [
//       Permission.camera,
//       Permission.location,
//     ].request();
//     _log("Perms", "Camera: ${statuses[Permission.camera]}, Location: ${statuses[Permission.location]}");
//   }
//
//   Future<void> _initCamera() async {
//     if (_cameras.isEmpty) {
//       _log("Camera", "No cameras available");
//       return;
//     }
//
//     // User requested simpler logic: controller = CameraController(cameras[0], ResolutionPreset.high, enableAudio: false);
//     // We will try to find back camera, but fallback to index 0 immediately if needed.
//
//     CameraDescription selectedCamera;
//     try {
//       selectedCamera = _cameras.firstWhere(
//         (camera) => camera.lensDirection == CameraLensDirection.back,
//       );
//       _log("Camera", "Found back camera: ${selectedCamera.name}");
//     } catch (e) {
//       _log("Camera", "Back camera not found, using first available camera");
//       selectedCamera = _cameras[0];
//     }
//
//     _log("Camera", "Initializing controller for ${selectedCamera.name}...");
//
//     controller = CameraController(
//       selectedCamera,
//       ResolutionPreset.high,
//       enableAudio: false,
//     );
//
//     try {
//       await controller!.initialize();
//       _log("Camera", "Camera initialized successfully (inactive on startup)");
//     } catch (e) {
//       _log("Camera", "Camera initialization error: $e");
//     }
//   }
//
//   Future<void> _startLocationTracking() async {
//     _log("Location", "Starting location tracking...");
//
//     // Check if location services are enabled
//     bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
//     if (!serviceEnabled) {
//       _log("Location", "Location services are disabled");
//       setState(() => _statusText = "Location services disabled. Please enable location.");
//       return;
//     }
//
//     // Check location permissions
//     LocationPermission permission = await Geolocator.checkPermission();
//     if (permission == LocationPermission.denied) {
//       permission = await Geolocator.requestPermission();
//       if (permission == LocationPermission.denied) {
//         _log("Location", "Location permission denied");
//         setState(() => _statusText = "Location permission denied");
//         return;
//       }
//     }
//
//     if (permission == LocationPermission.deniedForever) {
//       _log("Location", "Location permission denied forever");
//       setState(() => _statusText = "Location permission permanently denied");
//       return;
//     }
//
//     // Get initial position with timeout
//     try {
//       _log("Location", "Getting initial position...");
//       _currentPosition = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//         timeLimit: const Duration(seconds: 5),
//       );
//       _log("Location", "Initial position: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}");
//     } catch (e) {
//       _log("Location", "Error getting initial position: $e");
//     }
//
//     // Listen to location stream
//     // Removed distanceFilter to ensure we get updates even for small movements during testing
//     Geolocator.getPositionStream(
//         locationSettings: const LocationSettings(
//             accuracy: LocationAccuracy.high,
//             // distanceFilter: 10 // Commented out for debugging
//         )
//     ).listen((Position position) {
//       _currentPosition = position;
//       _log("Location", "Position update: ${position.latitude}, ${position.longitude}");
//     }, onError: (e) {
//       _log("Location", "Stream error: $e");
//     });
//   }
//
//   /// Fetch POIs from OpenStreetMap (called every 5 seconds)
//   Future<void> _fetchPOIs() async {
//     if (!mounted) return;
//
//     if (_currentPosition == null) {
//       _log("OSM", "No location available yet, skipping POI fetch");
//       return;
//     }
//
//     _log("OSM", "Fetching POIs for ${_currentPosition!.latitude}, ${_currentPosition!.longitude}");
//
//     try {
//       final results = await _osmService.getNearbyPOIs(
//           _currentPosition!.latitude,
//           _currentPosition!.longitude
//       );
//       _log("OSM", "Found ${results.length} POIs");
//
//       final top5 = results.take(5).toList();
//
//       if (top5.isEmpty) {
//         _log("OSM", "No POIs found nearby");
//         return;
//       }
//
//       _log("OSM", "Top 5: ${top5.map((p) => p.name).toList()}");
//
//       // Update state with the latest POIs
//       if (mounted) {
//         setState(() {
//           _nearbyPOIs = top5;
//         });
//       }
//     } catch (e) {
//       _log("OSM", "Fetch error: $e");
//     }
//   }
//
//   /// Process POIs with Gemini and Fish Audio (called every 60 seconds)
//   Future<void> _processWithGeminiAndAudio() async {
//     if (!mounted) return;
//
//     if (_nearbyPOIs.isEmpty) {
//       _log("Pipeline", "No POIs available to process");
//       return;
//     }
//
//     _log("Pipeline", "Starting Gemini + Fish Audio pipeline...");
//     _log("Pipeline", "Processing ${_nearbyPOIs.length} POIs");
//
//     try {
//       // Step 2: Convert to conversational text using Gemini
//       _log("Pipeline", "Sending to Gemini...");
//       final conversationalText = await _geminiService.convertToConversation(_nearbyPOIs);
//       _log("Pipeline", "Gemini response: $conversationalText");
//
//       // Step 3: Convert text to speech using Fish Audio
//       _log("Pipeline", "Sending to Fish Audio...");
//       await _fishAudioService.textToSpeech(conversationalText);
//       _log("Pipeline", "Fish Audio TTS complete");
//
//       _log("Pipeline", "Pipeline complete");
//     } catch (e) {
//       _log("Pipeline", "Error: $e");
//     }
//   }
//
//   void _toggleCamera() {
//     if (controller == null || !controller!.value.isInitialized) {
//       _log("Camera", "Cannot toggle: Controller not initialized");
//       return;
//     }
//
//     setState(() {
//       _isCameraActive = !_isCameraActive;
//     });
//     _log("Camera", "Toggled camera: $_isCameraActive");
//   }
//
//   @override
//   void dispose() {
//     controller?.dispose();
//     _osmTimer?.cancel();
//     _geminiTimer?.cancel();
//     _fishAudioService.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: SafeArea(
//         child: Column(
//           children: [
//             Expanded(
//               flex: 7,
//               child: Container(
//                 color: Colors.black,
//                 child: _isCameraActive && controller != null && controller!.value.isInitialized
//                     ? ClipRect(
//                         child: OverflowBox(
//                           alignment: Alignment.center,
//                           child: FittedBox(
//                             fit: BoxFit.cover,
//                             child: SizedBox(
//                               width: MediaQuery.of(context).size.width,
//                               height: MediaQuery.of(context).size.width * controller!.value.aspectRatio,
//                               child: CameraPreview(controller!),
//                             ),
//                           ),
//                         ),
//                       )
//                     : Center(
//                         child: Column(
//                           mainAxisAlignment: MainAxisAlignment.center,
//                           children: [
//                             Icon(
//                               Icons.camera_alt,
//                               size: 80,
//                               color: Colors.white30,
//                             ),
//                             const SizedBox(height: 16),
//                             Text(
//                               _isCameraActive ? 'Starting camera...' : 'Camera inactive',
//                               style: TextStyle(
//                                 color: Colors.white38,
//                                 fontSize: 16,
//                               ),
//                             ),
//                             if (_statusText.isNotEmpty)
//                               Padding(
//                                 padding: const EdgeInsets.only(top: 8.0),
//                                 child: Text(
//                                   _statusText,
//                                   style: TextStyle(color: Colors.redAccent, fontSize: 12),
//                                 ),
//                               ),
//                           ],
//                         ),
//                       ),
//               ),
//             ),
//
//             // Divider
//             Container(
//               height: 2,
//               decoration: BoxDecoration(
//                 gradient: LinearGradient(
//                   colors: [
//                     const Color(0xFF667eea),
//                     const Color(0xFF764ba2),
//                   ],
//                 ),
//               ),
//             ),
//
//             // BOTTOM SECTION: Start/Stop Button
//             Expanded(
//               flex: 3,
//               child: Container(
//                 width: double.infinity,
//                 decoration: BoxDecoration(
//                   gradient: LinearGradient(
//                     begin: Alignment.topLeft,
//                     end: Alignment.bottomRight,
//                     colors: [
//                       const Color(0xFF1A1A1A),
//                       const Color(0xFF2A2A2A),
//                     ],
//                   ),
//                 ),
//                 child: Center(
//                   child: ElevatedButton(
//                     onPressed: _toggleCamera,
//                     style: ElevatedButton.styleFrom(
//                       padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 20),
//                       backgroundColor: Colors.transparent,
//                       shadowColor: Colors.transparent,
//                       shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(30),
//                       ),
//                     ).copyWith(
//                       backgroundColor: MaterialStateProperty.resolveWith<Color>(
//                         (Set<MaterialState> states) {
//                           return Colors.transparent;
//                         },
//                       ),
//                     ),
//                     child: Container(
//                       padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
//                       decoration: BoxDecoration(
//                         gradient: LinearGradient(
//                           colors: _isCameraActive
//                               ? [
//                                   const Color(0xFFea5455),
//                                   const Color(0xFFf07167),
//                                 ]
//                               : [
//                                   const Color(0xFF667eea),
//                                   const Color(0xFF764ba2),
//                                 ],
//                         ),
//                         borderRadius: BorderRadius.circular(30),
//                         boxShadow: [
//                           BoxShadow(
//                             color: (_isCameraActive
//                                 ? const Color(0xFFea5455)
//                                 : const Color(0xFF667eea)).withOpacity(0.5),
//                             blurRadius: 20,
//                             spreadRadius: 2,
//                           ),
//                         ],
//                       ),
//                       child: Row(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           Icon(
//                             _isCameraActive ? Icons.stop : Icons.play_arrow,
//                             color: Colors.white,
//                             size: 28,
//                           ),
//                           const SizedBox(width: 12),
//                           Text(
//                             _isCameraActive ? 'STOP' : 'START',
//                             style: const TextStyle(
//                               color: Colors.white,
//                               fontSize: 20,
//                               fontWeight: FontWeight.bold,
//                               letterSpacing: 1.5,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }





import 'dart:async';
import 'dart:ui' as ui; // For Image handling
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Import your existing services
import 'osm_service.dart';
import 'gemini_service.dart';
import 'fish_audio_service.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load Environment Variables
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Error loading .env: $e");
  }

  // 2. Find Cameras
  try {
    _cameras = await availableCameras();
  } catch (e) {
    debugPrint("Camera Error: $e");
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
      debugShowCheckedModeBanner: false,
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
  // === HARDWARE & AI ===
  CameraController? controller;
  late FlutterVision vision;

  // === SERVICES ===
  final OSMService _osmService = OSMService();
  late GeminiService _geminiService;
  late FishAudioService _fishAudioService;
  final DangerAnalyzer _analyzer = DangerAnalyzer();
  final StickyTracker _tracker = StickyTracker();

  // === STATE ===
  bool _isLoaded = false;       // Are models/camera ready?
  bool _isActive = false;       // Is the "Start" button pressed?
  bool _isDetecting = false;    // Is YOLO currently processing a frame?
  String _statusText = "Initializing...";

  // === DATA ===
  List<Map<String, dynamic>> _yoloResults = [];
  Map<int, int> _trackAssignments = {};
  CameraImage? _cameraImage;    // For painting boxes
  String _globalDangerStatus = "SAFE";

  // === TIMERS ===
  Timer? _environmentTimer;     // The slow loop (Gemini/OSM)
  DateTime? _lastDangerAudio;   // To prevent spamming "Stop! Stop!"

  // === DIAGNOSTICS ===
  int _fps = 0;
  int _inferenceMs = 0;
  DateTime? _lastFrameTime;

  @override
  void initState() {
    super.initState();
    _initializeSystem();
  }

  // 1. INITIALIZE EVERYTHING (BUT DO NOT START SCANNING)
  Future<void> _initializeSystem() async {
    // A. API Keys
    final gKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final fKey = dotenv.env['FISH_AUDIO_API_KEY'] ?? '';
    if (gKey.isEmpty || fKey.isEmpty) {
      setState(() => _statusText = "Error: Missing API Keys");
      return;
    }
    _geminiService = GeminiService(gKey);
    _fishAudioService = FishAudioService(fKey);

    // B. Permissions
    await [
      Permission.camera,
      Permission.location,
      Permission.microphone
    ].request();

    // C. Camera
    if (_cameras.isEmpty) {
      setState(() => _statusText = "No Camera Found");
      return;
    }
    controller = CameraController(_cameras[0], ResolutionPreset.high, enableAudio: false);
    await controller!.initialize();

    // D. Vision Model
    vision = FlutterVision();
    await vision.loadYoloModel(
        modelPath: "assets/yolov8m.tflite", // Ensure this matches your asset
        labels: "assets/labels.txt",
        modelVersion: "yolov8",
        quantization: false,
        numThreads: 4,
        useGpu: true
    );

    setState(() {
      _isLoaded = true;
      _statusText = "System Ready. Press Start.";
    });
  }

  // 2. TOGGLE LOGIC (THE START/STOP BUTTON)
  void _toggleSystem() async {
    if (!_isLoaded) return;

    if (_isActive) {
      // === STOPPING ===
      setState(() {
        _isActive = false;
        _statusText = "Stopping...";
        _yoloResults = [];
        _cameraImage = null;
        _globalDangerStatus = "SAFE";
      });

      // Stop Loops
      _environmentTimer?.cancel();
      await controller?.stopImageStream();
      await _fishAudioService.stopAudio();

      setState(() => _statusText = "System Idle");

    } else {
      // === STARTING ===
      setState(() {
        _isActive = true;
        _statusText = "Starting Vision...";
      });

      // A. Start Fast Loop (YOLO)
      await controller?.startImageStream((image) => _yoloLoop(image));

      // B. Start Slow Loop (Gemini/OSM) - Runs every 20 seconds
      _environmentTimer = Timer.periodic(const Duration(seconds: 20), (t) => _environmentLoop());

      // Trigger first environment scan immediately
      _environmentLoop();

      setState(() => _statusText = "Scanning...");
    }
  }

  // 3. FAST LOOP: YOLO OBJECT DETECTION (~30 FPS)
  void _yoloLoop(CameraImage image) async {
    if (_isDetecting || !_isActive) return;
    _isDetecting = true;
    final stopwatch = Stopwatch()..start();

    try {
      // A. Run Inference
      final result = await vision.yoloOnFrame(
        bytesList: image.planes.map((plane) => plane.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: 0.4,
        confThreshold: 0.35,
        classThreshold: 0.4,
      );

      // B. Track Objects
      List<Rect> rects = result.map((r) => Rect.fromLTRB(r["box"][0], r["box"][1], r["box"][2], r["box"][3])).toList();
      Map<int, int> assignments = _tracker.update(rects);
      _analyzer.cleanOldHistory(assignments.values.toSet());

      // C. Analyze Danger
      String maxDanger = "SAFE";
      String dangerLabel = "";

      for (int i = 0; i < result.length; i++) {
        int? id = assignments[i];
        if (id == null) continue;

        double h = result[i]["box"][3] - result[i]["box"][1];
        var analysis = _analyzer.analyze(id, result[i]["tag"], h, image.height.toDouble());

        if (analysis["status"] == "CRITICAL") {
          maxDanger = "CRITICAL";
          dangerLabel = result[i]["tag"];
        } else if (analysis["status"] == "WARNING" && maxDanger != "CRITICAL") {
          maxDanger = "WARNING";
        }
      }

      // D. IMMEDIATE AUDIO INTERRUPT (Safety First)
      if (maxDanger == "CRITICAL") {
        if (_lastDangerAudio == null || DateTime.now().difference(_lastDangerAudio!).inSeconds > 3) {
          _lastDangerAudio = DateTime.now();
          debugPrint("🚨 CRITICAL DANGER: $dangerLabel");
          // Assuming you added an interrupt parameter to FishAudioService,
          // otherwise regular TTS is fine, it just might queue.
          _fishAudioService.textToSpeech("Stop! $dangerLabel ahead!");
        }
      }

      // E. Update UI
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _yoloResults = result;
          _trackAssignments = assignments;
          _cameraImage = image;
          _globalDangerStatus = maxDanger;
          _inferenceMs = stopwatch.elapsedMilliseconds;

          if (_lastFrameTime != null) {
            int gap = DateTime.now().difference(_lastFrameTime!).inMilliseconds;
            if (gap > 0) _fps = (1000 / gap).round();
          }
          _lastFrameTime = DateTime.now();
        });
      }

    } catch (e) {
      debugPrint("YOLO Loop Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

  // 4. SLOW LOOP: CONTEXT (GEMINI + OSM) (~Every 20s)
  Future<void> _environmentLoop() async {
    if (!_isActive) return;
    // Don't describe scenery if a car is about to hit the user
    if (_globalDangerStatus == "CRITICAL") return;

    try {
      // A. Get Location
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      // B. Get Places
      List<POI> pois = await _osmService.getNearbyPOIs(pos.latitude, pos.longitude);
      final topPois = pois.take(4).toList();

      // C. Get Description
      String desc = await _geminiService.convertToConversation(topPois);

      // D. Speak (Only if still safe)
      if (_isActive && _globalDangerStatus != "CRITICAL") {
        debugPrint("🌍 ENV AUDIO: $desc");
        await _fishAudioService.textToSpeech(desc);
      }

    } catch (e) {
      debugPrint("Env Loop Error: $e");
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    vision.closeYoloModel();
    _environmentTimer?.cancel();
    _fishAudioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Loading Screen (UPDATED TO SHOW ERRORS)
    if (!_isLoaded) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // If status contains "Error", show red icon, else show spinner
            if (_statusText.contains("Error") || _statusText.contains("Missing"))
              const Icon(Icons.error_outline, color: Colors.red, size: 50)
            else
              const CircularProgressIndicator(),

            const SizedBox(height: 20),

            // Show the actual status text so you know what's wrong!
            Text(
              _statusText,
              style: TextStyle(
                  color: _statusText.contains("Error") ? Colors.redAccent : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold
              ),
              textAlign: TextAlign.center,
            ),
          ],
        )),
      );
    }


    final Size screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // A. CAMERA FEED (Zoomed to Cover)
          if (controller != null && controller!.value.isInitialized)
            SizedBox(
              width: screenSize.width,
              height: screenSize.height,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller!.value.previewSize!.height,
                  height: controller!.value.previewSize!.width,
                  child: CameraPreview(controller!),
                ),
              ),
            ),

          // B. DRAWING OVERLAY (Only when active)
          if (_isActive && _cameraImage != null)
            SizedBox(
              width: screenSize.width,
              height: screenSize.height,
              child: CustomPaint(
                painter: ResultsPainter(
                    _yoloResults,
                    _trackAssignments,
                    _analyzer,
                    _cameraImage!.height.toDouble(),
                    _cameraImage!.width.toDouble(),
                    screenSize
                ),
              ),
            ),

          // C. STATUS BAR (Top)
          Positioned(
            top: 50, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                  color: _getStatusColor().withOpacity(0.9),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10)]
              ),
              child: Text(
                _isActive ? (_globalDangerStatus == "SAFE" ? "PATH CLEAR" : _globalDangerStatus) : "SYSTEM IDLE",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
            ),
          ),

          // D. START/STOP BUTTON (Bottom)
          Positioned(
            bottom: 40, left: 20, right: 20,
            child: SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _toggleSystem,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _isActive ? Colors.redAccent : Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 10
                ),
                icon: Icon(_isActive ? Icons.stop_circle : Icons.play_circle, size: 30),
                label: Text(
                  _isActive ? "STOP GUIDING" : "START GUIDING",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          // E. DEBUG INFO (Small text above button)
          Positioned(
            bottom: 110, left: 20,
            child: _isActive ? Container(
              padding: const EdgeInsets.all(5),
              color: Colors.black54,
              child: Text(
                "FPS: $_fps | Inf: ${_inferenceMs}ms | YOLOv8m",
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ) : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    if (!_isActive) return Colors.grey;
    if (_globalDangerStatus == "CRITICAL") return Colors.red;
    if (_globalDangerStatus == "WARNING") return Colors.orange;
    return Colors.green;
  }
}

// ==================== HELPER CLASSES (PASTE THESE AT THE BOTTOM) ====================

// 1. LOGIC: DANGER ANALYZER
class DangerAnalyzer {
  static const double DANGER_ZONE_RATIO = 0.45;
  static const double APPROACH_THRESHOLD = 0.05;

  final List<String> targetClasses = [
    "person", "bicycle", "car", "motorcycle", "bus", "train", "truck",
    "laptop", "tv", "cell phone", "keyboard", "mouse"
  ];

  final Map<int, List<double>> _history = {};

  Map<String, String> analyze(int trackId, String label, double currentH, double frameH) {
    if (!targetClasses.contains(label)) return {"status": "IGNORE", "message": ""};

    double heightRatio = currentH / frameH;
    if (heightRatio > DANGER_ZONE_RATIO) {
      return {"status": "CRITICAL", "message": "STOP! $label"};
    }

    if (!_history.containsKey(trackId)) _history[trackId] = [];
    _history[trackId]!.add(currentH);
    if (_history[trackId]!.length > 10) _history[trackId]!.removeAt(0);

    if (_history[trackId]!.length >= 3) {
      double pastH = _history[trackId]![0];
      if (pastH > 0) {
        double growth = (currentH - pastH) / pastH;
        if (growth > APPROACH_THRESHOLD) {
          return {"status": "WARNING", "message": "Approaching"};
        }
      }
    }

    if (["laptop", "tv", "cell phone"].contains(label)) return {"status": "INFO", "message": "Detected"};

    return {"status": "SAFE", "message": ""};
  }

  void cleanOldHistory(Set<int> activeIds) {
    _history.removeWhere((key, value) => !activeIds.contains(key));
  }
}

// 2. LOGIC: STICKY TRACKER
class StickyTracker {
  int _nextId = 0;
  final Map<int, Offset> _objects = {};
  final Map<int, int> _disappearedCount = {};
  final int maxDisappearedFrames = 10;

  Map<int, int> update(List<Rect> rects) {
    if (rects.isEmpty) {
      for (int id in _objects.keys) {
        _disappearedCount[id] = (_disappearedCount[id] ?? 0) + 1;
      }
      _cleanup();
      return {};
    }

    List<Offset> inputCentroids = rects.map((r) => r.center).toList();
    Map<int, int> assignments = {};
    Set<int> usedExistingIds = {};
    Set<int> usedInputIndexes = {};

    if (_objects.isNotEmpty) {
      for (int i = 0; i < inputCentroids.length; i++) {
        Offset inputCenter = inputCentroids[i];
        int? bestId;
        double shortestDist = 100.0;

        _objects.forEach((id, existingCenter) {
          if (usedExistingIds.contains(id)) return;
          double dist = (inputCenter - existingCenter).distance;
          if (dist < shortestDist) {
            shortestDist = dist;
            bestId = id;
          }
        });

        if (bestId != null) {
          assignments[i] = bestId!;
          _objects[bestId!] = inputCenter;
          _disappearedCount[bestId!] = 0;
          usedExistingIds.add(bestId!);
          usedInputIndexes.add(i);
        }
      }
    }

    for (int i = 0; i < inputCentroids.length; i++) {
      if (!usedInputIndexes.contains(i)) {
        int newId = _nextId++;
        _objects[newId] = inputCentroids[i];
        _disappearedCount[newId] = 0;
        assignments[i] = newId;
      }
    }
    for (int id in _objects.keys) {
      if (!usedExistingIds.contains(id)) {
        _disappearedCount[id] = (_disappearedCount[id] ?? 0) + 1;
      }
    }
    _cleanup();
    return assignments;
  }

  void _cleanup() {
    _objects.removeWhere((id, _) => (_disappearedCount[id] ?? 0) > maxDisappearedFrames);
    _disappearedCount.removeWhere((id, count) => count > maxDisappearedFrames);
  }
}

// 3. VISUALS: RESULTS PAINTER
class ResultsPainter extends CustomPainter {
  final List<Map<String, dynamic>> results;
  final Map<int, int> assignments;
  final DangerAnalyzer analyzer;
  final double camHeight;
  final double camWidth;
  final Size screenSize;

  ResultsPainter(this.results, this.assignments, this.analyzer, this.camHeight, this.camWidth, this.screenSize);

  @override
  void paint(Canvas canvas, Size size) {
    double baseScaleX = screenSize.width / camHeight;
    double baseScaleY = screenSize.height / camWidth;
    double fittedScale = (baseScaleX > baseScaleY) ? baseScaleX : baseScaleY;

    double offsetX = (screenSize.width - (camHeight * fittedScale)) / 2;
    double offsetY = (screenSize.height - (camWidth * fittedScale)) / 2;

    for (int i = 0; i < results.length; i++) {
      final box = results[i]["box"];
      String tagName = results[i]["tag"];
      int trackId = assignments[i] ?? -1;

      double objH = box[3] - box[1];
      var analysis = analyzer.analyze(trackId, tagName, objH, camHeight);
      String status = analysis['status']!;

      if (status == "IGNORE") continue;

      Color color = Colors.greenAccent;
      double stroke = 2.0;

      if (status == "WARNING") { color = Colors.orangeAccent; stroke = 4.0; }
      if (status == "CRITICAL") { color = Colors.redAccent; stroke = 6.0; }
      if (status == "INFO") { color = Colors.cyanAccent; stroke = 3.0; }

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke;

      double x1 = box[0] * fittedScale + offsetX;
      double y1 = box[1] * fittedScale + offsetY;
      double x2 = box[2] * fittedScale + offsetX;
      double y2 = box[3] * fittedScale + offsetY;

      Rect scaledRect = Rect.fromLTRB(x1, y1, x2, y2);
      canvas.drawRect(scaledRect, paint);

      String conf = "";
      if (results[i]["box"].length > 4) conf = "${(results[i]["box"][4] * 100).toInt()}%";

      final textPainter = TextPainter(
        text: TextSpan(
          text: "$tagName $conf",
          style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(scaledRect.left, scaledRect.top - 28, textPainter.width + 10, 28),
              const Radius.circular(6)
          ),
          Paint()..color = color.withOpacity(0.85)
      );
      textPainter.paint(canvas, Offset(scaledRect.left + 5, scaledRect.top - 26));
    }
  }

  @override
  bool shouldRepaint(ResultsPainter oldDelegate) => true;
}