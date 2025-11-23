import 'package:google_generative_ai/google_generative_ai.dart';
import 'osm_service.dart';

class GeminiService {
  late final GenerativeModel _model;
  
  GeminiService(String apiKey) {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );
  }

  /// Converts a list of POIs into a conversational paragraph using Gemini API
  Future<String> convertToConversation(List<POI> pois) async {
    if (pois.isEmpty) {
      return "I don't see any notable locations nearby at the moment.";
    }

    // Build the prompt with POI data
    final prompt = _buildPrompt(pois);

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      if (response.text != null && response.text!.isNotEmpty) {
        return response.text!;
      } else {
        return "I couldn't generate a description at this time.";
      }
    } catch (e) {
      print("Gemini API error: $e");
      return "Unable to describe your surroundings right now.";
    }
  }

  String _buildPrompt(List<POI> pois) {
    final locationsText = StringBuffer();
    
    for (int i = 0; i < pois.length; i++) {
      final poi = pois[i];
      locationsText.writeln('${i + 1}. ${poi.name} (${poi.category}) - ${poi.distance.round()}m away');
    }

    return '''You are a helpful navigation assistant. Here are some nearby locations around the user:

$locationsText
Convert this into a friendly, natural conversational paragraph (2-3 sentences) describing what's around the user. Be concise and helpful. Focus on the most interesting or useful locations.''';
  }
}
