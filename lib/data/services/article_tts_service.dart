import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../domain/entities/news_entities.dart';
import 'native_tts_engine.dart';

enum TtsState { idle, speaking, paused }

@immutable
class TtsProgress {
  const TtsProgress({this.word = '', this.start = 0, this.end = 0});

  final String word;
  final int start;
  final int end;
}

class ArticleTtsService {
  ArticleTtsService() {
    _initFuture = _init();
  }

  static const _maxChunkLen = 3500;

  final NativeTtsEngine _engine = NativeTtsEngine();
  late final Future<void> _initFuture;

  final ValueNotifier<TtsState> stateNotifier = ValueNotifier(TtsState.idle);
  final ValueNotifier<TtsProgress> progressNotifier =
      ValueNotifier(const TtsProgress());

  String _fullText = '';
  List<_Chunk> _chunks = const [];
  int _currentChunkIdx = 0;
  int _lastGlobalEnd = 0;
  bool _stopped = false;
  bool _disposed = false;

  Future<void> _init() async {
    await _engine.init();
    await _engine.setLanguage('en-US');
    await _engine.setSpeechRate(0.45);
    await _engine.setVolume(1.0);
    await _engine.setPitch(1.0);

    _engine.onStart = () {
      if (_disposed) return;
      stateNotifier.value = TtsState.speaking;
    };

    _engine.onDone = () {
      if (_disposed || _stopped) return;
      _advanceToNextChunk();
    };

    _engine.onError = (msg) {
      if (_disposed) return;
      _resetPlayback();
    };

    _engine.onRange = (int start, int end) {
      if (_disposed) return;
      if (_currentChunkIdx >= _chunks.length) return;
      final chunk = _chunks[_currentChunkIdx];
      final globalStart = chunk.offset + start;
      final globalEnd = chunk.offset + end;
      _lastGlobalEnd = globalEnd;
      final word = _fullText.length >= globalEnd
          ? _fullText.substring(globalStart, globalEnd)
          : '';
      progressNotifier.value = TtsProgress(
        word: word,
        start: globalStart,
        end: globalEnd,
      );
    };
  }

  Future<void> speak(String text) async {
    if (text.isEmpty || _disposed) return;
    await _initFuture;
    _fullText = text;
    _chunks = _splitIntoChunks(text);
    if (_chunks.isEmpty) return;
    _currentChunkIdx = 0;
    _lastGlobalEnd = 0;
    _stopped = false;
    await _engine.speak(_chunks.first.text);
  }

  Future<void> pause() async {
    if (stateNotifier.value != TtsState.speaking || _disposed) return;
    _stopped = true;
    await _engine.stop();
    stateNotifier.value = TtsState.paused;
  }

  Future<void> resume() async {
    if (stateNotifier.value != TtsState.paused || _disposed) return;
    await _initFuture;
    _stopped = false;

    if (_lastGlobalEnd > 0 && _lastGlobalEnd < _fullText.length) {
      final remaining = _fullText.substring(_lastGlobalEnd).trimLeft();
      if (remaining.isNotEmpty) {
        _chunks = _splitIntoChunks(remaining, offset: _lastGlobalEnd);
        if (_chunks.isEmpty) {
          _resetPlayback();
          return;
        }
        _currentChunkIdx = 0;
        await _engine.speak(_chunks.first.text);
        return;
      }
    }

    _chunks = _splitIntoChunks(_fullText);
    if (_chunks.isEmpty) {
      _resetPlayback();
      return;
    }
    _currentChunkIdx = 0;
    _lastGlobalEnd = 0;
    await _engine.speak(_chunks.first.text);
  }

  Future<void> stop() async {
    if (_disposed) return;
    _stopped = true;
    await _engine.stop();
    _resetPlayback();
  }

  void dispose() {
    _disposed = true;
    _stopped = true;
    _engine.stop().catchError((_) {});
    stateNotifier.dispose();
    progressNotifier.dispose();
  }

  void _advanceToNextChunk() {
    _currentChunkIdx++;
    if (_currentChunkIdx < _chunks.length) {
      _engine.speak(_chunks[_currentChunkIdx].text);
    } else {
      _resetPlayback();
    }
  }

  void _resetPlayback() {
    stateNotifier.value = TtsState.idle;
    progressNotifier.value = const TtsProgress();
    _lastGlobalEnd = 0;
    _currentChunkIdx = 0;
    _chunks = const [];
  }

  /// Splits [text] into chunks of at most [_maxChunkLen] characters,
  /// preferring sentence boundaries (. ! ? or double-newline).
  static List<_Chunk> _splitIntoChunks(String text, {int offset = 0}) {
    if (text.length <= _maxChunkLen) {
      return [_Chunk(text, offset)];
    }

    final chunks = <_Chunk>[];
    var pos = 0;

    while (pos < text.length) {
      final remaining = text.length - pos;
      if (remaining <= _maxChunkLen) {
        chunks.add(_Chunk(text.substring(pos), offset + pos));
        break;
      }

      final window = text.substring(pos, pos + _maxChunkLen);
      var splitAt = _findSentenceBoundary(window);

      if (splitAt <= 0) {
        splitAt = window.lastIndexOf(' ');
      }
      if (splitAt <= 0) {
        splitAt = _maxChunkLen;
      }

      chunks.add(_Chunk(window.substring(0, splitAt).trimRight(), offset + pos));
      pos += splitAt;

      while (pos < text.length && text[pos] == ' ') {
        pos++;
      }
    }

    return chunks;
  }

  /// Finds the last sentence-ending boundary in [window].
  /// Returns the index *after* the punctuation + space, or -1 if none found.
  static int _findSentenceBoundary(String window) {
    final sentenceEnd = RegExp(r'[.!?]\s');
    var best = -1;
    for (final m in sentenceEnd.allMatches(window)) {
      best = math.max(best, m.end);
    }
    if (best < 0) {
      final doubleNewline = window.lastIndexOf('\n\n');
      if (doubleNewline > 0) best = doubleNewline + 2;
    }
    return best;
  }

  /// Extracts plain speakable text from an [Article].
  /// Prefers summaryMarkdown (stripped), falls back to structured blocks.
  static String extractSpeakableText(Article article) {
    final md = article.summaryMarkdown?.trim();
    if (md != null && md.isNotEmpty) return _stripMarkdown(md);

    final blockText = article.blocks
        .where((b) => b.type != 'stat')
        .map((b) {
          switch (b.type) {
            case 'heading':
              return '${b.content}. ';
            case 'quote':
              final attr = b.label != null ? ' Quote by ${b.label}. ' : '';
              return '"${b.content}".$attr';
            default:
              return b.content;
          }
        })
        .join(' ')
        .trim();

    if (blockText.isNotEmpty) return blockText;

    return article.excerpt;
  }

  static String _stripMarkdown(String md) {
    return md
        .replaceAll(RegExp(r'!\[([^\]]*)\]\([^\)]+\)'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1')
        .replaceAll(RegExp(r'#{1,6}\s*'), '')
        .replaceAll(RegExp(r'\*{3}([^*]+)\*{3}'), r'$1')
        .replaceAll(RegExp(r'\*{2}([^*]+)\*{2}'), r'$1')
        .replaceAll(RegExp(r'\*([^*]+)\*'), r'$1')
        .replaceAll(RegExp(r'_{2}([^_]+)_{2}'), r'$1')
        .replaceAll(RegExp(r'_([^_]+)_'), r'$1')
        .replaceAll(RegExp(r'```[^`]*```', dotAll: true), '')
        .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
        .replaceAll(RegExp(r'^\s*[-*+]\s', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\d+\.\s', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*>\s?', multiLine: true), '')
        .replaceAll(RegExp(r'^---+$', multiLine: true), '')
        .replaceAll(RegExp(r'\|[^\n]+\|', multiLine: true), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

class _Chunk {
  const _Chunk(this.text, this.offset);

  final String text;

  /// Start index of this chunk within the full text.
  final int offset;
}
