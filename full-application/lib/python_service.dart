import 'dart:convert';
import 'dart:io';

/// Service to interact with Python backend scripts
class PythonService {
  final String pythonPath;
  final String scriptDirectory;
  
  PythonService({
    required this.pythonPath,
    required this.scriptDirectory,
  });
  
  /// Execute the Python frame processing script
  /// 
  /// Returns a map with:
  /// - success: bool
  /// - audio_files: List<String> (paths to generated audio)
  /// - text: String (generated text from Gemini)
  /// - error: String? (error message if failed)
  Future<Map<String, dynamic>> processFrame(String framePath) async {
    print('PythonService: Processing frame: $framePath');
    
    final scriptPath = '$scriptDirectory${Platform.pathSeparator}process_frame.py';
    
    // Verify script exists
    if (!await File(scriptPath).exists()) {
      return {
        'success': false,
        'error': 'Python script not found: $scriptPath'
      };
    }
    
    try {
      // Run Python script
      final result = await Process.run(
        pythonPath,
        [scriptPath, framePath],
        workingDirectory: scriptDirectory,
      );
      
      print('PythonService: Python exit code: ${result.exitCode}');
      
      if (result.exitCode != 0) {
        print('PythonService: Python stderr: ${result.stderr}');
        return {
          'success': false,
          'error': 'Python script failed: ${result.stderr}',
        };
      }
      
      // Parse JSON output from Python
      final output = result.stdout.toString();
      print('PythonService: Python stdout length: ${output.length} chars');
      
      // Extract JSON from output (between RESULT: markers)
      final jsonStart = output.indexOf('{');
      final jsonEnd = output.lastIndexOf('}') + 1;
      
      if (jsonStart == -1 || jsonEnd <= jsonStart) {
        print('PythonService: Could not find JSON in output');
        return {
          'success': false,
          'error': 'Invalid Python output format',
        };
      }
      
      final jsonStr = output.substring(jsonStart, jsonEnd);
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      print('PythonService: Parsed result: ${parsed['success']}');
      if (parsed['success'] == true && parsed['audio_files'] != null) {
        print('PythonService: Audio files: ${parsed['audio_files']}');
      }
      
      return parsed;
      
    } catch (e, stackTrace) {
      print('PythonService: Exception: $e');
      print('PythonService: Stack trace: $stackTrace');
      return {
        'success': false,
        'error': 'Failed to execute Python script: $e',
      };
    }
  }
  
  /// Get the Python interpreter path
  /// 
  /// First tries to use venv, then falls back to system python
  static Future<String> getPythonPath(String projectRoot) async {
    // Try venv first (Windows)
    final venvPython = '$projectRoot${Platform.pathSeparator}venv${Platform.pathSeparator}Scripts${Platform.pathSeparator}python.exe';
    if (await File(venvPython).exists()) {
      print('PythonService: Using venv Python: $venvPython');
      return venvPython;
    }
    
    // Try system Python on Windows
    if (Platform.isWindows) {
      // Try common locations
      final commonPaths = [
        'python',  // In PATH
        'python3', // In PATH
        r'C:\Python311\python.exe',
        r'C:\Python310\python.exe',
        r'C:\Python39\python.exe',
      ];
      
      for (final path in commonPaths) {
        try {
          final result = await Process.run(path, ['--version']);
          if (result.exitCode == 0) {
            print('PythonService: Using system Python: $path');
            return path;
          }
        } catch (e) {
          continue;
        }
      }
    }
    
    // Default fallback
    print('PythonService: Using default Python: python');
    return 'python';
  }
}
