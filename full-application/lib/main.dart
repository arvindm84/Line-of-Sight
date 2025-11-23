import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'osm_service.dart';
import 'gemini_service.dart';
import 'fish_audio_service.dart';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Error loading .env: $e");
  }
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
  // === HARDWARE ===
  CameraController? controller;
  late FlutterVision vision;

  // === SERVICES ===
  final OSMService _osmService = OSMService();
  late GeminiService _geminiService;
  late FishAudioService _fishAudioService;
  final DangerAnalyzer _analyzer = DangerAnalyzer();
  final StickyTracker _tracker = StickyTracker();

  // === STATE ===
  bool _isLoaded = false;
  bool _isActive = false;
  bool _isDetecting = false;
  String _statusText = "Initializing...";

  // === DATA ===
  List<Map<String, dynamic>> _yoloResults = [];
  Map<int, int> _trackAssignments = {};
  CameraImage? _cameraImage;
  String _globalDangerStatus = "SAFE";
  String _lastDangerStatus = "SAFE";

  // === AUDIO QUEUE SYSTEM ===
  String? _queuedEnvironmentText;
  DateTime? _lastDangerAudioTime;

  // === TIMERS ===
  Timer? _visualTimer;      // Vision (Images)
  Timer? _environmentTimer;
  int _visualCycleCount = 0;

  // === DIAGNOSTICS ===
  int _fps = 0;
  int _inferenceMs = 0;
  DateTime? _lastFrameTime;

  @override
  void initState() {
    super.initState();
    _initializeSystem();
  }

  Future<void> _initializeSystem() async {
    final gKey = dotenv.env['GEMINI_API_KEY'] ?? dotenv.env['GEMINI_KEY'] ?? '';
    final fKey = dotenv.env['FISH_AUDIO_KEY'] ?? dotenv.env['FISH_AUDIO_API_KEY'] ?? '';

    if (gKey.isEmpty || fKey.isEmpty) {
      setState(() => _statusText = "Error: Missing API Keys");
      return;
    }
    _geminiService = GeminiService(gKey);
    _fishAudioService = FishAudioService(fKey);

    await [Permission.camera, Permission.location, Permission.microphone].request();

    if (_cameras.isEmpty) {
      setState(() => _statusText = "No Camera Found");
      return;
    }
    controller = CameraController(_cameras[0], ResolutionPreset.high, enableAudio: false);
    await controller!.initialize();

    vision = FlutterVision();
    await vision.loadYoloModel(
        modelPath: "assets/yolov8m.tflite",
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

  void _toggleSystem() async {
    if (!_isLoaded) return;

    if (_isActive) {
      // === STOP ===
      setState(() {
        _isActive = false;
        _statusText = "System Idle";
        _yoloResults = [];
        _cameraImage = null;
        _globalDangerStatus = "SAFE";
        _queuedEnvironmentText = null;
        _lastDangerAudioTime = null;
      });

      // 1. Cancel Timers
      _environmentTimer?.cancel();
      _visualTimer?.cancel();

      // 2. Safe Camera Stop
      if (controller != null && controller!.value.isStreamingImages) {
        try {
          await controller!.stopImageStream();
        } catch (e) {
          debugPrint("Camera Stop Error: $e");
        }
      }

      // 3. Stop Audio
      await _fishAudioService.stopAudio();

      // 4. Reset AI Memory
      _tracker.reset();
      _analyzer.reset();

    } else {
      // === START ===
      setState(() {
        _isActive = true;
        _statusText = "Scanning...";
      });

      // 1. Start Fast Loop (YOLO)
      try {
        await controller?.startImageStream((image) => _yoloLoop(image));
      } catch (e) {
        debugPrint("Camera Start Error: $e");
      }

      // 2. Start Map Loop (Every 30s)
      _environmentTimer = Timer.periodic(const Duration(seconds: 30), (t) => _mapsLoop());

      // 3. Start Visual Loop (Every 15s)
      // We delay it by 2 seconds so it doesn't fight with the Map loop immediately
      Future.delayed(const Duration(seconds: 2), () {
        if (_isActive) {
          _visualLoop(); // Run once immediately
          _visualTimer = Timer.periodic(const Duration(seconds: 15), (t) => _visualLoop());
        }
      });
    }
  }

  Future<void> _runUnifiedSchedule() async {
    // 1. Run Visual Description
    await _visualLoop();
    
    // 2. Increment & Check for Map Description
    _visualCycleCount++;
    if (_visualCycleCount >= 2) {
      _visualCycleCount = 0;
      debugPrint("Cycle 2 reached (40s): Triggering Map Description...");
      await _mapsLoop();
    }
  }

// === LOOP 1: FAST DANGER DETECTION (YOLO) ===
  void _yoloLoop(CameraImage image) async {
    // Safety check: If stopped, drop frame immediately
    if (_isDetecting || !_isActive) return;

    _isDetecting = true;
    final stopwatch = Stopwatch()..start();

    try {
      final result = await vision.yoloOnFrame(
        bytesList: image.planes.map((plane) => plane.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: 0.4,
        confThreshold: 0.35,
        classThreshold: 0.4,
      );

      // ... (Rest of your YOLO logic stays the same) ...
      // Copy the logic from your previous code for tracking/analyzing
      // I am truncating here for brevity, but keep your existing logic!

      List<Rect> rects = result.map((r) => Rect.fromLTRB(r["box"][0], r["box"][1], r["box"][2], r["box"][3])).toList();
      Map<int, int> assignments = _tracker.update(rects);
      _analyzer.cleanOldHistory(assignments.values.toSet());

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

      if (maxDanger == "CRITICAL") {
        if (_lastDangerAudioTime == null || DateTime.now().difference(_lastDangerAudioTime!).inSeconds > 3 && dangerLabel != "person") {
          _lastDangerAudioTime = DateTime.now();
          debugPrint("🚨 DANGER INTERRUPT: $dangerLabel");
          _fishAudioService.textToSpeech("Stop! $dangerLabel ahead!", interrupt: true);
        }
      }
      else if (_lastDangerStatus == "CRITICAL" && maxDanger == "SAFE") {
        if (_queuedEnvironmentText != null) {
          debugPrint("✅ Safe. Playing queued description.");
          _fishAudioService.textToSpeech("Safe now. $_queuedEnvironmentText");
          _queuedEnvironmentText = null;
        }
      }
      _lastDangerStatus = maxDanger;

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
      debugPrint("YOLO Error: $e");
    } finally {
      _isDetecting = false;
    }
  }

// === VISUAL LOOP (Medium Priority) ===
  Future<void> _visualLoop() async {
    if (!_isActive || controller == null || !controller!.value.isInitialized) return;

    // If Danger is active, don't even queue visuals.
    if (_globalDangerStatus == "CRITICAL") return;

    try {
      // 1. Stop Stream to take Pic
      if (controller!.value.isStreamingImages) {
        await controller?.stopImageStream();
      }

      // 2. Take Pic
      XFile imageFile = await controller!.takePicture();

      // 3. CRITICAL CHECK: Did user press STOP while we were taking the pic?
      if (!_isActive) {
        File(imageFile.path).delete(); // Clean up
        return; // EXIT IMMEDIATELY. DO NOT RESTART STREAM.
      }

      // 4. Restart Stream
      await controller?.startImageStream((image) => _yoloLoop(image));

      // 5. Process Image
      String desc = await _geminiService.describeEnvironmentFromImage(imageFile);
      File(imageFile.path).delete();

      // 6. Speak
      debugPrint("📸 Queuing Visual Description...");
      _fishAudioService.textToSpeech(desc, interrupt: false);

    } catch (e) {
      debugPrint("Visual Error: $e");
      // Attempt to recover stream if we are still active
      if (_isActive && controller != null && !controller!.value.isStreamingImages) {
        try {
          await controller?.startImageStream((image) => _yoloLoop(image));
        } catch (err) { /* Ignore */ }
      }
    }
  }

  // === MAP LOOP (Low Priority) ===
  Future<void> _mapsLoop() async {
    if (!_isActive || _globalDangerStatus == "CRITICAL") return;

    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      List<POI> pois = await _osmService.getNearbyPOIs(pos.latitude, pos.longitude);
      final topPois = pois.take(3).toList(); // Take top 3

      if (topPois.isNotEmpty) {
        String desc = await _geminiService.convertToConversation(topPois);

        // Add to Queue (interrupt: false)
        // If Visual is speaking, this will wait until Visual is done!
        debugPrint("🗺️ Queuing Map Description...");
        _fishAudioService.textToSpeech("Nearby: $desc", interrupt: false);
      }
    } catch (e) {
      debugPrint("Map Error: $e");
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    vision.closeYoloModel();
    _visualTimer?.cancel();
    _fishAudioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_statusText.contains("Error"))
              const Icon(Icons.error, color: Colors.red, size: 50)
            else
              const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(_statusText, style: const TextStyle(color: Colors.white)),
          ],
        )),
      );
    }

    final Size screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // 1. CAMERA
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

          // 2. BOXES
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

          // 3. HUD
          Positioned(
            top: 50, left: 20, right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                  color: _getStatusColor().withOpacity(0.9),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [const BoxShadow(color: Colors.black45, blurRadius: 10)]
              ),
              child: Text(
                _isActive ? (_globalDangerStatus == "SAFE" ? "PATH CLEAR" : _globalDangerStatus) : "SYSTEM IDLE",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // 4. BUTTON
          Positioned(
            bottom: 40 + screenSize.height * 0.05, left: 20, right: 20,
            child: SizedBox(
              height: 72,
              child: ElevatedButton.icon(
                onPressed: _toggleSystem,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _isActive ? Colors.redAccent : Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
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

          Positioned(
            bottom: 170, left: 20,
            child: _isActive ? Text(
              "FPS: $_fps | Inf: ${_inferenceMs}ms",
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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

// ==================== HELPER CLASSES ====================

class DangerAnalyzer {
  static const double DANGER_ZONE_RATIO = 0.45;
  static const double APPROACH_THRESHOLD = 0.05;
  final List<String> targetClasses = ["person", "bicycle", "car", "motorcycle", "bus", "train", "truck", "laptop", "tv", "cell phone"];
  final Map<int, List<double>> _history = {};

  Map<String, String> analyze(int trackId, String label, double currentH, double frameH) {
    if (!targetClasses.contains(label)) return {"status": "IGNORE", "message": ""};

    double heightRatio = currentH / frameH;
    if (heightRatio > DANGER_ZONE_RATIO) return {"status": "CRITICAL", "message": "STOP! $label"};

    if (!_history.containsKey(trackId)) _history[trackId] = [];
    _history[trackId]!.add(currentH);
    if (_history[trackId]!.length > 10) _history[trackId]!.removeAt(0);

    if (_history[trackId]!.length >= 3) {
      double growth = (currentH - _history[trackId]![0]) / _history[trackId]![0];
      if (growth > APPROACH_THRESHOLD) return {"status": "WARNING", "message": "Approaching"};
    }

    if (["laptop", "tv", "cell phone"].contains(label)) return {"status": "INFO", "message": "Detected"};
    return {"status": "SAFE", "message": ""};
  }
  void reset() {
    _history.clear();
  }
  void cleanOldHistory(Set<int> activeIds) => _history.removeWhere((key, value) => !activeIds.contains(key));
}

class StickyTracker {
  int _nextId = 0;
  final Map<int, Offset> _objects = {};
  final Map<int, int> _disappearedCount = {};

  Map<int, int> update(List<Rect> rects) {
    if (rects.isEmpty) {
      _disappearedCount.updateAll((key, value) => value + 1);
      _cleanup();
      return {};
    }
    List<Offset> inputs = rects.map((r) => r.center).toList();
    Map<int, int> assignments = {};
    Set<int> usedIds = {};
    Set<int> usedInputs = {};

    if (_objects.isNotEmpty) {
      for (int i = 0; i < inputs.length; i++) {
        int? bestId;
        double minDst = 100.0;
        _objects.forEach((id, center) {
          if (usedIds.contains(id)) return;
          double dst = (inputs[i] - center).distance;
          if (dst < minDst) { minDst = dst; bestId = id; }
        });
        if (bestId != null) {
          assignments[i] = bestId!;
          _objects[bestId!] = inputs[i];
          _disappearedCount[bestId!] = 0;
          usedIds.add(bestId!);
          usedInputs.add(i);
        }
      }
    }

    for (int i = 0; i < inputs.length; i++) {
      if (!usedInputs.contains(i)) {
        int id = _nextId++;
        _objects[id] = inputs[i];
        _disappearedCount[id] = 0;
        assignments[i] = id;
      }
    }
    _objects.keys.where((id) => !usedIds.contains(id)).forEach((id) => _disappearedCount[id] = (_disappearedCount[id] ?? 0) + 1);
    _cleanup();
    return assignments;
  }
  void reset() {
    _nextId = 0;
    _objects.clear();
    _disappearedCount.clear();
  }
  void _cleanup() {
    _objects.removeWhere((id, _) => (_disappearedCount[id] ?? 0) > 10);
    _disappearedCount.removeWhere((id, c) => c > 10);
  }
}

class ResultsPainter extends CustomPainter {
  final List<Map<String, dynamic>> results;
  final Map<int, int> assignments;
  final DangerAnalyzer analyzer;
  final double h;
  final double w;
  final Size screen;

  ResultsPainter(this.results, this.assignments, this.analyzer, this.h, this.w, this.screen);

  @override
  void paint(Canvas canvas, Size size) {
    double scale = screen.width / h > screen.height / w ? screen.width / h : screen.height / w;
    double dx = (screen.width - h * scale) / 2;
    double dy = (screen.height - w * scale) / 2;

    for (int i = 0; i < results.length; i++) {
      final box = results[i]["box"];
      int id = assignments[i] ?? -1;
      var analysis = analyzer.analyze(id, results[i]["tag"], box[3] - box[1], h);
      if (analysis['status'] == "IGNORE") continue;

      Color c = analysis['status'] == "CRITICAL" ? Colors.red : (analysis['status'] == "WARNING" ? Colors.orange : Colors.green);
      final paint = Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 3.0;

      Rect r = Rect.fromLTRB(box[0] * scale + dx, box[1] * scale + dy, box[2] * scale + dx, box[3] * scale + dy);
      canvas.drawRect(r, paint);

      TextPainter(
          text: TextSpan(text: "${results[i]['tag']} ${analysis['status']}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr
      )..layout()..paint(canvas, Offset(r.left, r.top - 20));
    }
  }
  @override
  bool shouldRepaint(ResultsPainter old) => true;
}