class GeminiConfig {
  static const apiKey = String.fromEnvironment('GEMINI_API_KEY');

  static bool get hasApiKey => apiKey.isNotEmpty;
}
