import 'package:flutter/widgets.dart';

/// Web implementation: there is no concept of a local file path that can
/// be rendered by `Image.file` on the web. Returns the [fallback] widget
/// (a `SizedBox.shrink` by default). The receipt-scan UI is hidden on
/// web, so this is only used as defensive scaffolding.
class LocalFileImage extends StatelessWidget {
  const LocalFileImage({
    super.key,
    required this.path,
    this.fit,
    this.width,
    this.height,
    this.fallback,
  });

  final String path;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) =>
      fallback ?? const SizedBox.shrink();
}
