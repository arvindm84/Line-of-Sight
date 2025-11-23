// import 'dart:async';
// import 'dart:math' as math;
// import 'package:flutter/material.dart';
// import 'package:camera/camera.dart';
// import 'package:flutter_vision/flutter_vision.dart';
// import 'package:permission_handler/permission_handler.dart';
// // import 'package:audioplayers/audioplayers.dart'; // Uncomment if you add audio sound
//
// late List<CameraDescription> cameras;
//
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   // Initialize cameras before app starts
//   try {
//     cameras = await availableCameras();
//   } on CameraException catch (e) {
//     debugPrint('Error: $e.code\nError Message: $e.description');
//   }
//   runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: DangerCamHome()));
// }
//
// // ==================== 1. DART PORT OF PYTHON DANGER ANALYZER ====================
// class DangerAnalyzerDart {
//   // Configuration from your Python script
//   static const double DANGER_ZONE_RATIO = 0.4;
//   static const double APPROACH_THRESHOLD = 0.02;
//
//   // History storage: Map<TrackId, List<Heights>>
//   final Map<int, List<double>> _history = {};
//
//   // Returns map with 'status' (SAFE/WARNING/CRITICAL) and 'message'
//   Map<String, String> analyze(int trackId, double currentH, double frameH) {
//     // --- 1. IMMEDIATE PROXIMITY CHECK ---
//     double heightRatio = currentH / frameH;
//
//     if (heightRatio > DANGER_ZONE_RATIO) {
//       return {
//         "status": "CRITICAL",
//         "message": "STOP! Object directly in front!"
//       };
//     }
//
//     // --- 2. APPROACH SPEED CHECK ---
//     // Ensure history list exists for this ID
//     if (!_history.containsKey(trackId)) {
//       _history[trackId] = [];
//     }
//
//     _history[trackId]!.add(currentH);
//
//     // Keep list short (max 10 frames, same as Python)
//     if (_history[trackId]!.length > 10) {
//       _history[trackId]!.removeAt(0);
//     }
//
//     // Need at least 5 frames to judge speed
//     if (_history[trackId]!.length >= 5) {
//       // Compare current size to size 5 frames ago (index 0 of the trimmed list)
//       double pastH = _history[trackId]![0];
//
//       // Avoid division by zero if something weird happens
//       if (pastH > 0) {
//         double growth = (currentH - pastH) / pastH;
//         if (growth > APPROACH_THRESHOLD) {
//           return {"status": "WARNING", "message": "Approaching fast"};
//         }
//       }
//     }
//
//     return {"status": "SAFE", "message": ""};
//   }
//
//   // Clean up old IDs that haven't been seen in a while to prevent memory leaks
//   void cleanOldHistory(Set<int> activeIds) {
//     _history.removeWhere((key, value) => !activeIds.contains(key));
//   }
// }
//
// // ==================== 2. SIMPLE DART TRACKER ====================
// // TFLite doesn't track IDs natively. We need a basic centroid tracker.
// class SimpleTrackerDart {
//   int _nextId = 0;
//   // Stores the last known center position of an object ID
//   Map<int, Offset> _objects = {};
//   int maxDisappearedFrames = 10;
//   Map<int, int> _disappearedCount = {};
//
//   // Returns a map linking index of current frame detections to a persistent ID
//   Map<int, int> update(List<Rect> rects) {
//     if (rects.isEmpty) {
//       for (int id in _objects.keys) {
//         _disappearedCount[id] = (_disappearedCount[id] ?? 0) + 1;
//       }
//       _cleanup();
//       return {};
//     }
//
//     // Calculate centers of new rects
//     List<Offset> inputCentroids = rects.map((r) => r.center).toList();
//     Map<int, int> assignments = {};
//     Set<int> usedExistingIds = {};
//     Set<int> usedInputIndexes = {};
//
//     // Match existing objects to new centroids based on distance
//     if (_objects.isNotEmpty) {
//       for (int i = 0; i < inputCentroids.length; i++) {
//         Offset inputCenter = inputCentroids[i];
//         int? bestId;
//         double shortestDist = 100.0; // Max distance to consider a match (pixels)
//
//         _objects.forEach((id, existingCenter) {
//           if (usedExistingIds.contains(id)) return;
//
//           double dist = (inputCenter - existingCenter).distance;
//           if (dist < shortestDist) {
//             shortestDist = dist;
//             bestId = id;
//           }
//         });
//
//         if (bestId != null) {
//           // Found a match
//           assignments[i] = bestId!;
//           _objects[bestId!] = inputCenter; // Update position
//           _disappearedCount[bestId!] = 0; // Reset disappeared count
//           usedExistingIds.add(bestId!);
//           usedInputIndexes.add(i);
//         }
//       }
//     }
//
//     // Register new objects for unmatched inputs
//     for (int i = 0; i < inputCentroids.length; i++) {
//       if (!usedInputIndexes.contains(i)) {
//         int newId = _nextId++;
//         _objects[newId] = inputCentroids[i];
//         _disappearedCount[newId] = 0;
//         assignments[i] = newId;
//       }
//     }
//
//     // Mark unmatched existing objects as disappeared
//     for (int id in _objects.keys) {
//       if (!usedExistingIds.contains(id)) {
//         _disappearedCount[id] = (_disappearedCount[id] ?? 0) + 1;
//       }
//     }
//
//     _cleanup();
//     return assignments;
//   }
//
//   void _cleanup() {
//     List<int> toRemove = [];
//     _disappearedCount.forEach((id, count) {
//       if(count > maxDisappearedFrames) toRemove.add(id);
//     });
//     for (var id in toRemove) {
//       _objects.remove(id);
//       _disappearedCount.remove(id);
//     }
//   }
// }
//
//
// // ==================== 3. MAIN APP UI & DETECTION LOOP ====================
// class DangerCamHome extends StatefulWidget {
//   const DangerCamHome({super.key});
//
//   @override
//   State<DangerCamHome> createState() => _DangerCamHomeState();
// }
//
// class _DangerCamHomeState extends State<DangerCamHome> {
//   late CameraController controller;
//   late FlutterVision vision;
//   bool isLoaded = false;
//   bool isDetecting = false;
//   // final player = AudioPlayer(); // Uncomment for audio
//
//   List<Map<String, dynamic>> yoloResults = [];
//   CameraImage? cameraImage;
//
//   // Logic Instances
//   final DangerAnalyzerDart analyzer = DangerAnalyzerDart();
//   final SimpleTrackerDart tracker = SimpleTrackerDart();
//
//   @override
//   void initState() {
//     super.initState();
//     initSetup();
//   }
//
//   initSetup() async {
//     await Permission.camera.request();
//     // await Permission.microphone.request(); // Needed if using AudioPlayer
//
//     vision = FlutterVision();
//
//     // 1. Load the "Baked" TFLite Model
//     // Make sure the filenames match exactly what is in your assets folder
//     await vision.loadYoloModel(
//         modelPath: "assets/yolo_danger.tflite",
//         labels: "assets/labels.txt",
//         modelVersion: "yolov8",
//         quantization: true, // Important for int8 models
//         numThreads: 4, // Use more threads for speed
//         useGpu: true   // Important for performance
//     );
//
//     // 2. Initialize Camera
//     controller = CameraController(cameras[0], ResolutionPreset.medium, enableAudio: false);
//     await controller.initialize();
//
//     setState(() {
//       isLoaded = true;
//     });
//
//     // 3. Start Detection Loop
//     startDetection();
//   }
//
//   void startDetection() {
//     if (!isLoaded || isDetecting) return;
//
//     // Frame throttling variable
//     int frameCount = 0;
//
//     controller.startImageStream((CameraImage image) async {
//       // THROTTLING: Only process every 3rd frame to prevent UI freeze
//       // Phone cameras run fast (30-60fps), TFLite runs slower (~15fps).
//       frameCount++;
//       if (frameCount % 3 != 0) return;
//
//       if (isDetecting) return;
//       isDetecting = true;
//
//       // Keep reference to current image dimensions for painting later
//       cameraImage = image;
//
//       // Run YOLO on the frame
//       final result = await vision.yoloOnFrame(
//         bytesList: image.planes.map((plane) => plane.bytes).toList(),
//         imageHeight: image.height,
//         imageWidth: image.width,
//         // Adjust thresholds as needed
//         iouThreshold: 0.4,
//         confThreshold: 0.3,
//         classThreshold: 0.4,
//       );
//
//       // Check for critical triggers in the results *before* setting state
//       // This mimicks your Python "AUDIO TRIGGER" print
//       bool criticalFound = false;
//       // We need the tracker here to know which IDs are which to check analyzer history
//       List<Rect> tempRects = result.map((r) => Rect.fromLTRB(r["box"][0], r["box"][1], r["box"][2], r["box"][3])).toList();
//       Map<int, int> tempAssignments = tracker.update(tempRects);
//       Set<int> activeIds = tempAssignments.values.toSet();
//
//       for (int i = 0; i < result.length; i++) {
//         int trackId = tempAssignments[i] ?? -1;
//         if(trackId == -1) continue;
//         // YOLO TFLite returns normalized coordinates (0.0 - 1.0) sometimes,
//         // depending on model export settings. Assuming pixel values here relative to camera image size.
//         double h = result[i]["box"][3] - result[i]["box"][1];
//         // NOTE: Camera image height/width might be swapped depending on orientation. Using height for calculation.
//         var analysis = analyzer.analyze(trackId, h, image.height.toDouble());
//         if (analysis["status"] == "CRITICAL") {
//           criticalFound = true;
//           debugPrint("🔊 AUDIO TRIGGER: ${analysis['message']} (${result[i]['tag']})");
//         }
//       }
//
//       // Cleanup old history
//       analyzer.cleanOldHistory(activeIds);
//
//       if (criticalFound) {
//         // Optional: Play sound here
//         // player.play(AssetSource('alert.mp3'));
//       }
//
//       if (mounted) {
//         setState(() {
//           yoloResults = result;
//         });
//       }
//       isDetecting = false;
//     });
//   }
//
//   @override
//   void dispose() {
//     controller.stopImageStream();
//     controller.dispose();
//     vision.closeYoloModel();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     if (!isLoaded) {
//       return const Scaffold(
//           backgroundColor: Colors.black,
//           body: Center(child: CircularProgressIndicator()));
//     }
//
//     final Size screenSize = MediaQuery.of(context).size;
//
//     return Scaffold(
//       body: Stack(
//         children: [
//           // 1. The Camera Feed
//           SizedBox(
//               width: screenSize.width,
//               height: screenSize.height,
//               child: CameraPreview(controller)
//           ),
//
//           // 2. The Painting Layer (Boxes and Text)
//           if (cameraImage != null)
//             SizedBox(
//               width: screenSize.width,
//               height: screenSize.height,
//               child: CustomPaint(
//                 painter: ResultsPainter(
//                     yoloResults,
//                     analyzer,
//                     tracker, // Pass tracker to maintain IDs in painter
//                     cameraImage!.height.toDouble(),
//                     cameraImage!.width.toDouble(),
//                     screenSize
//                 ),
//               ),
//             ),
//
//           // Header
//           Positioned(
//               top: 40, left: 20,
//               child: Container(
//                 padding: const EdgeInsets.all(8),
//                 color: Colors.black54,
//                 child: const Text("Blind Assist - Danger Tracking",
//                     style: TextStyle(color: Colors.white, fontSize: 18)),
//               )
//           )
//         ],
//       ),
//     );
//   }
// }
//
// // ==================== 4. CUSTOM PAINTER FOR VISUALS ====================
// class ResultsPainter extends CustomPainter {
//   final List<Map<String, dynamic>> results;
//   final DangerAnalyzerDart analyzer;
//   final SimpleTrackerDart tracker;
//   final double camHeight;
//   final double camWidth;
//   final Size screenSize;
//
//   ResultsPainter(this.results, this.analyzer, this.tracker, this.camHeight, this.camWidth, this.screenSize);
//
//   @override
//   void paint(Canvas canvas, Size size) {
//     // 1. Convert raw YOLO results to Rects for the tracker
//     List<Rect> currentRects = [];
//     for (var result in results) {
//       final box = result["box"];
//       currentRects.add(Rect.fromLTRB(box[0], box[1], box[2], box[3]));
//     }
//
//     // 2. Get persistent IDs from tracker
//     // Note: We already updated tracker in main loop, but calling it again
//     // with same data is okay, or we could pass the assignments map down.
//     // For simplicity of this single-file example, we re-run tracking association.
//     Map<int, int> assignments = tracker.update(currentRects);
//
//     // Calculations for scaling camera coordinates to screen coordinates
//     // Camera images are often rotated 90 degrees relative to portrait phone screen.
//     // We assume portrait orientation here.
//     double scaleX = screenSize.width / camHeight;
//     double scaleY = screenSize.height / camWidth;
//
//     for (int i = 0; i < results.length; i++) {
//       final box = results[i]["box"];
//       String tagName = results[i]["tag"];
//       int trackId = assignments[i] ?? -1;
//       if(trackId == -1) continue;
//
//       double x1 = box[0];
//       double y1 = box[1];
//       double x2 = box[2];
//       double y2 = box[3];
//       double objH = y2 - y1;
//
//       // --- GET STATUS FROM ANALYZER ---
//       // Using camHeight as the frame reference frame
//       var analysis = analyzer.analyze(trackId, objH, camHeight);
//       String status = analysis['status']!;
//       String message = analysis['message']!;
//
//       // Determine Color based on status
//       Color color = Colors.green; // SAFE
//       if (status == "WARNING") color = Colors.yellow;
//       if (status == "CRITICAL") color = Colors.red;
//
//       // --- DRAWING ---
//       final paint = Paint()
//         ..color = color
//         ..style = PaintingStyle.stroke
//         ..strokeWidth = 3.0;
//
//       // Scale and rotate coordinates for display
//       // NOTE: This scaling might need tweaking depending on specific device camera orientation
//       Rect scaledRect = Rect.fromLTRB(
//           x1 * scaleX,
//           y1 * scaleY,
//           x2 * scaleX,
//           y2 * scaleY
//       );
//
//       canvas.drawRect(scaledRect, paint);
//
//       // Draw Text Label
//       String labelText = "#$trackId $tagName";
//       if (status != "SAFE") {
//         labelText += "\n[$status] $message";
//       }
//
//       TextSpan span = TextSpan(
//           style: TextStyle(
//               color: color,
//               fontSize: 16,
//               fontWeight: FontWeight.bold,
//               backgroundColor: Colors.black54
//           ),
//           text: labelText
//       );
//       TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
//       tp.layout();
//       // Draw text above the box
//       tp.paint(canvas, Offset(scaledRect.left, scaledRect.top - tp.height));
//     }
//   }
//
//   @override
//   bool shouldRepaint(ResultsPainter oldDelegate) => true;
// }


import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:permission_handler/permission_handler.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Error: $e.code\nError Message: $e.description');
  }
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: DangerCamHome()));
}

// ==================== 1. LOGIC: INTELLIGENT ANALYZER ====================
class DangerAnalyzer {
  static const double DANGER_ZONE_RATIO = 0.45;
  static const double APPROACH_THRESHOLD = 0.05;

  // Combined Danger + Tech items
  final List<String> targetClasses = [
    "person", "bicycle", "car", "motorcycle", "bus", "train", "truck",
    "laptop", "tv", "cell phone", "keyboard", "mouse" // Tech items added
  ];

  final Map<int, List<double>> _history = {};

  Map<String, String> analyze(int trackId, String label, double currentH, double frameH) {
    // 1. FILTER: Only show what we care about
    if (!targetClasses.contains(label)) {
      // If it's a "Vase" or "Chair", ignore it to clean up the screen
      return {"status": "IGNORE", "message": ""};
    }

    // 2. CHECK PROXIMITY
    double heightRatio = currentH / frameH;
    if (heightRatio > DANGER_ZONE_RATIO) {
      return {"status": "CRITICAL", "message": "STOP! $label"};
    }

    // 3. CHECK SPEED
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

    // Special color for Tech items
    if (["laptop", "tv", "cell phone"].contains(label)) {
      return {"status": "INFO", "message": "Detected"};
    }

    return {"status": "SAFE", "message": ""};
  }

  void cleanOldHistory(Set<int> activeIds) {
    _history.removeWhere((key, value) => !activeIds.contains(key));
  }
}

// ==================== 2. LOGIC: STICKY TRACKER ====================
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

// ==================== 3. UI: MAIN SCREEN ====================
class DangerCamHome extends StatefulWidget {
  const DangerCamHome({super.key});

  @override
  State<DangerCamHome> createState() => _DangerCamHomeState();
}

class _DangerCamHomeState extends State<DangerCamHome> {
  late CameraController controller;
  late FlutterVision vision;
  bool isLoaded = false;
  bool isDetecting = false;

  List<Map<String, dynamic>> yoloResults = [];
  Map<int, int> trackAssignments = {};
  CameraImage? cameraImage;
  String globalStatus = "SCANNING";
  Color statusColor = Colors.blue;

  int fps = 0;
  int inferenceMs = 0;
  DateTime? lastFrameTime;

  final DangerAnalyzer analyzer = DangerAnalyzer();
  final StickyTracker tracker = StickyTracker();

  @override
  void initState() {
    super.initState();
    initSetup();
  }

  initSetup() async {
    await Permission.camera.request();
    vision = FlutterVision();

    // 640px HIGH RES MODEL
    await vision.loadYoloModel(
        modelPath: "assets/yolov8m.tflite",
        labels: "assets/labels.txt",
        modelVersion: "yolov8",
        quantization: false,
        numThreads: 6,
        useGpu: true
    );

    controller = CameraController(cameras[0], ResolutionPreset.high, enableAudio: false);
    await controller.initialize();

    setState(() { isLoaded = true; });
    startDetection();
  }

  void startDetection() {
    if (!isLoaded || isDetecting) return;

    controller.startImageStream((CameraImage image) async {
      if (isDetecting) return;
      isDetecting = true;
      final stopwatch = Stopwatch()..start();

      try {
        final result = await vision.yoloOnFrame(
          bytesList: image.planes.map((plane) => plane.bytes).toList(),
          imageHeight: image.height,
          imageWidth: image.width,
          iouThreshold: 0.4,
          confThreshold: 0.30, // Increased to 30% to kill "Vase" noise
          classThreshold: 0.30,
        );

        List<Rect> rects = result.map((r) => Rect.fromLTRB(r["box"][0], r["box"][1], r["box"][2], r["box"][3])).toList();
        Map<int, int> assignments = tracker.update(rects);
        analyzer.cleanOldHistory(assignments.values.toSet());

        String maxDanger = "SAFE";
        bool techFound = false;

        for (int i = 0; i < result.length; i++) {
          int? id = assignments[i];
          if (id == null) continue;

          double h = result[i]["box"][3] - result[i]["box"][1];
          var analysis = analyzer.analyze(id, result[i]["tag"], h, image.height.toDouble());

          if (analysis["status"] == "CRITICAL") maxDanger = "CRITICAL";
          else if (analysis["status"] == "WARNING" && maxDanger != "CRITICAL") maxDanger = "WARNING";
          else if (analysis["status"] == "INFO") techFound = true;
        }

        stopwatch.stop();
        if (mounted) {
          setState(() {
            yoloResults = result;
            trackAssignments = assignments;
            cameraImage = image;
            inferenceMs = stopwatch.elapsedMilliseconds;

            if (lastFrameTime != null) {
              int gap = DateTime.now().difference(lastFrameTime!).inMilliseconds;
              if (gap > 0) fps = (1000 / gap).round();
            }
            lastFrameTime = DateTime.now();

            globalStatus = maxDanger;
            if (globalStatus == "SAFE") {
              statusColor = techFound ? Colors.blue : Colors.green;
              if(techFound) globalStatus = "TECH FOUND";
            }
            if (globalStatus == "WARNING") statusColor = Colors.orange;
            if (globalStatus == "CRITICAL") statusColor = Colors.red;
          });
        }
      } catch (e) {
        debugPrint("Error: $e");
      } finally {
        isDetecting = false;
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    vision.closeYoloModel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Loading Screen
    if (!isLoaded || !controller.value.isInitialized) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator())
      );
    }

    final Size screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // 2. The Camera Feed (FIXED ZOOM)
          // We force the camera to "Cover" the screen without manual math.
          // This aligns perfectly with the Painter's logic.
          SizedBox(
            width: screenSize.width,
            height: screenSize.height,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                // Note: We swap width/height because Android cameras
                // natively capture in Landscape, but we are in Portrait.
                width: controller.value.previewSize!.height,
                height: controller.value.previewSize!.width,
                child: CameraPreview(controller),
              ),
            ),
          ),

          // 3. The Drawing Layer
          if (cameraImage != null)
            SizedBox(
              width: screenSize.width,
              height: screenSize.height,
              child: CustomPaint(
                painter: ResultsPainter(
                    yoloResults,
                    trackAssignments,
                    analyzer,
                    cameraImage!.height.toDouble(),
                    cameraImage!.width.toDouble(),
                    screenSize,
                    // We don't need the manual zoom scale anymore
                    // because we aligned the camera using FittedBox above.
                    1.0
                ),
              ),
            ),

          // 4. TOP BAR (Status)
          Positioned(
            top: 50, left: 20, right: 20,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 10)]
              ),
              child: Center(
                child: Text(
                  globalStatus == "SAFE" ? "PATH CLEAR" : globalStatus,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
              ),
            ),
          ),

          // 5. BOTTOM INFO
          Positioned(
            bottom: 30, left: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("FPS: $fps  |  ${inferenceMs}ms", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text("Model: YOLOv8m (High Res)", style: const TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

// ==================== 4. VISUALS: PAINTER (CORRECTED SCALING) ====================
class ResultsPainter extends CustomPainter {
  final List<Map<String, dynamic>> results;
  final Map<int, int> assignments;
  final DangerAnalyzer analyzer;
  final double camHeight;
  final double camWidth;
  final Size screenSize;
  final double zoomScale; // The fix for "Bad Drawing"

  ResultsPainter(this.results, this.assignments, this.analyzer, this.camHeight, this.camWidth, this.screenSize, this.zoomScale);

  @override
  void paint(Canvas canvas, Size size) {
    // Math to map the Camera Coordinates to the Zoomed/Cropped Screen
    double baseScaleX = screenSize.width / camHeight;
    double baseScaleY = screenSize.height / camWidth;

    // We apply the extra zoom factor used in Transform.scale
    // But we need to handle the offset caused by centering
    // This is a simplified "Cover" mapping:

    double fittedScale = math.max(baseScaleX, baseScaleY);

    // Calculate offsets to center the image
    double offsetX = (screenSize.width - (camHeight * fittedScale)) / 2;
    double offsetY = (screenSize.height - (camWidth * fittedScale)) / 2;

    for (int i = 0; i < results.length; i++) {
      final box = results[i]["box"];
      String tagName = results[i]["tag"];
      int trackId = assignments[i] ?? -1;

      // Analyze
      double objH = box[3] - box[1];
      var analysis = analyzer.analyze(trackId, tagName, objH, camHeight);
      String status = analysis['status']!;

      if (status == "IGNORE") continue; // Don't draw Vases!

      Color color = Colors.greenAccent;
      double stroke = 2.0;

      if (status == "WARNING") { color = Colors.orangeAccent; stroke = 4.0; }
      if (status == "CRITICAL") { color = Colors.redAccent; stroke = 6.0; }
      if (status == "INFO") { color = Colors.cyanAccent; stroke = 3.0; }

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke;

      // Apply the "Fitted Cover" math
      double x1 = box[0] * fittedScale + offsetX;
      double y1 = box[1] * fittedScale + offsetY;
      double x2 = box[2] * fittedScale + offsetX;
      double y2 = box[3] * fittedScale + offsetY;

      Rect scaledRect = Rect.fromLTRB(x1, y1, x2, y2);
      canvas.drawRect(scaledRect, paint);

      // Label
      String conf = "";
      if (results[i]["box"].length > 4) {
        conf = "${(results[i]["box"][4] * 100).toInt()}%";
      }

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