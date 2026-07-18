// Verifies the Android smart-parse client forwards the user's CONFIGURED bank
// names to the backend (so cards added in Settings are recognised by voice /
// shared-SMS / receipt parsing), and that the list is de-duped + trimmed. A
// fake HttpClientAdapter captures the outgoing request body so no network is
// touched.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/data/services/ai_categorize_service.dart';

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
        'amount': 250,
        'description': 'Lunch',
        'bank': 'KOTAK',
        'cardType': 'CC',
        'category': 'Food',
        'model': 'test-model',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('smartParse forwards distinct, trimmed bank names + parses the result',
      () async {
    final client = ApiClient();
    final adapter = _CapturingAdapter();
    client.dio.httpClientAdapter = adapter;
    final svc = AICategorizeService(client);

    final result = await svc.smartParse(
      'spent 250 on kotak credit card',
      liteModel: 'gemini-2.5-flash-lite',
      banks: ['KOTAK', 'HDFC', 'kotak', '  ', 'SCAPIA'],
    );

    expect(result, isNotNull);
    expect(result!.bank, 'KOTAK');
    expect(result.cardType, 'CC');

    final body = adapter.calls.single.data as Map;
    expect(body['text'], 'spent 250 on kotak credit card');
    expect(body['liteModel'], 'gemini-2.5-flash-lite');
    // Case-insensitive dedupe ("kotak"), empties dropped, order preserved.
    expect(body['banks'], <String>['KOTAK', 'HDFC', 'SCAPIA']);
  });

  test('smartParse omits the banks key when none are configured', () async {
    final client = ApiClient();
    final adapter = _CapturingAdapter();
    client.dio.httpClientAdapter = adapter;
    final svc = AICategorizeService(client);

    await svc.smartParse('spent 250 cash', banks: const []);
    expect((adapter.calls.single.data as Map).containsKey('banks'), isFalse);

    adapter.calls.clear();
    await svc.smartParse('spent 250 cash');
    expect((adapter.calls.single.data as Map).containsKey('banks'), isFalse);
  });
}
