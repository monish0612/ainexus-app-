import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';

class ProfilePhotoMeta {
  const ProfilePhotoMeta({
    required this.exists,
    this.sha256,
    this.bytes,
    this.updatedAt,
  });

  final bool exists;
  final String? sha256;
  final int? bytes;
  final String? updatedAt;

  factory ProfilePhotoMeta.fromJson(Object? raw) {
    if (raw is! Map) return const ProfilePhotoMeta(exists: false);
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final exists = m['exists'] == true;
    return ProfilePhotoMeta(
      exists: exists,
      sha256: m['sha256'] is String ? m['sha256'] as String : null,
      bytes: m['bytes'] is num ? (m['bytes'] as num).toInt() : null,
      updatedAt: m['updatedAt'] is String ? m['updatedAt'] as String : null,
    );
  }
}

/// Cloud copy of the rolling avatar. 404 from an older server is "no photo".
abstract class ProfilePhotoRemote {
  Future<ProfilePhotoMeta> fetchMeta();
  Future<Uint8List?> fetchJpeg({String? ifNoneMatch});
  Future<ProfilePhotoMeta> upload(Uint8List jpeg);
  Future<void> delete();
}

class DioProfilePhotoRemote implements ProfilePhotoRemote {
  DioProfilePhotoRemote(this._api);

  final ApiClient _api;

  static bool _isMissing(int? status) =>
      status == 204 || status == 404;

  @override
  Future<ProfilePhotoMeta> fetchMeta() async {
    try {
      final resp = await _api.get<Object?>(ApiEndpoints.profilePhotoMeta);
      if (_isMissing(resp.statusCode)) {
        return const ProfilePhotoMeta(exists: false);
      }
      return ProfilePhotoMeta.fromJson(resp.data);
    } on DioException catch (e) {
      if (_isMissing(e.response?.statusCode)) {
        return const ProfilePhotoMeta(exists: false);
      }
      rethrow;
    }
  }

  @override
  Future<Uint8List?> fetchJpeg({String? ifNoneMatch}) async {
    try {
      final resp = await _api.dio.get<List<int>>(
        ApiEndpoints.profilePhoto,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Accept': 'image/jpeg',
            if (ifNoneMatch != null && ifNoneMatch.isNotEmpty)
              'If-None-Match': '"$ifNoneMatch"',
          },
          validateStatus: (s) =>
              s != null && ((s >= 200 && s < 300) || s == 304 || s == 404),
        ),
      );
      final status = resp.statusCode ?? 0;
      if (status == 304 || _isMissing(status)) return null;
      final data = resp.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      if (_isMissing(e.response?.statusCode) || e.response?.statusCode == 304) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<ProfilePhotoMeta> upload(Uint8List jpeg) async {
    final resp = await _api.put<Object?>(
      ApiEndpoints.profilePhoto,
      data: <String, dynamic>{'jpegBase64': base64Encode(jpeg)},
    );
    return ProfilePhotoMeta.fromJson(resp.data);
  }

  @override
  Future<void> delete() async {
    try {
      await _api.delete<Object?>(ApiEndpoints.profilePhoto);
    } on DioException catch (e) {
      if (_isMissing(e.response?.statusCode)) return;
      rethrow;
    }
  }
}

String sha256Hex(Uint8List bytes) => sha256.convert(bytes).toString();
