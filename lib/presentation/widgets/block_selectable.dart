import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Chrome that must never join a text selection (Share, AI Summarize,
/// KEY FACTS labels, nav, sticky header, etc.).
class NonSelectableChrome extends StatelessWidget {
  const NonSelectableChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(child: child);
  }
}

/// One continuous selection document. Drag handles and **Select all** cover
/// every [Text] / markdown descendant — never widgets wrapped in
/// [NonSelectableChrome].
class ArticleSelectionScope extends StatelessWidget {
  const ArticleSelectionScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(child: child);
  }
}

/// Prose that joins an ancestor [ArticleSelectionScope]. Not a
/// [SelectableText] — those isolate each paragraph and block drag-to-next.
class BlockSelectableText extends StatelessWidget {
  const BlockSelectableText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      textAlign: textAlign,
      softWrap: true,
    );
  }
}

/// Markdown whose paragraphs share one selection tree so the user can
/// highlight across the whole article / AI answer.
///
/// [ownSelectionScope] is true for standalone answers (follow-up bubble,
/// search result). Article readers set it false and wrap title + body in a
/// single [ArticleSelectionScope] instead.
class BlockSelectableMarkdown extends StatelessWidget {
  const BlockSelectableMarkdown({
    super.key,
    required this.data,
    this.styleSheet,
    this.onTapLink,
    this.sizedImageBuilder,
    this.shrinkWrap = true,
    this.fitContent = true,
    this.ownSelectionScope = true,
  });

  final String data;
  final MarkdownStyleSheet? styleSheet;
  final MarkdownTapLinkCallback? onTapLink;
  final MarkdownSizedImageBuilder? sizedImageBuilder;
  final bool shrinkWrap;
  final bool fitContent;
  final bool ownSelectionScope;

  @override
  Widget build(BuildContext context) {
    final markdown = MarkdownBody(
      data: data,
      selectable: false,
      shrinkWrap: shrinkWrap,
      fitContent: fitContent,
      styleSheet: styleSheet,
      onTapLink: onTapLink,
      sizedImageBuilder: sizedImageBuilder,
    );
    if (!ownSelectionScope) return markdown;
    return ArticleSelectionScope(child: markdown);
  }
}
