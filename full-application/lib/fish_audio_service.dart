import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

class FishAudioService {
  final String apiKey;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  FishAudioService(this.apiKey);

  /// Convert text to speech using Fish Audio API and play it
  Future<void> textToSpeech(String text) async {
    if (text.isEmpty) {
      print("No text to convert to speech");
      return;
    }

    try {
      print("Converting text to speech: $text");
      
      // Call Fish Audio API
      final response = await http.post(
        Uri.parse('https://api.fish.audio/v1/tts'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': text,
          'reference_id': '8ef4a238714b45718ce04243307c57a7', // Same as Python code
          'format': 'mp3',
        }),
      );

      if (response.statusCode == 200) {
        // Save audio to temporary file
        final directory = await getTemporaryDirectory();
        final audioFile = File('${directory.path}/output.mp3');
        await audioFile.writeAsBytes(response.bodyBytes);
        
        print("Audio saved to ${audioFile.path}");
        
        // Play the audio
        await _audioPlayer.play(DeviceFileSource(audioFile.path));
        print("Playing audio...");
      } else {
        print("Fish Audio API error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("Error in text-to-speech: $e");
    }
  }

  /// Stop audio playback
  Future<void> stopAudio() async {
    await _audioPlayer.stop();
  }

  /// Dispose of resources
  void dispose() {
    _audioPlayer.dispose();
  }
}
