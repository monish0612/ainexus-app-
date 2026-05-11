import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/local/database/app_database.dart';
import 'tutor_entities.dart';

/// Discriminator for the persisted result payload. Keeping it as named
/// constants (instead of an enum on the wire) means the server-side
/// schema only sees plain strings, matching the existing article-chats
/// convention.
abstract final class SavedSearchKind {
  static const url = 'url';
  static const query = 'query';

  /// InsightAI vision flow — user attached an image (camera/gallery)
  /// and optionally typed a text query. Same persistence + sync
  /// semantics as [query]; the discriminator lets the History UI
  /// render the camera badge instead of the search badge.
  static const image = 'image';
}

abstract final class SavedSearchResponseType {
  static const summarizer = 'summarizer';
  static const grounded = 'grounded';
  static const tavily = 'tavily';

  /// Result of an InsightAI image-search call. Wire-compatible with
  /// [grounded] (same `{ answer, model, sources }` shape) plus three
  /// extra opaque fields inside `responseJson` for cross-device
  /// preview without a Drift schema migration:
  ///   • `imageThumb`     : data:image/jpeg;base64,... (≤ 50 KB)
  ///   • `imageMediaType` : original mime (image/jpeg, image/png, …)
  ///   • `question`       : the text query the user typed alongside
  ///                        the image, surfaced verbatim in History
  static const imageGrounded = 'image-grounded';
}

/// Immutable view of a saved search — the in-app domain object the UI and
/// store layer pass around. Round-trips losslessly to/from Drift via
/// [fromDrift] / [toCompanion] and to/from the wire via [fromJson] /
/// [toJson]. The opaque [responseJson] carries the original DTO so result
/// shape evolution doesn't require an entity migration.
@immutable
class SavedSearchEntry {
  const SavedSearchEntry({
    required this.id,
    required this.kind,
    required this.query,
    required this.title,
    required this.responseType,
    required this.responseJson,
    required this.savedAt,
    required this.updatedAt,
    this.model = '',
    this.provider = '',
    this.mode = '',
    this.pinned = true,
    this.deletedAt,
  });

  final String id;
  final String kind;
  final String query;
  final String title;
  final String responseType;
  final String responseJson;
  final String model;
  final String provider;
  final String mode;
  final String savedAt;
  final String updatedAt;
  final bool pinned;
  final String? deletedAt;

  // ── Drift round-trip ───────────────────────────────────────────────────────

  factory SavedSearchEntry.fromDrift(SavedSearche row) {
    return SavedSearchEntry(
      id: row.id,
      kind: row.kind,
      query: row.query,
      title: row.title,
      responseType: row.responseType,
      responseJson: row.responseJson,
      model: row.model,
      provider: row.provider,
      mode: row.mode,
      savedAt: row.savedAt,
      updatedAt: row.updatedAt,
      pinned: row.pinned,
      deletedAt: row.deletedAt,
    );
  }

  // ── Wire round-trip ────────────────────────────────────────────────────────
  //
  // The server is expected to mirror the article-chats wire shape: camelCase
  // outbound, tolerant of snake_case on inbound. We follow the same
  // permissive parsing pattern used in tutor_entities.dart so a future
  // backend tweak doesn't require a client release.

  factory SavedSearchEntry.fromJson(Map<String, dynamic> json) {
    String pickStr(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is String) return v;
      }
      return '';
    }

    bool pickBool(List<String> keys, {bool fallback = false}) {
      for (final k in keys) {
        final v = json[k];
        if (v is bool) return v;
        if (v is num) return v != 0;
        if (v is String) return v.toLowerCase() == 'true' || v == '1';
      }
      return fallback;
    }

    // Handle the `responseJson` field generously — server may send the
    // result as a nested map (preferred) or as a JSON string for parity
    // with our local Drift representation.
    final rawResponse = json['responseJson'] ?? json['response_json'];
    final responseJson = rawResponse is Map
        ? jsonEncode(rawResponse)
        : (rawResponse?.toString() ?? '{}');

    return SavedSearchEntry(
      id: pickStr(const ['id']),
      kind: pickStr(const ['kind']),
      query: pickStr(const ['query']),
      title: pickStr(const ['title']),
      responseType: pickStr(const ['responseType', 'response_type']),
      responseJson: responseJson,
      model: pickStr(const ['model']),
      provider: pickStr(const ['provider']),
      mode: pickStr(const ['mode']),
      savedAt: pickStr(const ['savedAt', 'saved_at']),
      updatedAt: pickStr(const ['updatedAt', 'updated_at']),
      pinned: pickBool(const ['pinned'], fallback: true),
      deletedAt: () {
        for (final k in const ['deletedAt', 'deleted_at']) {
          final v = json[k];
          if (v is String && v.isNotEmpty) return v;
        }
        return null;
      }(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind,
        'query': query,
        'title': title,
        'responseType': responseType,
        'responseJson': _decodedResponseJsonForWire(),
        'model': model,
        'provider': provider,
        'mode': mode,
        'savedAt': savedAt,
        'updatedAt': updatedAt,
        'pinned': pinned,
        if (deletedAt != null) 'deletedAt': deletedAt,
      };

  /// Sends the response payload to the server as a structured object when
  /// it parses cleanly, falling back to the raw string otherwise. This keeps
  /// the server-side queryable (it can index inside the response) without
  /// risking a payload corruption on parse errors.
  Object _decodedResponseJsonForWire() {
    try {
      final decoded = jsonDecode(responseJson);
      if (decoded is Map || decoded is List) return decoded;
    } catch (_) {
      // fall through
    }
    return responseJson;
  }

  // ── Decoded result ─────────────────────────────────────────────────────────
  //
  // Decodes the opaque [responseJson] into the appropriate DTO. Returns
  // null if the saved type is unknown to this client version (forward-
  // compat) — UI should fall back to a generic preview in that case.

  Object? decodedResult() {
    Map<String, dynamic>? parsed;
    try {
      final decoded = jsonDecode(responseJson);
      if (decoded is Map) {
        parsed = decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {
      return null;
    }
    if (parsed == null) return null;

    switch (responseType) {
      case SavedSearchResponseType.summarizer:
        return SummarizerResult.fromJson(parsed);
      case SavedSearchResponseType.grounded:
        return GroundedSearchResponse.fromJson(parsed);
      case SavedSearchResponseType.imageGrounded:
        // Image-grounded results share the GroundedSearchResponse wire
        // shape — the extra `imageThumb` / `imageMediaType` / `question`
        // fields are surfaced through [imageThumbDataUrl] etc. so the
        // typed result stays clean and reusable.
        return GroundedSearchResponse.fromJson(parsed);
      case SavedSearchResponseType.tavily:
        return TavilySearchResponse.fromJson(parsed);
      default:
        return null;
    }
  }

  // ── Image-grounded helpers ───────────────────────────────────────────────
  //
  // These helpers crack open the opaque [responseJson] for image-grounded
  // entries so the History sheet can render the thumbnail + question
  // without leaking any of the JSON shape into the rest of the codebase.
  // For non-image entries they return null/empty so call sites can simply
  // ignore the field when [responseType] doesn't match.

  Map<String, dynamic>? _responseExtras() {
    try {
      final decoded = jsonDecode(responseJson);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return null;
  }

  /// `data:image/jpeg;base64,...` URL for the 256 px preview thumbnail
  /// of an [SavedSearchResponseType.imageGrounded] entry. Returns null
  /// when missing or when the entry is not image-grounded.
  String? get imageThumbDataUrl {
    if (responseType != SavedSearchResponseType.imageGrounded) return null;
    final extras = _responseExtras();
    final v = extras?['imageThumb'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  /// Original media type of the source image (image/jpeg, image/png,
  /// image/heic, …). Useful for the History UI to render an accurate
  /// "type" pill. Null for non-image entries.
  String? get imageMediaType {
    if (responseType != SavedSearchResponseType.imageGrounded) return null;
    final extras = _responseExtras();
    final v = extras?['imageMediaType'];
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  /// The user's text question that accompanied the uploaded image. May
  /// be empty when the user uploaded an image without typing anything.
  String? get imageQuestion {
    if (responseType != SavedSearchResponseType.imageGrounded) return null;
    final extras = _responseExtras();
    final v = extras?['question'];
    if (v is String) return v;
    return null;
  }

  // ── Convenience builders ──────────────────────────────────────────────────

  SavedSearchEntry copyWith({
    String? id,
    String? kind,
    String? query,
    String? title,
    String? responseType,
    String? responseJson,
    String? model,
    String? provider,
    String? mode,
    String? savedAt,
    String? updatedAt,
    bool? pinned,
    String? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return SavedSearchEntry(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      query: query ?? this.query,
      title: title ?? this.title,
      responseType: responseType ?? this.responseType,
      responseJson: responseJson ?? this.responseJson,
      model: model ?? this.model,
      provider: provider ?? this.provider,
      mode: mode ?? this.mode,
      savedAt: savedAt ?? this.savedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }

  /// Best-effort title derivation used at save-time.
  static String deriveTitle({required String kind, required String query}) {
    final t = query.trim();
    if (kind == SavedSearchKind.url) {
      try {
        final uri = Uri.parse(t);
        final host = uri.host;
        if (host.isNotEmpty) {
          final path = uri.path.replaceAll(RegExp(r'/+$'), '');
          return path.isNotEmpty ? '$host$path' : host;
        }
      } catch (_) {}
    }
    if (t.length <= 80) return t;
    return '${t.substring(0, 77).trim()}\u2026';
  }
}
