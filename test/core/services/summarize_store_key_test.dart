import 'dart:async';

import 'package:ai_nexus/core/network/api_client.dart';
import 'package:ai_nexus/core/services/summarize_store.dart';
import 'package:ai_nexus/core/utils/tidy_url.dart';
import 'package:ai_nexus/data/services/tutor_ai_service.dart';
import 'package:ai_nexus/domain/entities/tutor_entities.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _HangTutor extends TutorAiService {
  _HangTutor() : super(ApiClient());

  final urls = <String>[];

  @override
  Future<SummarizerResult> summarize({
    required String url,
    String? provider,
    String? xgrokModel,
    String? liteModel,
    CancelToken? cancelToken,
  }) async {
    urls.add(url);
    final done = Completer<SummarizerResult>();
    cancelToken?.whenCancel.then((_) {
      if (!done.isCompleted) {
        done.completeError(
          DioException(
            requestOptions: RequestOptions(path: '/ai/summarize'),
            type: DioExceptionType.cancel,
          ),
        );
      }
    });
    return done.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    final store = SummarizeStore.instance;
    for (final url in [
      'https://youtu.be/dQw4w9WgXcQ?si=a',
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    ]) {
      store.remove(TidyUrl.summarizeJobKey(url));
    }
  });

  test('tracking variants reuse one store key and one cleaned fetch URL',
      () async {
    final tutor = _HangTutor();
    final store = SummarizeStore.instance;

    final keyA = store.startSummarize(
      url: 'https://youtu.be/dQw4w9WgXcQ?si=aaa',
      service: tutor,
    );
    final keyB = store.startSummarize(
      url: 'https://m.youtube.com/watch?v=dQw4w9WgXcQ&feature=share',
      service: tutor,
    );

    expect(keyA, keyB);
    expect(keyA, 'youtube.com/watch?v=dQw4w9WgXcQ');
    expect(store.getJob(keyA)?.loading, isTrue);

    await Future<void>.delayed(Duration.zero);
    expect(tutor.urls, isNotEmpty);
    expect(
      tutor.urls.every(
        (u) => u == 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      ),
      isTrue,
    );

    store.remove(keyA);
  });
}
