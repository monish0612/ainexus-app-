// Verifies the batch summarize client forwards the article's original URL to
// the backend (so the server can deep-extract real content for articles whose
// local copy is thin — the "summary doesn't explain anything" fix), and omits
// the key when no URL exists. A fake HttpClientAdapter captures the outgoing
// request body so no network is touched.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/services/news_summarize_service.dart';
import 'package:ai_nexus/domain/entities/news_entities.dart';

class _CapturingAdapter implements HttpClientAdapter {
  final List<RequestOptions> calls = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    calls.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'summaries': [
          {'id': 'a1', 'summary': 'Lede.\n\nBody paragraph.'},
          {'id': 'a2', 'summary': 'Another summary.'},
        ],
        'model': 'test-model',
        'count': 2,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Article _article(String id, {String? originalUrl}) => Article(
      id: id,
      title: 'Title $id',
      excerpt: 'Excerpt for $id',
      source: 'Source',
      category: 'Tech',
      imageUrl: '',
      readTime: 3,
      date: '2026-07-18',
      blocks: const [],
      originalUrl: originalUrl,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('summarizeBatch forwards url when the article has one, omits otherwise',
      () async {
    final client = ApiClient();
    final adapter = _CapturingAdapter();
    client.dio.httpClientAdapter = adapter;
    final svc = NewsSummarizeService(client);

    final result = await svc.summarizeBatch(articles: [
      _article('a1', originalUrl: ' https://example.com/story '),
      _article('a2'),
    ]);

    expect(result, {
      'a1': 'Lede.\n\nBody paragraph.',
      'a2': 'Another summary.',
    });

    final body = adapter.calls.single.data as Map;
    final sent = (body['articles'] as List).cast<Map>();
    expect(sent, hasLength(2));
    // URL is trimmed and forwarded so the backend can enrich thin articles.
    expect(sent[0]['url'], 'https://example.com/story');
    // No URL → key omitted entirely (older backends strip unknown keys, but
    // we never send noise).
    expect(sent[1].containsKey('url'), isFalse);
    // The rest of the wire contract is untouched.
    expect(sent[0]['id'], 'a1');
    expect(sent[0]['title'], 'Title a1');
    expect(sent[0]['content'], isNotEmpty);
  });
}
