// Cross-platform façade for the on-device OCR engine
// (`google_mlkit_text_recognition`).
//
// The package itself only ships native bindings (Android/iOS), so the
// import would fail to compile on web. We re-export the real package on
// native and provide minimal compile-only stubs on web. The receipt-scan
// UI is hidden on web (`PlatformCapabilities.canUseMlKitOcr`), so these
// stub methods are never called at runtime.
export 'ocr_stub_native.dart'
    if (dart.library.js_interop) 'ocr_stub_web.dart';
