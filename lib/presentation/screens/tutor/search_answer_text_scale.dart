import 'package:flutter/material.dart';

import '../../widgets/block_selectable.dart';
import '../news/news_reader_text_scale.dart';

/// Search-result A−/A+ keys. Distinct from the news reader so both UIs can
/// sit on the navigator without [ValueKey] collisions.
const Key kSearchAnswerTextSizeBarKey = ValueKey('search_answer_text_size_bar');
const Key kSearchAnswerTextDecreaseKey =
    ValueKey('search_answer_text_decrease');
const Key kSearchAnswerTextIncreaseKey =
    ValueKey('search_answer_text_increase');

/// Compact A−/A+ pill. Uses the same steps and SharedPreferences key as the
/// news article reader so one reading size follows the user.
class SearchAnswerTextSizeControl extends StatelessWidget {
  const SearchAnswerTextSizeControl({super.key});

  @override
  Widget build(BuildContext context) {
    return const UnscaledReaderChrome(
      child: ArticleReaderTextSizeBar(
        variant: ArticleReaderTextSizeVariant.onSurface,
        barKey: kSearchAnswerTextSizeBarKey,
        decreaseKey: kSearchAnswerTextDecreaseKey,
        increaseKey: kSearchAnswerTextIncreaseKey,
      ),
    );
  }
}

/// A−/A+ plus an optional chrome action (Copy / Expand). [FittedBox] shrinks
/// the cluster on a 320px phone instead of overflowing.
class SearchAnswerHeaderActions extends StatelessWidget {
  const SearchAnswerHeaderActions({super.key, this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return UnscaledReaderChrome(
      child: NonSelectableChrome(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SearchAnswerTextSizeControl(),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Left-aligned section label with A−/A+ (and optional Copy) pinned right.
class SearchAnswerSectionHeader extends StatelessWidget {
  const SearchAnswerSectionHeader({
    super.key,
    required this.label,
    this.labelStyle,
    this.leading,
    this.trailing,
  });

  final String label;
  final TextStyle? labelStyle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return UnscaledReaderChrome(
      child: NonSelectableChrome(
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 8),
            ],
            Text(label, style: labelStyle),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: SearchAnswerHeaderActions(trailing: trailing),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
