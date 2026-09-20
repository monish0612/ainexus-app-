import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/news_entities.dart';
import 'article_detail_modal.dart';
import 'news_controller.dart';

/// Opens the existing article reader (save, listen, follow-up chat).
/// Shared by the News feed and the Saved page so neither path diverges.
Future<void> openNewsArticle({
  required BuildContext context,
  required WidgetRef ref,
  required Article raw,
}) async {
  final article =
      await ref.read(newsControllerProvider.notifier).loadArticle(raw.id) ??
          raw;
  if (!context.mounted) return;
  final feed =
      ref.read(newsControllerProvider).valueOrNull ?? const <Article>[];
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ArticleDetailModal(
        article: article,
        queue: feed,
        onToggleSave: (_) {
          ref.read(newsControllerProvider.notifier).toggleSaved(raw.id);
        },
        onMarkRead: () {
          ref.read(newsControllerProvider.notifier).markRead(raw.id);
        },
      ),
    ),
  );
}
