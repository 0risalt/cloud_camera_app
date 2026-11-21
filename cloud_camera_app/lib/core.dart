import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppColors {
  static const bg = Color(0xFF0E0E12);
  static const bgAlt = Color(0xFF16161E);
  static const surface = Color(0xFF1E1E28);
  static const surfaceAlt = Color(0xFF262633);
  static const primary = Color(0xFF7C6CFF);
  static const accent = Color(0xFF4ADEDE);
  static const success = Color(0xFF4CD964);
  static const warning = Color(0xFFFFB020);
  static const danger = Color(0xFFFF4E5B);
  static const favorite = Color(0xFFFFC93C);
  static const textPrimary = Color(0xFFF2F2F7);
  static const textSecondary = Color(0xFFA0A0B0);
  static const divider = Color(0xFF2C2C3A);
}

/// Единый SnackBar для всех экранов: `msg('текст', success: true)`.
mixin Msg<T extends StatefulWidget> on State<T> {
  void msg(String text, {bool success = false, bool error = false}) {
    if (!mounted) return;
    final color = error
        ? AppColors.danger
        : success
            ? AppColors.success
            : AppColors.primary;
    final icon = error
        ? Icons.error_outline
        : success
            ? Icons.check_circle_outline
            : Icons.info_outline;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ]),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withOpacity(0.4)),
      ),
    ));
  }
}

enum UploadStatus { pending, uploading, uploaded, failed }

class MediaItem {
  final String id, localPath;
  final bool isVideo;
  final DateTime createdAt;
  String? cloudUrl, publicId;
  bool isFavorite;
  UploadStatus status;

  MediaItem({
    required this.id,
    required this.localPath,
    required this.isVideo,
    required this.createdAt,
    this.cloudUrl,
    this.publicId,
    this.isFavorite = false,
  }) : status = publicId != null ? UploadStatus.uploaded : UploadStatus.pending;

  Map<String, dynamic> toJson() => {
        'id': id,
        'localPath': localPath,
        'cloudUrl': cloudUrl,
        'publicId': publicId,
        'isVideo': isVideo,
        'createdAt': createdAt.toIso8601String(),
        'isFavorite': isFavorite,
      };

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'],
        localPath: j['localPath'],
        isVideo: j['isVideo'],
        createdAt: DateTime.parse(j['createdAt']),
        cloudUrl: j['cloudUrl'],
        publicId: j['publicId'],
        isFavorite: j['isFavorite'] ?? false,
      );
}

/// Яндекс.Диск REST API.
class _Yandex {
  // Токен лучше передавать так: flutter run --dart-define=YANDEX_TOKEN=...
  static const _token = String.fromEnvironment('YANDEX_TOKEN',
      defaultValue:
          'y0__wgBEPyU4McFGKSsTCCd9s2wGTC4_YHlB2bj4Q894_kluUFsCvJN7UvybqFE');
  static const _api = 'https://cloud-api.yandex.net/v1/disk/resources';
  static const _folder = 'disk:/CloudCamera';
  static const _h = {
    'Authorization': 'OAuth $_token',
    'Accept': 'application/json',
  };

  static Uri _u(String sub, Map<String, String> q) =>
      Uri.parse('$_api$sub').replace(queryParameters: q);

  /// Возвращает путь на диске и публичную ссылку, либо null при ошибке.
  static Future<({String path, String? url})?> upload(File file) async {
    try {
      final remote = '$_folder/${file.uri.pathSegments.last}';
      await http.put(_u('', {'path': _folder}), headers: _h); // создать папку
      final r = await http.get(
          _u('/upload', {'path': remote, 'overwrite': 'true'}),
          headers: _h);
      if (r.statusCode != 200) return null;
      final put = await http.put(Uri.parse(jsonDecode(r.body)['href']),
          body: await file.readAsBytes(),
          headers: {'Content-Type': 'application/octet-stream'});
      if (put.statusCode != 201) return null;
      final pub = await http.put(_u('/publish', {'path': remote}), headers: _h);
      return (
        path: remote,
        url: pub.statusCode == 200 ? jsonDecode(pub.body)['href'] as String? : null,
      );
    } catch (_) {
      return null;
    }
  }

  /// 204 — удалено, 404 — файла уже нет.
  static Future<bool> delete(String path) async {
    try {
      final r = await http.delete(
          _u('', {'path': path, 'permanently': 'true'}),
          headers: _h);
      return r.statusCode == 204 || r.statusCode == 404;
    } catch (_) {
      return false;
    }
  }
}

/// Единое хранилище медиа: список в памяти + SharedPreferences + облако.
/// Экраны подписываются через ListenableBuilder.
class MediaStore extends ChangeNotifier {
  MediaStore._();
  static final i = MediaStore._();
  static const _key = 'media_items';

  List<MediaItem> items = [];

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    try {
      items = raw == null || raw.isEmpty
          ? []
          : (jsonDecode(raw) as List).map((e) => MediaItem.fromJson(e)).toList();
    } catch (_) {
      items = [];
    }
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> add(MediaItem it) {
    items.insert(0, it);
    return _save();
  }

  Future<bool> upload(MediaItem it) async {
    it.status = UploadStatus.uploading;
    notifyListeners();
    final r = await _Yandex.upload(File(it.localPath));
    if (r != null) {
      it.cloudUrl = r.url;
      it.publicId = r.path;
    }
    it.status = r != null ? UploadStatus.uploaded : UploadStatus.failed;
    await _save();
    return r != null;
  }

  Future<void> toggleFavorite(MediaItem it) {
    it.isFavorite = !it.isFavorite;
    return _save();
  }

  /// Удаляет файлы с телефона и из облака. false — если облако не ответило.
  Future<bool> remove(List<MediaItem> list) async {
    var cloudOk = true;
    for (final it in list) {
      if (it.publicId?.isNotEmpty ?? false) {
        cloudOk &= await _Yandex.delete(it.publicId!);
      }
      try {
        final f = File(it.localPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    final ids = list.map((e) => e.id).toSet();
    items.removeWhere((e) => ids.contains(e.id));
    await _save();
    return cloudOk;
  }
}
