import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

import 'core.dart';

enum _Range { all, today, week, month }

String _plural(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'файл';
  if (m10 >= 2 && m10 <= 4 && (m100 < 10 || m100 >= 20)) return 'файла';
  return 'файлов';
}

final _fmt = DateFormat('dd.MM.yyyy HH:mm');

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> with Msg<GalleryScreen> {
  final _store = MediaStore.i;
  final _search = TextEditingController();
  final _sel = <String>{};
  bool _favOnly = false, _selecting = false;
  _Range _range = _Range.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MediaItem> get _visible {
    final q = _search.text.trim().toLowerCase();
    final now = DateTime.now();
    bool inRange(MediaItem e) => switch (_range) {
          _Range.all => true,
          _Range.today =>
            e.createdAt.isAfter(DateTime(now.year, now.month, now.day)),
          _Range.week => now.difference(e.createdAt).inDays <= 7,
          _Range.month => now.difference(e.createdAt).inDays <= 30,
        };
    return _store.items
        .where((e) =>
            (!_favOnly || e.isFavorite) &&
            inRange(e) &&
            (q.isEmpty ||
                File(e.localPath).uri.pathSegments.last.toLowerCase().contains(q)))
        .toList();
  }

  Future<void> _upload(MediaItem it) async {
    msg('Загрузка на Яндекс.Диск...');
    if (await _store.upload(it)) {
      msg('Загружено ✔', success: true);
    } else {
      msg('Ошибка загрузки', error: true);
    }
  }

  Future<void> _delete(List<MediaItem> list) async {
    final n = list.length;
    final text = n > 1
        ? 'Удалить $n ${_plural(n)}? Файлы будут удалены и из облака (если были загружены).'
        : (list.first.publicId?.isNotEmpty ?? false)
            ? 'Файл будет удалён и с телефона, и из Яндекс.Диска.'
            : 'Файл будет удалён только с телефона.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить?'),
        content: Text(text),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    final cloudOk = await _store.remove(list);
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _sel.clear();
    });
    if (!cloudOk) msg('Не удалось удалить из облака', error: true);
    msg(n > 1 ? 'Удалено: $n' : 'Удалено', success: true);
  }

  void _toggle(String id) => setState(() {
        if (!_sel.remove(id)) _sel.add(id);
        if (_sel.isEmpty) _selecting = false;
      });

  Widget _header(int count) {
    if (_selecting) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Row(children: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() {
              _selecting = false;
              _sel.clear();
            }),
          ),
          Expanded(
            child: Text('Выбрано: ${_sel.length}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                )),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            onPressed: _sel.isEmpty
                ? null
                : () => _delete(
                    _store.items.where((e) => _sel.contains(e.id)).toList()),
          ),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withOpacity(0.3), blurRadius: 16),
            ],
          ),
          child: const Icon(Icons.cloud_queue, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Галерея',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              )),
          Text(count == 0 ? 'Пока пусто' : '$count ${_plural(count)}',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.divider),
          ),
          child: const Row(children: [
            Icon(Icons.sync, color: AppColors.success, size: 14),
            SizedBox(width: 4),
            Text('auto',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                )),
          ]),
        ),
      ]),
    );
  }

  Widget _filters() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(children: [
          Row(children: [
            _Chip('Все', !_favOnly, () => setState(() => _favOnly = false),
                icon: Icons.grid_view_rounded),
            _Chip('Избранное', _favOnly, () => setState(() => _favOnly = true),
                icon: Icons.star_rounded, color: AppColors.favorite),
          ]),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Поиск по имени файла...',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.textSecondary),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear,
                            color: AppColors.textSecondary),
                        onPressed: () => setState(_search.clear),
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (r, label) in [
                (_Range.all, 'Все'),
                (_Range.today, 'Сегодня'),
                (_Range.week, 'Неделя'),
                (_Range.month, 'Месяц'),
              ])
                _Chip(label, _range == r, () => setState(() => _range = r)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _store,
            builder: (_, __) {
              final items = _visible;
              return Column(children: [
                _header(items.length),
                if (!_selecting) _filters(),
                Expanded(
                  child: items.isEmpty
                      ? _empty(_store.items.isNotEmpty)
                      : RefreshIndicator(
                          color: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          onRefresh: _store.load,
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final it = items[i];
                              return _Tile(
                                item: it,
                                selecting: _selecting,
                                selected: _sel.contains(it.id),
                                onTap: () => _selecting
                                    ? _toggle(it.id)
                                    : Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) => _Viewer(item: it))),
                                onLongPress: () => setState(() {
                                  _selecting = true;
                                  _sel.add(it.id);
                                }),
                                onUpload: () => _upload(it),
                                onDelete: () => _delete([it]),
                                onFav: () => _store.toggleFavorite(it),
                              );
                            },
                          ),
                        ),
                ),
              ]);
            },
          ),
        ),
      );

  Widget _empty(bool hasItems) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
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
              hasItems ? 'Ничего не найдено' : 'Пока нет медиа. Снимите что-нибудь!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
        ),
      );
}

/// Универсальная «таблетка»: вкладки и фильтры по дате.
class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final Color color;

  const _Chip(this.label, this.active, this.onTap,
      {this.icon, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    final fg = active ? color : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? color.withOpacity(0.16)
                : AppColors.surface.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active ? color.withOpacity(0.6) : AppColors.divider),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final MediaItem item;
  final bool selecting, selected;
  final VoidCallback onTap, onLongPress, onUpload, onDelete, onFav;

  const _Tile({
    required this.item,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onUpload,
    required this.onDelete,
    required this.onFav,
  });

  Widget _badge(Widget child, {Color? border}) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
          border: border == null ? null : Border.all(color: border, width: 1),
        ),
        child: child,
      );

  Widget _status() {
    final (Color, IconData?) s = switch (item.status) {
      UploadStatus.uploaded => (AppColors.success, Icons.cloud_done),
      UploadStatus.uploading => (AppColors.warning, null),
      UploadStatus.failed => (AppColors.danger, Icons.cloud_off),
      UploadStatus.pending => (AppColors.textSecondary, Icons.cloud_queue),
    };
    return _badge(
      s.$2 != null
          ? Icon(s.$2, size: 12, color: s.$1)
          : SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation(s.$1),
              ),
            ),
      border: s.$1.withOpacity(0.6),
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
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
          child: Stack(fit: StackFit.expand, children: [
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
            Positioned(left: 4, top: 4, child: _status()),
            if (item.isFavorite && !selecting)
              Positioned(
                left: 4,
                bottom: 4,
                child: _badge(
                    const Icon(Icons.star, color: AppColors.favorite, size: 14)),
              ),
            Positioned(
              top: 2,
              right: 2,
              child: selecting
                  ? Container(
                      margin: const EdgeInsets.all(4),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? AppColors.primary : Colors.black54,
                        border: Border.all(color: Colors.white70, width: 1.5),
                      ),
                      child: selected
                          ? const Icon(Icons.check, color: Colors.white, size: 14)
                          : null,
                    )
                  : PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          color: Colors.white, size: 18),
                      onSelected: (v) {
                        if (v == 'upload') onUpload();
                        if (v == 'delete') onDelete();
                        if (v == 'fav') onFav();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'fav',
                          child: Row(children: [
                            Icon(
                              item.isFavorite ? Icons.star_border : Icons.star,
                              color: AppColors.favorite,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(item.isFavorite
                                ? 'Убрать из избранного'
                                : 'В избранное'),
                          ]),
                        ),
                        if (item.status != UploadStatus.uploaded)
                          const PopupMenuItem(
                              value: 'upload', child: Text('Загрузить в облако')),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            Icon(Icons.delete, color: AppColors.danger, size: 20),
                            SizedBox(width: 8),
                            Text('Удалить',
                                style: TextStyle(color: AppColors.danger)),
                          ]),
                        ),
                      ],
                    ),
            ),
          ]),
        ),
      );
}

class _Viewer extends StatelessWidget {
  final MediaItem item;
  const _Viewer({required this.item});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(_fmt.format(item.createdAt),
              style: const TextStyle(fontSize: 16)),
        ),
        body: Column(children: [
          Expanded(
            child: item.isVideo
                ? _Video(path: item.localPath)
                : PhotoView(
                    imageProvider: FileImage(File(item.localPath)),
                    backgroundDecoration:
                        const BoxDecoration(color: Colors.black),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: item.cloudUrl != null
                ? SelectableText(item.cloudUrl!,
                    style: const TextStyle(
                        color: Colors.lightBlueAccent, fontSize: 12))
                : const Text('Не загружено в облако',
                    style: TextStyle(color: Colors.grey)),
          ),
        ]),
      );
}

class _Video extends StatefulWidget {
  final String path;
  const _Video({required this.path});

  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  late final _c = VideoPlayerController.file(File(widget.path));

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _c.play();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: _c,
        builder: (_, v, __) => !v.isInitialized
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: AspectRatio(
                  aspectRatio: v.aspectRatio,
                  child: Stack(alignment: Alignment.bottomCenter, children: [
                    VideoPlayer(_c),
                    VideoProgressIndicator(_c, allowScrubbing: true),
                    Center(
                      child: IconButton(
                        iconSize: 60,
                        color: Colors.white70,
                        icon: Icon(v.isPlaying
                            ? Icons.pause_circle
                            : Icons.play_circle),
                        onPressed: () => v.isPlaying ? _c.pause() : _c.play(),
                      ),
                    ),
                  ]),
                ),
              ),
      );
}
