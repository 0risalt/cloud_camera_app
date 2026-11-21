import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../models/media_item.dart';
import '../services/yandex_disk_service.dart';
import '../services/storage_service.dart';
import '../services/gallery_events.dart';
import '../theme/app_theme.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _isRecording = false;
  bool _isInitializing = true;
  bool _autoUpload = true;
  bool _showFlash = false;

  final _cloud = YandexDiskService();
  final _storage = StorageService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final camStatus = await Permission.camera.request();
      final micStatus = await Permission.microphone.request();
      if (!camStatus.isGranted) {
        _snack('Нет доступа к камере');
        if (mounted) setState(() => _isInitializing = false);
        return;
      }
      if (!micStatus.isGranted) {
        _snack('Нет доступа к микрофону');
      }
    }

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _snack('Камеры не найдены');
        if (mounted) setState(() => _isInitializing = false);
        return;
      }
      await _startCamera(_cameras[_cameraIndex]);
    } catch (e) {
      _snack('Ошибка инициализации: $e');
    }

    if (mounted) setState(() => _isInitializing = false);
  }

  Future<void> _startCamera(CameraDescription desc) async {
    final controller = CameraController(
      desc,
      ResolutionPreset.high,
      enableAudio: true,
    );
    await controller.initialize();
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _controller?.dispose();
    _controller = null;
    await _startCamera(_cameras[_cameraIndex]);
  }

  Future<Directory> _getOutputDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'CloudCamera'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Быстрая белая вспышка на экране при снимке
  void _flashEffect() {
    setState(() => _showFlash = true);
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _showFlash = false);
    });
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      _snack('Камера не готова');
      return;
    }
    if (controller.value.isTakingPicture) return;

    try {
      _flashEffect();
      final file = await controller.takePicture();

      final dir = await _getOutputDir();
      final newPath = p.join(dir.path, '${const Uuid().v4()}.jpg');
      final saved = await File(file.path).copy(newPath);

      final item = MediaItem(
        id: const Uuid().v4(),
        localPath: saved.path,
        isVideo: false,
        createdAt: DateTime.now(),
      );

      await _saveItem(item);
      GalleryEvents.notifyChanged();

      if (_autoUpload) {
        _uploadItem(item);
      } else {
        _snack('Фото сохранено локально');
      }
    } catch (e) {
      _snack('Ошибка съёмки: $e');
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      if (_isRecording) {
        final file = await controller.stopVideoRecording();
        setState(() => _isRecording = false);

        final dir = await _getOutputDir();
        final newPath = p.join(dir.path, '${const Uuid().v4()}.mp4');
        final saved = await File(file.path).copy(newPath);

        final item = MediaItem(
          id: const Uuid().v4(),
          localPath: saved.path,
          isVideo: true,
          createdAt: DateTime.now(),
        );

        await _saveItem(item);
        GalleryEvents.notifyChanged();

        if (_autoUpload) {
          _uploadItem(item);
        } else {
          _snack('Видео сохранено локально');
        }
      } else {
        await controller.startVideoRecording();
        setState(() => _isRecording = true);
      }
    } catch (e) {
      _snack('Ошибка записи: $e');
      setState(() => _isRecording = false);
    }
  }

  Future<void> _saveItem(MediaItem item) async {
    final items = await _storage.loadItems();
    items.insert(0, item);
    await _storage.saveItems(items);
  }

  Future<void> _uploadItem(MediaItem item) async {
    item.status = UploadStatus.uploading;
    await _updateItem(item);
    GalleryEvents.notifyChanged();

    final result = await _cloud.uploadFile(File(item.localPath));

    if (result != null) {
      item.cloudUrl = result['publicUrl'];
      item.publicId = result['diskPath'];
      item.status = UploadStatus.uploaded;
      _snack('Загружено на Яндекс.Диск ✔', success: true);
    } else {
      item.status = UploadStatus.failed;
      _snack('Ошибка загрузки. Проверьте токен', error: true);
    }

    await _updateItem(item);
    GalleryEvents.notifyChanged();
  }

  Future<void> _updateItem(MediaItem item) async {
    final items = await _storage.loadItems();
    final idx = items.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      items[idx] = item;
      await _storage.saveItems(items);
    }
    if (mounted) setState(() {});
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
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withOpacity(0.4)),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _startCamera(_cameras[_cameraIndex]);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller != null && _controller!.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Камера'),
        backgroundColor: Colors.transparent,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _autoUpload
                    ? AppColors.success.withOpacity(0.5)
                    : AppColors.textSecondary.withOpacity(0.3),
              ),
            ),
            child: IconButton(
              tooltip: _autoUpload
                  ? 'Автозагрузка включена'
                  : 'Автозагрузка выключена',
              icon: Icon(
                _autoUpload ? Icons.cloud_done : Icons.cloud_off,
                color:
                    _autoUpload ? AppColors.success : AppColors.textSecondary,
              ),
              onPressed: () => setState(() => _autoUpload = !_autoUpload),
            ),
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : !ready
              ? const _CameraUnavailable()
              : Stack(
                  children: [
                    Positioned.fill(child: CameraPreview(_controller!)),

                    // Верхний градиент (для читаемости AppBar)
                    const Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 140,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.black54, Colors.transparent],
                          ),
                        ),
                      ),
                    ),

                    // Нижний градиент (для читаемости кнопок)
                    const Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 200,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black87, Colors.transparent],
                          ),
                        ),
                      ),
                    ),

                    // Индикатор записи
                    if (_isRecording)
                      const Positioned(
                        top: 100,
                        left: 0,
                        right: 0,
                        child: Center(child: _RecordingBadge()),
                      ),

                    // Кнопки
                    Positioned(
                      bottom: 40,
                      left: 0,
                      right: 0,
                      child: _CameraControls(
                        isRecording: _isRecording,
                        onFlip: _switchCamera,
                        onShutterTap: _takePhoto,
                        onShutterLongStart: _toggleRecording,
                        onShutterLongEnd: () {
                          if (_isRecording) _toggleRecording();
                        },
                      ),
                    ),

                    // Подсказка
                    const Positioned(
                      bottom: 14,
                      left: 0,
                      right: 0,
                      child: Text(
                        'Тап — фото, удержание — видео',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),

                    // Вспышка при снимке
                    IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: _showFlash ? 1 : 0,
                        duration: const Duration(milliseconds: 90),
                        child: Container(color: Colors.white),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.no_photography_outlined,
                size: 48, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const Text(
            'Камера недоступна',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Проверьте разрешения и подключение',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.danger.withOpacity(0.4),
            blurRadius: 16,
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_manual_record, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text(
            'REC',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraControls extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onFlip;
  final VoidCallback onShutterTap;
  final VoidCallback onShutterLongStart;
  final VoidCallback onShutterLongEnd;

  const _CameraControls({
    required this.isRecording,
    required this.onFlip,
    required this.onShutterTap,
    required this.onShutterLongStart,
    required this.onShutterLongEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CircleButton(
          icon: Icons.flip_camera_ios_outlined,
          onTap: isRecording ? null : onFlip,
        ),
        GestureDetector(
          onTap: onShutterTap,
          onLongPress: onShutterLongStart,
          onLongPressEnd: (_) => onShutterLongEnd(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: isRecording ? 72 : 84,
            height: isRecording ? 72 : 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
              border: Border.all(
                color: isRecording ? AppColors.danger : Colors.white,
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isRecording ? AppColors.danger : AppColors.primary)
                      .withOpacity(0.4),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isRecording ? 26 : 62,
                height: isRecording ? 26 : 62,
                decoration: BoxDecoration(
                  shape: isRecording ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: isRecording ? BorderRadius.circular(6) : null,
                  color: isRecording ? AppColors.danger : Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 56),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CircleButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.6),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white24,
            ),
          ),
          child: Icon(
            icon,
            color: onTap == null ? Colors.white38 : Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}
