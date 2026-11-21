import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/media_item.dart';
import '../services/storage_service.dart';
import '../services/gallery_events.dart';
import '../theme/app_theme.dart';

class SlideshowScreen extends StatefulWidget {
  const SlideshowScreen({super.key});

  @override
  State<SlideshowScreen> createState() => _SlideshowScreenState();
}

class _SlideshowScreenState extends State<SlideshowScreen> {
  final _storage = StorageService();
  List<MediaItem> _items = [];
  bool _loading = true;
  bool _playing = false;
  int _index = 0;
  Timer? _timer;
  int _interval = 3; // секунды

  @override
  void initState() {
    super.initState();
    _load();
    GalleryEvents.revision.addListener(_onChange);
  }

  @override
  void dispose() {
    GalleryEvents.revision.removeListener(_onChange);
    _timer?.cancel();
    super.dispose();
  }

  void _onChange() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final items = await _storage.loadItems();
    if (!mounted) return;
    setState(() {
      // Оставляем только фото (видео в слайдшоу не крутим)
      _items = items.where((e) => !e.isVideo).toList();
      if (_index >= _items.length) _index = 0;
      _loading = false;
    });
  }

  void _togglePlay() {
    if (_items.isEmpty) return;
    setState(() => _playing = !_playing);
    _timer?.cancel();
    if (_playing) {
      _timer = Timer.periodic(Duration(seconds: _interval), (_) {
        if (!mounted) return;
        setState(() {
          _index = (_index + 1) % _items.length;
        });
      });
    }
  }

  void _next() {
    if (_items.isEmpty) return;
    setState(() => _index = (_index + 1) % _items.length);
  }

  void _prev() {
    if (_items.isEmpty) return;
    setState(() => _index = (_index - 1 + _items.length) % _items.length);
  }

  void _setInterval(int s) {
    setState(() => _interval = s);
    if (_playing) {
      _timer?.cancel();
      _timer = Timer.periodic(Duration(seconds: s), (_) {
        if (!mounted) return;
        setState(() {
          _index = (_index + 1) % _items.length;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.slideshow, color: AppColors.primary, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Слайдшоу',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _items.isEmpty
                      ? const Center(
                          child: Text(
                            'Нет фото для слайдшоу',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  child: Container(
                                    key: ValueKey(_index),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.5),
                                          blurRadius: 24,
                                        ),
                                      ],
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Image.file(
                                      File(_items[_index].localPath),
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${_index + 1} / ${_items.length}  •  '
                              '${DateFormat('dd.MM.yyyy HH:mm').format(_items[_index].createdAt)}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _Controls(
                              playing: _playing,
                              interval: _interval,
                              onPlay: _togglePlay,
                              onPrev: _prev,
                              onNext: _next,
                              onInterval: _setInterval,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final bool playing;
  final int interval;
  final VoidCallback onPlay;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int> onInterval;

  const _Controls({
    required this.playing,
    required this.interval,
    required this.onPlay,
    required this.onPrev,
    required this.onNext,
    required this.onInterval,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ControlButton(icon: Icons.skip_previous, onTap: onPrev),
            const SizedBox(width: 20),
            GestureDetector(
              onTap: onPlay,
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Icon(
                  playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(width: 20),
            _ControlButton(icon: Icons.skip_next, onTap: onNext),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Интервал:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(width: 8),
            ...[2, 3, 5, 10].map(
              (s) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => onInterval(s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: interval == s
                          ? AppColors.primary.withOpacity(0.2)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: interval == s
                            ? AppColors.primary
                            : AppColors.divider,
                      ),
                    ),
                    child: Text(
                      '$sс',
                      style: TextStyle(
                        color: interval == s
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ControlButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, color: AppColors.textPrimary, size: 26),
        ),
      ),
    );
  }
}
