import 'dart:async';
import 'package:flutter/services.dart' show rootBundle;

class BertTokenizer {
  final Map<String, int> vocab;
  final bool doLowerCase;
  final int maxLen;
  final int unkId;
  final int padId;
  final int clsId;
  final int sepId;

  BertTokenizer({
    required this.vocab,
    this.doLowerCase = true,
    this.maxLen = 128,
  }) : unkId = vocab['[UNK]'] ?? 100,
       padId = vocab['[PAD]'] ?? 0,
       clsId = vocab['[CLS]'] ?? 101,
       sepId = vocab['[SEP]'] ?? 102;

  static Future<BertTokenizer> fromVocabAsset(
    String assetPath, {
    bool doLowerCase = true,
    int maxLen = 128,
  }) async {
    final raw = await rootBundle.loadString(assetPath);
    final lines = raw.split('\n');
    final Map<String, int> vocab = {};
    for (int i = 0; i < lines.length; i++) {
      final token = lines[i].trim();
      if (token.isEmpty) continue;
      vocab[token] = i;
    }
    return BertTokenizer(
      vocab: vocab,
      doLowerCase: doLowerCase,
      maxLen: maxLen,
    );
  }

  // basic tokenization: split on whitespace & punctuation (simple)
  List<String> _basicTokenize(String text) {
    if (doLowerCase) text = text.toLowerCase();
    // keep words and punctuation as tokens
    final regex = RegExp(r"[A-Za-z0-9]+|[^ \t\nA-Za-z0-9]");
    final matches = regex.allMatches(text);
    return matches.map((m) => m.group(0)!).toList();
  }

  // WordPiece longest-match algorithm on a single word piece
  List<String> _wordpieceTokenize(String word) {
    final tokens = <String>[];
    int start = 0;
    while (start < word.length) {
      int end = word.length;
      String? curSubstr;
      while (end > start) {
        String substr = word.substring(start, end);
        String candidate = (start == 0) ? substr : "##$substr";
        if (vocab.containsKey(candidate)) {
          curSubstr = candidate;
          break;
        }
        end -= 1;
      }
      if (curSubstr == null) {
        tokens.add('[UNK]');
        break;
      }
      tokens.add(curSubstr);
      start = end;
    }
    return tokens;
  }

  // public method: returns { 'inputIds': List<int>, 'attentionMask': List<int> }
  Map<String, List<int>> encode(String text) {
    final words = _basicTokenize(text);
    final subTokens = <String>[];
    for (final w in words) {
      subTokens.addAll(_wordpieceTokenize(w));
    }

    // build ids with special tokens
    final ids = <int>[];
    ids.add(clsId);
    for (final t in subTokens) {
      ids.add(vocab[t] ?? unkId);
    }
    ids.add(sepId);

    // truncate/pad
    if (ids.length > maxLen) {
      ids.removeRange(maxLen, ids.length);
      // ensure last token is sep
      ids[ids.length - 1] = sepId;
    }
    while (ids.length < maxLen) {
      ids.add(padId);
    }

    final attentionMask = ids.map((id) => id == padId ? 0 : 1).toList();
    return {'inputIds': ids, 'attentionMask': attentionMask};
  }
}
