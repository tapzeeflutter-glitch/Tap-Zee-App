import 'dart:math';
import 'dart:io' show Platform;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'bert_tokenizer.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

class SpamClassifier {
  final Interpreter? _interpreter;
  final BertTokenizer _tokenizer;
  final List<String> labels;
  final int maxLen;
  final bool _isWindowsFallback;

  SpamClassifier._(
    this._interpreter,
    this._tokenizer,
    this.labels,
    this.maxLen,
    this._isWindowsFallback,
  );

  static Future<SpamClassifier> create(
    String modelAsset,
    String vocabAsset, {
    int maxLen = 128,
    String? labelConfigJsonAsset,
  }) async {
    // Handle Windows fallback
    if (Platform.isWindows) {
      print(
        'TFLite: Using Windows fallback mode (no native library available)',
      );
      final tokenizer = await BertTokenizer.fromVocabAsset(
        vocabAsset,
        maxLen: maxLen,
      );
      List<String> labels = ['LABEL_0', 'LABEL_1'];
      return SpamClassifier._(null, tokenizer, labels, maxLen, true);
    }

    try {
      final interpreter = await Interpreter.fromAsset(modelAsset);
      final tokenizer = await BertTokenizer.fromVocabAsset(
        vocabAsset,
        maxLen: maxLen,
      );
      List<String> labels = ['LABEL_0', 'LABEL_1'];
      if (labelConfigJsonAsset != null) {
        try {
          final raw = await rootBundle.loadString(labelConfigJsonAsset);
          final Map cfg = jsonDecode(raw);
          if (cfg.containsKey('id2label')) {
            final m = Map<String, dynamic>.from(cfg['id2label']);
            labels = List.generate(m.length, (i) => m['$i'] as String);
          }
        } catch (_) {}
      }
      return SpamClassifier._(interpreter, tokenizer, labels, maxLen, false);
    } catch (e) {
      print(
        'TFLite: Failed to load model, falling back to mock implementation: $e',
      );
      final tokenizer = await BertTokenizer.fromVocabAsset(
        vocabAsset,
        maxLen: maxLen,
      );
      List<String> labels = ['LABEL_0', 'LABEL_1'];
      return SpamClassifier._(null, tokenizer, labels, maxLen, true);
    }
  }

  // softmax helper
  List<double> _softmax(List<double> logits) {
    final maxL = logits.reduce(max);
    final exps = logits.map((l) => exp(l - maxL)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  Future<Map<String, dynamic>> classify(String text) async {
    // Windows/mock fallback - simple heuristic-based classification
    if (_interpreter == null || _isWindowsFallback) {
      return _fallbackClassify(text);
    }

    final encoded = _tokenizer.encode(text);
    final inputIds = [encoded['inputIds']!]; // shape [1, maxLen]
    final attentionMask = [encoded['attentionMask']!]; // shape [1, maxLen]

    // Prepare output buffer (assume model returns [1, num_labels] float32)
    final outputShapes = _interpreter
        .getOutputTensors()
        .map((t) => t.shape)
        .toList();
    final numLabels = outputShapes[0].last;
    final outputBuffer = List.generate(1, (_) => List.filled(numLabels, 0.0));

    // run (check how many inputs the model expects)
    final inputTensorsCount = _interpreter.getInputTensors().length;
    if (inputTensorsCount == 1) {
      // sometimes model expects concatenated single input (rare). Try inputIds only.
      _interpreter.run(inputIds, outputBuffer);
    } else {
      // typical exported BERT TFLite expects [input_ids, attention_mask] (and maybe token_type_ids)
      final inputs = [inputIds, attentionMask];
      final outputs = <int, Object>{0: outputBuffer};
      _interpreter.runForMultipleInputs(inputs, outputs);
    }

    final logits = (outputBuffer[0]).map((e) => e.toDouble()).toList();
    final probs = _softmax(logits);
    final maxIndex = probs.indexWhere((p) => p == probs.reduce(max));
    return {
      'label': labels[maxIndex],
      'index': maxIndex,
      'probabilities': probs,
      'logits': logits,
    };
  }

  // Fallback classification for Windows/mock mode
  Map<String, dynamic> _fallbackClassify(String text) {
    // Simple heuristic-based spam detection
    final lowerText = text.toLowerCase();

    // Common spam indicators
    final spamKeywords = [
      'win',
      'free',
      'prize',
      'winner',
      'congratulations',
      'urgent',
      'click here',
      'limited time',
      'offer',
      'money',
      'cash',
      'rich',
      'million',
      'billion',
      'investment',
      'crypto',
      'bitcoin',
      'password',
      'account suspended',
      'verify',
      'confirm',
      'bank details',
    ];

    final capsRatio =
        text.replaceAll(RegExp(r'[^A-Z]'), '').length / text.length;
    final exclamationCount = '!'.allMatches(text).length;
    final hasMultipleCaps = capsRatio > 0.3;
    final hasManyExclamations = exclamationCount > 3;

    int spamScore = 0;
    for (final keyword in spamKeywords) {
      if (lowerText.contains(keyword)) {
        spamScore += 2;
      }
    }

    if (hasMultipleCaps) spamScore += 1;
    if (hasManyExclamations) spamScore += 1;

    // Determine if it's spam based on score
    final isSpam = spamScore >= 3;
    final confidence = isSpam
        ? 85.0 + (spamScore * 3.0)
        : 100.0 - (spamScore * 10.0);
    final safeConfidence = confidence.clamp(0.0, 100.0);

    return {
      'label': isSpam ? 'LABEL_1' : 'LABEL_0',
      'index': isSpam ? 1 : 0,
      'probabilities': isSpam ? [0.15, 0.85] : [0.85, 0.15],
      'logits': isSpam ? [-1.5, 1.5] : [1.5, -1.5],
      'fallback': true,
      'confidence': safeConfidence,
    };
  }

  void dispose() {
    _interpreter?.close();
  }
}
