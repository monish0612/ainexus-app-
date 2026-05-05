/// Web stub for `google_mlkit_text_recognition`. All operations throw
/// `UnsupportedError`; the receipt-scan UI is hidden on web so this code
/// is never reached at runtime.
library ocr_stub_web;

const String _kErr =
    'On-device OCR is not available on the web build. The receipt-scan UI '
    'should be hidden behind PlatformCapabilities.canUseMlKitOcr.';

class TextRecognizer {
  TextRecognizer({Object? script});

  Future<RecognizedText> processImage(InputImage image) async {
    throw UnsupportedError(_kErr);
  }

  Future<void> close() async {}
}

class InputImage {
  InputImage._(this.filePath);
  final String filePath;

  static InputImage fromFilePath(String path) => InputImage._(path);
}

class RecognizedText {
  RecognizedText({this.text = '', this.blocks = const []});
  final String text;
  final List<TextBlock> blocks;
}

class TextBlock {
  TextBlock({this.text = '', this.lines = const []});
  final String text;
  final List<TextLine> lines;
}

class TextLine {
  TextLine({this.text = ''});
  final String text;
}
