import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_item.dart';

class StorageService {
  static const _key = 'media_items';

  Future<List<MediaItem>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => MediaItem.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveItems(List<MediaItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(items.map((e) => e.toJson()).toList());
    await prefs.setString(_key, raw);
  }
}
