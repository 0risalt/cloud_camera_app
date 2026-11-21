import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class YandexDiskService {
  // OAuth-токен Яндекс.Диска
  static const String _token =
      'y0__wgBEPyU4McFGKSsTCCd9s2wGTC4_YHlB2bj4Q894_kluUFsCvJN7UvybqFE';

  static const String _apiUrl =
      'https://cloud-api.yandex.net/v1/disk/resources';
  static const String _folder = 'disk:/CloudCamera';

  Map<String, String> get _headers => {
        'Authorization': 'OAuth $_token',
        'Accept': 'application/json',
      };

  /// Загружает файл на Яндекс.Диск в папку disk:/CloudCamera
  Future<Map<String, dynamic>?> uploadFile(File file) async {
    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final remotePath = '$_folder/$fileName';

      await _ensureFolder();

      final uploadUrlResponse = await http.get(
        Uri.parse('$_apiUrl/upload').replace(queryParameters: {
          'path': remotePath,
          'overwrite': 'true',
        }),
        headers: _headers,
      );

      if (uploadUrlResponse.statusCode != 200) {
        print('Yandex get upload URL error: '
            '${uploadUrlResponse.statusCode} ${uploadUrlResponse.body}');
        return null;
      }

      final uploadUrlData = jsonDecode(uploadUrlResponse.body);
      final uploadUrl = uploadUrlData['href'] as String;

      final fileBytes = await file.readAsBytes();
      final uploadResponse = await http.put(
        Uri.parse(uploadUrl),
        body: fileBytes,
        headers: {'Content-Type': 'application/octet-stream'},
      );

      if (uploadResponse.statusCode != 201) {
        print('Yandex upload error: '
            '${uploadResponse.statusCode} ${uploadResponse.body}');
        return null;
      }

      final publishResponse = await http.put(
        Uri.parse('$_apiUrl/publish').replace(queryParameters: {
          'path': remotePath,
        }),
        headers: _headers,
      );

      String? publicUrl;
      if (publishResponse.statusCode == 200) {
        final publishData = jsonDecode(publishResponse.body);
        publicUrl = publishData['href'];
      }

      return {
        'diskPath': remotePath,
        'publicUrl': publicUrl,
      };
    } catch (e) {
      print('Yandex upload exception: $e');
      return null;
    }
  }

  /// Удаляет файл с Яндекс.Диска.
  /// remotePath — полный путь, например: disk:/CloudCamera/uuid.jpg
  Future<bool> deleteFile(String remotePath) async {
    try {
      final response = await http.delete(
        Uri.parse(_apiUrl).replace(queryParameters: {
          'path': remotePath,
          'permanently': 'true',
        }),
        headers: _headers,
      );

      // 204 — успешно удалено; 404 — файла уже нет
      if (response.statusCode == 204 || response.statusCode == 404) {
        return true;
      }

      print('Yandex delete error: '
          '${response.statusCode} ${response.body}');
      return false;
    } catch (e) {
      print('Yandex delete exception: $e');
      return false;
    }
  }

  /// Создаёт папку CloudCamera, если её ещё нет
  Future<void> _ensureFolder() async {
    try {
      final response = await http.put(
        Uri.parse(_apiUrl).replace(queryParameters: {'path': _folder}),
        headers: _headers,
      );
      if (response.statusCode != 201 && response.statusCode != 409) {
        print('Yandex folder create status: '
            '${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Yandex folder create exception: $e');
    }
  }
}
