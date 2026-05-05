import 'dart:io';

import 'package:flutter/widgets.dart';

/// Native implementation: wraps [Image.file] with the local file at [path].
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
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) return fallback ?? const SizedBox.shrink();
    return Image.file(file, fit: fit, width: width, height: height);
  }
}
