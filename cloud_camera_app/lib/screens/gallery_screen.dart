import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item.dart';
import '../services/yandex_disk_service.dart';
import '../services/storage_service.dart';
import '../services/gallery_events.dart';
import '../theme/app_theme.dart';

enum GalleryFilter { all, favorites, today, week, month }
enum GalleryTab { all, favorites }

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _storage = StorageService();
  final _cloud = YandexDiskService();

  List<MediaItem> _allItems = [];
  List<MediaItem> _visible = [];
  bool _loading = true;

  GalleryTab _tab = GalleryTab.all;
  GalleryFilter _filter = GalleryFilter.all;
  String _query = '';

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    GalleryEvents.revision.addListener(_onExternalChange);
  }

  @override
  void dispose() {
    GalleryEvents.revision.removeListener(_onExternalChange);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onExternalChange() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final items = await _storage.loadItems();
    if (!mounted) return;
    setState(() {
      _allItems = items;
      _loading = false;
      _applyFilters();
    });
  }

  void _applyFilters() {
    Iterable<MediaItem> list = _allItems;

    // Вкладка: избранное
    if (_tab == GalleryTab.favorites) {
      list = list.where((e) => e.isFavorite);
    }

    // Фильтр по дате
    final now = DateTime.now();
    switch (_filter) {
      case GalleryFilter.today:
        final start = DateTime(now.year, now.month, now.day);
        list = list.where((e) => e.createdAt.isAfter(start));
        break;
      case GalleryFilter.week:
        list = list.where(
            (e) => now.difference(e.createdAt).inDays <= 7);
        break;
      case GalleryFilter.month:
        list = list.where(
            (e) => now.difference(e.createdAt).inDays <= 30);
        break;
      case GalleryFilter.favorites:
        list = list.where((e) => e.isFavorite);
        break;
      case GalleryFilter.all:
        break;
    }

    // Поиск по имени файла
    if (_query.trim().isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where(
          (e) => e.localPath.toLowerCase().split(Platform.pathSeparator).last
              .contains(q));
    }

    _visible = list.toList();
  }

  void _snack(String msg, {bool success = false, bool error = false}) {
    if (!mounted) return;
    final color = error
        ? AppColors.danger
        : success
            ? AppColors.success
            : AppColors.primary;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error
                  ? Icons.error_outline
                  : success
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withOpacity(0.4)),
        ),
      ),
    );
  }

  // ==================== Загрузка ====================

  Future<void> _upload(MediaItem item) async {
    item.status = UploadStatus.uploading;
    setState(() {});
    await _persist(item);

    _snack('Загрузка на Яндекс.Диск...');
    final result = await _cloud.uploadFile(File(item.localPath));

    if (result != null) {
      item.cloudUrl = result['publicUrl'];
      item.publicId = result['diskPath'];
      item.status = UploadStatus.uploaded;
      _snack('Загружено ✔', success: true);
    } else {
      item.status = UploadStatus.failed;
      _snack('Ошибка загрузки', error: true);
    }
    await _persist(item);
    setState(() {});
  }

  // ==================== Удаление ====================

  Future<void> _delete(MediaItem item) async {
    final choice = await _confirmDelete(
      item.publicId != null && item.publicId!.isNotEmpty
          ? 'Файл будет удалён и с телефона, и из Яндекс.Диска.'
          : 'Файл будет удалён только с телефона.',
    );
    if (choice != 'ok') return;
    await _deleteSingle(item);
    if (mounted) setState(() {});
    _snack('Удалено', success: true);
  }

  Future<String?> _confirmDelete(String message) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'ok'),
            child: const Text(
              'Удалить',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSingle(MediaItem item) async {
    if (item.publicId != null && item.publicId!.isNotEmpty) {
      final ok = await _cloud.deleteFile(item.publicId!);
      if (!ok) _snack('Не удалось удалить из облака', error: true);
    }
    try {
      final f = File(item.localPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    _allItems.removeWhere((e) => e.id == item.id);
    await _storage.saveItems(_allItems);
    _applyFilters();
  }

  // ==================== Массовое удаление ====================

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;
    final choice = await _confirmDelete(
      'Удалить $count ${_plural(count, 'файл', 'файла', 'файлов')}? '
      'Файлы будут удалены и из облака (если были загружены).',
    );
    if (choice != 'ok') return;

    final toDelete =
        _allItems.where((e) => _selectedIds.contains(e.id)).toList();

    for (final item in toDelete) {
      if (item.publicId != null && item.publicId!.isNotEmpty) {
        await _cloud.deleteFile(item.publicId!);
      }
      try {
        final f = File(item.localPath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    _allItems.removeWhere((e) => _selectedIds.contains(e.id));
    await _storage.saveItems(_allItems);

    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
      _applyFilters();
    });
    _snack('Удалено: $count', success: true);
  }

  // ==================== Избранное ====================

  Future<void> _toggleFavorite(MediaItem item) async {
    setState(() {
      item.isFavorite = !item.isFavorite;
      _applyFilters();
    });
    await _storage.saveItems(_allItems);
  }

  // ==================== Прочее ====================

  Future<void> _persist(MediaItem item) async {
    final idx = _allItems.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      _allItems[idx] = item;
      await _storage.saveItems(_allItems);
    }
  }

  void _openViewer(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ViewerScreen(item: item),
      ),
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  static String _plural(int n, String one, String few, String many) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return few;
    }
    return many;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _GalleryHeader(
              count: _visible.length,
              selectionMode: _selectionMode,
              selectedCount: _selectedIds.length,
              onExitSelection: _exitSelection,
              onDeleteSelected: _deleteSelected,
            ),
            if (!_selectionMode) ...[
              _TabsRow(
                current: _tab,
                onChanged: (t) {
                  setState(() {
                    _tab = t;
                    _applyFilters();
                  });
                },
              ),
              _SearchBar(
                controller: _searchCtrl,
                onChanged: (v) {
                  setState(() {
                    _query = v;
                    _applyFilters();
                  });
                },
                currentFilter: _filter,
                onFilterChanged: (f) {
                  setState(() {
                    _filter = f;
                    _applyFilters();
                  });
                },
              ),
            ],
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _visible.isEmpty
                      ? _EmptyState(hasItems: _allItems.isNotEmpty)
                      : RefreshIndicator(
                          color: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          onRefresh: () => _load(silent: true),
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1,
                            ),
                            itemCount: _visible.length,
                            itemBuilder: (context, i) {
                              final item = _visible[i];
                              final selected = _selectedIds.contains(item.id);
                              return _MediaTile(
                                item: item,
                                selectionMode: _selectionMode,
                                selected: selected,
                                onTap: () {
                                  if (_selectionMode) {
                                    _toggleSelection(item.id);
                                  } else {
                                    _openViewer(item);
                                  }
                                },
                                onLongPress: () {
                                  setState(() {
                                    _selectionMode = true;
                                    _selectedIds.add(item.id);
                                  });
                                },
                                onUpload: () => _upload(item),
                                onDelete: () => _delete(item),
                                onToggleFavorite: () =>
                                    _toggleFavorite(item),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== Header ====================

class _GalleryHeader extends StatelessWidget {
  final int count;
  final bool selectionMode;
  final int selectedCount;
  final VoidCallback onExitSelection;
  final VoidCallback onDeleteSelected;

  const _GalleryHeader({
    required this.count,
    required this.selectionMode,
    required this.selectedCount,
    required this.onExitSelection,
    required this.onDeleteSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (selectionMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onExitSelection,
            ),
            Expanded(
              child: Text(
                'Выбрано: $selectedCount',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.danger),
              onPressed: selectedCount > 0 ? onDeleteSelected : null,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
                  blurRadius: 16,
                ),
              ],
            ),
            child: const Icon(Icons.cloud_queue, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Галерея',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                count == 0
                    ? 'Пока пусто'
                    : '$count ${_GalleryScreenState._plural(count, 'файл', 'файла', 'файлов')}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                const Icon(Icons.sync, color: AppColors.success, size: 14),
                const SizedBox(width: 4),
                Text(
                  'auto',
                  style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== Tabs ====================

class _TabsRow extends StatelessWidget {
  final GalleryTab current;
  final ValueChanged<GalleryTab> onChanged;

  const _TabsRow({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _TabButton(
            icon: Icons.grid_view_rounded,
            label: 'Все',
            active: current == GalleryTab.all,
            onTap: () => onChanged(GalleryTab.all),
          ),
          const SizedBox(width: 8),
          _TabButton(
            icon: Icons.star_rounded,
            label: 'Избранное',
            active: current == GalleryTab.favorites,
            activeColor: AppColors.favorite,
            onTap: () => onChanged(GalleryTab.favorites),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color? activeColor;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? color.withOpacity(0.15)
              : AppColors.surface.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? color.withOpacity(0.6) : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: active ? color : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? color : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== Search + Filter ====================

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final GalleryFilter currentFilter;
  final ValueChanged<GalleryFilter> onFilterChanged;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.currentFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Поиск по имени файла...',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.textSecondary),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: AppColors.textSecondary),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'Все',
                  active: currentFilter == GalleryFilter.all,
                  onTap: () => onFilterChanged(GalleryFilter.all),
                ),
                _FilterChip(
                  label: '⭐ Избранное',
                  active: currentFilter == GalleryFilter.favorites,
                  onTap: () => onFilterChanged(GalleryFilter.favorites),
                ),
                _FilterChip(
                  label: 'Сегодня',
                  active: currentFilter == GalleryFilter.today,
                  onTap: () => onFilterChanged(GalleryFilter.today),
                ),
                _FilterChip(
                  label: 'Неделя',
                  active: currentFilter == GalleryFilter.week,
                  onTap: () => onFilterChanged(GalleryFilter.week),
                ),
                _FilterChip(
                  label: 'Месяц',
                  active: currentFilter == GalleryFilter.month,
                  onTap: () => onFilterChanged(GalleryFilter.month),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withOpacity(0.18)
                : AppColors.surface.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active
                  ? AppColors.primary.withOpacity(0.6)
                  : AppColors.divider,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.primary : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== Empty ====================

class _EmptyState extends StatelessWidget {
  final bool hasItems;
  const _EmptyState({required this.hasItems});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.divider),
              ),
              child: Icon(
                hasItems
                    ? Icons.search_off_rounded
                    : Icons.photo_camera_back_outlined,
                size: 44,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasItems
                  ? 'Ничего не найдено'
                  : 'Пока нет медиа. Снимите что-нибудь!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== MediaTile ====================

class _MediaTile extends StatelessWidget {
  final MediaItem item;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onUpload;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  const _MediaTile({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onUpload,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: item.isVideo
                  ? Container(
                      color: Colors.black54,
                      child: const Center(
                        child: Icon(Icons.play_circle,
                            color: Colors.white, size: 42),
                      ),
                    )
                  : Image.file(
                      File(item.localPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image),
                    ),
            ),

            // Статус загрузки (полоса/бейдж)
            Positioned(
              left: 4,
              top: 4,
              child: _StatusBadge(status: item.status),
            ),

            // Иконка "избранное" на плитке
            if (item.isFavorite && !selectionMode)
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.star,
                      color: AppColors.favorite, size: 14),
                ),
              ),

            // Верхний правый угол: меню или галочка
            Positioned(
              top: 2,
              right: 2,
              child: selectionMode
                  ? Container(
                      margin: const EdgeInsets.all(4),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? AppColors.primary
                            : Colors.black54,
                        border: Border.all(color: Colors.white70, width: 1.5),
                      ),
                      child: selected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 14)
                          : null,
                    )
                  : PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          color: Colors.white, size: 18),
                      onSelected: (v) {
                        if (v == 'upload') onUpload();
                        if (v == 'delete') onDelete();
                        if (v == 'fav') onToggleFavorite();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'fav',
                          child: Row(
                            children: [
                              Icon(
                                item.isFavorite
                                    ? Icons.star_border
                                    : Icons.star,
                                color: AppColors.favorite,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(item.isFavorite
                                  ? 'Убрать из избранного'
                                  : 'В избранное'),
                            ],
                          ),
                        ),
                        if (item.status != UploadStatus.uploaded)
                          const PopupMenuItem(
                            value: 'upload',
                            child: Text('Загрузить в облако'),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete,
                                  color: AppColors.danger, size: 20),
                              SizedBox(width: 8),
                              Text('Удалить',
                                  style:
                                      TextStyle(color: AppColors.danger)),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== StatusBadge ====================

class _StatusBadge extends StatelessWidget {
  final UploadStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color c;
    IconData? ic;

    switch (status) {
      case UploadStatus.uploaded:
        c = AppColors.success;
        ic = Icons.cloud_done;
        break;
      case UploadStatus.uploading:
        c = AppColors.warning;
        ic = null; // покажем спиннер
        break;
      case UploadStatus.failed:
        c = AppColors.danger;
        ic = Icons.cloud_off;
        break;
      case UploadStatus.pending:
        c = AppColors.textSecondary;
        ic = Icons.cloud_queue;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withOpacity(0.6), width: 1),
      ),
      child: ic != null
          ? Icon(ic, size: 12, color: c)
          : SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation(c),
              ),
            ),
    );
  }
}

// ==================== Viewer ====================

class _ViewerScreen extends StatelessWidget {
  final MediaItem item;
  const _ViewerScreen({required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          DateFormat('dd.MM.yyyy HH:mm').format(item.createdAt),
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: item.isVideo
                ? _VideoPlayerView(path: item.localPath)
                : PhotoView(
                    imageProvider: FileImage(File(item.localPath)),
                    backgroundDecoration:
                        const BoxDecoration(color: Colors.black),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.black,
            child: Column(
              children: [
                if (item.cloudUrl != null)
                  SelectableText(
                    item.cloudUrl!,
                    style: const TextStyle(
                        color: Colors.lightBlueAccent, fontSize: 12),
                  )
                else
                  const Text('Не загружено в облако',
                      style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPlayerView extends StatefulWidget {
  final String path;
  const _VideoPlayerView({required this.path});

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(_controller),
          VideoProgressIndicator(_controller, allowScrubbing: true),
          Center(
            child: IconButton(
              iconSize: 60,
              icon: Icon(
                _controller.value.isPlaying
                    ? Icons.pause_circle
                    : Icons.play_circle,
                color: Colors.white70,
              ),
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}