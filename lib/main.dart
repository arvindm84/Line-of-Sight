import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/main_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request permissions
  await Permission.camera.request();
  await Permission.location.request();

  // Get cameras
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(VisualGuideApp(camera: firstCamera));
}

class VisualGuideApp extends StatelessWidget {
  final CameraDescription camera;

  const VisualGuideApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visual Guide',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: MainScreen(camera: camera),
      debugShowCheckedModeBanner: false,
    );
  }
}
