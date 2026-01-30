import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:sensors_plus/sensors_plus.dart';

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
        primaryColor: Colors.yellowAccent,
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

  // === LISTENERS ===
  StreamSubscription? _accelerometerSubscription;
  StreamSubscription? _volumeSubscription;
  DateTime? _lastShakeTime;

  // === SERVICES ===
  final OSMService _osmService = OSMService();
  late GeminiService _geminiService;
  late FishAudioService _fishAudioService;
  final DangerAnalyzer _analyzer = DangerAnalyzer();
  final StickyTracker _tracker = StickyTracker();

  // === STATE ===
  bool _isLoaded = false;
  bool _isActive = false; // "Start/Stop" switch
  bool _isDetecting = false;
  String _statusText = "Initializing...";

  // === BUTTON FEEDBACK STATE ===
  String _buttonFeedback = "";
  Timer? _feedbackClearTimer;

  // === DATA ===
  List<Map<String, dynamic>> _yoloResults = [];
  Map<int, int> _trackAssignments = {};
  CameraImage? _cameraImage;
  String _globalDangerStatus = "SAFE";
  File? _lastGeminiImage;

  // === TIMERS ===
  Timer? _volumeDoublePressTimer;
  DateTime? _lastDangerAudioTime;

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
    final gKey = "AIzaSyCic1UHAphNgeKC9feOkkM1BRycK_Mw3b0";
    final fKey = "b34f820bdc61448e96e1235f94fa60d0";

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

    // Use High Resolution for good Gemini photos
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

    _setupVolumeTrigger();
    _setupShakeTrigger();

    setState(() {
      _isLoaded = true;
      _statusText = "Ready. Press Start.";
    });
  }

  // === 1. VOLUME BUTTON LOGIC ===
  void _setupVolumeTrigger() {
    try {
      _volumeSubscription = FlutterVolumeController.addListener((volume) {
        // Only trigger actions if system is ACTIVE
        if (_isActive) {
          _onVolumePress();
        } else {
          // If system is OFF, volume buttons just act as a Start Switch
          _toggleSystem();
        }
      });
    } catch (e) {
      debugPrint("Volume Init Error: $e");
    }
  }

  void _onVolumePress() {
    _showButtonFeedback("Button Detected...", Colors.grey);

    if (_volumeDoublePressTimer != null && _volumeDoublePressTimer!.isActive) {
      _volumeDoublePressTimer?.cancel();
      _onDoublePressLocation();
    } else {
      _volumeDoublePressTimer = Timer(const Duration(milliseconds: 400), () {
        _onSinglePressVision();
      });
    }
  }

  void _showButtonFeedback(String text, Color color) {
    setState(() => _buttonFeedback = text);
    _feedbackClearTimer?.cancel();
    _feedbackClearTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _buttonFeedback = "");
    });
  }

  // === 2. SHAKE LOGIC ===
  void _setupShakeTrigger() {
    _accelerometerSubscription = userAccelerometerEvents.listen((UserAccelerometerEvent event) {
      double force = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      if (force > 12.0) {
        DateTime now = DateTime.now();
        if (_lastShakeTime == null || now.difference(_lastShakeTime!) > const Duration(seconds: 2)) {
          _lastShakeTime = now;
          _showButtonFeedback("📳 SHAKE DETECTED", Colors.yellow);
          _toggleSystem();
          if (_isActive) _fishAudioService.textToSpeech("System Started", interrupt: true);
          else _fishAudioService.textToSpeech("System Stopped", interrupt: true);
        }
      }
    });
  }

  // === 3. CORE ACTIONS (BUTTON ONLY) ===

  Future<void> _onSinglePressVision() async {
    // STRICT CHECK: Must be Active to run
    if (!_isActive) return;

    _showButtonFeedback("📸 SINGLE CLICK: Vision", Colors.cyan);
    debugPrint("📸 Vision Scan Triggered");

    if (controller == null || !controller!.value.isInitialized) return;

    _fishAudioService.textToSpeech("Capturing...", interrupt: true);

    try {
      // 1. Pause Stream
      bool wasStreaming = controller!.value.isStreamingImages;
      if (wasStreaming) await controller!.stopImageStream();

      // 2. Capture
      XFile image = await controller!.takePicture();

      setState(() {
        if (_lastGeminiImage != null) _lastGeminiImage!.delete();
        _lastGeminiImage = File(image.path);
      });

      // 3. Resume Stream Immediately
      if (wasStreaming && _isActive) {
        await controller!.startImageStream((image) => _yoloLoop(image));
      }

      // 4. Analyze (Gemini)
      String desc = await _geminiService.describeEnvironmentFromImage(image);

      // 5. Speak (STRICT CHECK: Am I still active?)
      if (mounted && _isActive) {
        _fishAudioService.textToSpeech(desc, interrupt: false);
      } else {
        debugPrint("🛑 Stop pressed during Gemini. Speech Cancelled.");
      }

    } catch (e) {
      debugPrint("Vision Error: $e");
      _showButtonFeedback("Error: $e", Colors.red);
    }
  }

  Future<void> _onDoublePressLocation() async {
    if (!_isActive) return;

    _showButtonFeedback("📍 DOUBLE CLICK: Location", Colors.green);
    _fishAudioService.textToSpeech("Checking location...", interrupt: true);

    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      List<POI> pois = await _osmService.getNearbyPOIs(pos.latitude, pos.longitude);

      // STRICT CHECK
      if (!_isActive) return;

      if (pois.isNotEmpty) {
        String desc = await _geminiService.convertToConversation(pois.take(3).toList());
        _fishAudioService.textToSpeech("Nearby: $desc", interrupt: false);
      } else {
        _fishAudioService.textToSpeech("No known landmarks nearby.");
      }
    } catch (e) {
      _fishAudioService.textToSpeech("Could not get location.");
    }
  }

  // === 4. SYSTEM CONTROL ===

  void _toggleSystem() async {
    if (!_isLoaded) return;

    if (_isActive) {
      // === STOP COMMAND ===
      debugPrint("🛑 SYSTEM STOPPING...");

      // 1. Kill Audio
      await _fishAudioService.stopAudio();

      // 2. Update State
      setState(() {
        _isActive = false;
        _statusText = "System Idle";
        _yoloResults = [];
        _globalDangerStatus = "SAFE";
        _buttonFeedback = "🛑 STOPPED";
      });

      // 3. Stop Camera Stream
      if (controller!.value.isStreamingImages) {
        await controller!.stopImageStream();
      }

      // 4. Reset Trackers
      _tracker.reset();
      _analyzer.reset();

    } else {
      // === START COMMAND ===
      debugPrint("▶️ SYSTEM STARTING...");
      setState(() {
        _isActive = true;
        _statusText = "Scanning...";
        _buttonFeedback = "▶️ STARTED";
      });

      try {
        await controller?.startImageStream((image) => _yoloLoop(image));
        // NOTE: No timers here anymore. Only YOLO runs automatically.
      } catch (e) {
        debugPrint("Camera Start Error: $e");
      }
    }
  }

  void _yoloLoop(CameraImage image) async {
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

      // Only speak danger if Active
      if (maxDanger == "CRITICAL" && _isActive) {
        if (_lastDangerAudioTime == null || DateTime.now().difference(_lastDangerAudioTime!).inSeconds > 3) {
          if (dangerLabel != "person") {
            _lastDangerAudioTime = DateTime.now();
            _fishAudioService.textToSpeech("Stop! $dangerLabel ahead!", interrupt: true);
          }
        }
      }

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

  @override
  void dispose() {
    controller?.dispose();
    vision.closeYoloModel();
    _fishAudioService.dispose();
    _accelerometerSubscription?.cancel();
    _volumeSubscription?.cancel();
    _lastGeminiImage?.delete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
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

          // 4. BUTTON FEEDBACK (New!)
          if (_buttonFeedback.isNotEmpty)
            Positioned(
              top: 130, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                  child: Text(_buttonFeedback, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ),

          // 5. BUTTON
          Positioned(
            bottom: 40 + screenSize.height * 0.05, left: 0, right: 0,
            child: Center(
              child: SizedBox(
                height: 72,
                width: 200,
                child: ElevatedButton.icon(
                  onPressed: _toggleSystem,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _isActive ? Colors.redAccent : Colors.blueAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
                      elevation: 10
                  ),
                  icon: Icon(_isActive ? Icons.stop_circle : Icons.play_circle, size: 30),
                  label: Text(
                    _isActive ? "STOP" : "START",
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),

          // 6. GEMINI PREVIEW
          if (_lastGeminiImage != null)
            Positioned(
              bottom: 40, left: 20,
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.yellowAccent, width: 2),
                    borderRadius: BorderRadius.circular(10),
                    image: DecorationImage(
                        image: FileImage(_lastGeminiImage!),
                        fit: BoxFit.cover
                    )
                ),
                child: const Align(
                  alignment: Alignment.bottomCenter,
                  child: Text("Vision", style: TextStyle(backgroundColor: Colors.black54, color: Colors.white, fontSize: 10)),
                ),
              ),
            ),

          // 7. STATS
          if (_isActive)
            Positioned(
              bottom: 140, left: 0, right: 0,
              child: Text(
                "FPS: $_fps | Inf: ${_inferenceMs}ms",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
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

// === HELPERS ===
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
  void reset() { _history.clear(); }
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
  void reset() { _nextId = 0; _objects.clear(); _disappearedCount.clear(); }
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
    double scale = math.max(screen.width / h, screen.height / w);
    double dx = (screen.width - h * scale) / 2;
    double dy = (screen.height - w * scale) / 2;
    for (int i = 0; i < results.length; i++) {
      final box = results[i]["box"];
      int id = assignments[i] ?? -1;
      var analysis = analyzer.analyze(id, results[i]["tag"], box[3] - box[1], h);
      if (analysis['status'] == "IGNORE") continue;
      Color c = analysis['status'] == "CRITICAL" ? Colors.redAccent : (analysis['status'] == "WARNING" ? Colors.orangeAccent : Colors.greenAccent);
      final paint = Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 3.0;
      Rect r = Rect.fromLTRB(box[0] * scale + dx, box[1] * scale + dy, box[2] * scale + dx, box[3] * scale + dy);
      canvas.drawRect(r, paint);
      TextPainter(text: TextSpan(text: "${results[i]['tag']} ${analysis['status']}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(r.left, r.top - 20));
    }
  }
  @override
  bool shouldRepaint(ResultsPainter old) => true;
}
