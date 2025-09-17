import '../ml/spam_classifier.dart';

class SpamResult {
  final bool isSpam;
  final double confidence;

  SpamResult({required this.isSpam, required this.confidence});
}

class SpamDetectionService {
  static SpamClassifier? _classifier;
  static bool _isInitialized = false;

  // For testing purposes
  static bool get isInitialized => _isInitialized;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _classifier = await SpamClassifier.create(
        'assets/spam_model/model.tflite',
        'assets/spam_model/vocab.txt',
        maxLen: 128,
      );
      _isInitialized = true;
    } catch (e) {
      throw Exception("Failed to initialize spam classifier: $e");
    }
  }

  static Future<SpamResult> checkSpam(String message) async {
    if (!_isInitialized || _classifier == null) {
      await initialize();
    }

    if (_classifier == null) {
      throw Exception("Spam classifier initialization failed");
    }

    try {
      final result = await _classifier!.classify(message);

      // Assuming LABEL_1 is spam (adjust based on your model's training)
      final isSpam = result['label'] == 'LABEL_1';
      final confidence = (result['probabilities'][result['index']] * 100)
          .toDouble();

      return SpamResult(isSpam: isSpam, confidence: confidence);
    } catch (e) {
      throw Exception("Failed to classify message: $e");
    }
  }

  static void dispose() {
    _classifier?.dispose();
    _classifier = null;
    _isInitialized = false;
  }
}
