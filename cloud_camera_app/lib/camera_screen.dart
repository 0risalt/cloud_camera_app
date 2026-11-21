import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'core.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver, Msg<CameraScreen> {
  static final _mobile = Platform.isAndroid || Platform.isIOS;

  CameraController? _ctrl;
  List<CameraDescription> _cameras = [];
  int _camIdx = 0;
  bool _recording = false, _initializing = true, _autoUpload = true, _flash = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      if (_mobile) {
        final cam = await Permission.camera.request();
        final mic = await Permission.microphone.request();
        if (!cam.isGranted) return msg('Нет доступа к камере');
        if (!mic.isGranted) msg('Нет доступа к микрофону');
      }
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return msg('Камеры не найдены');
      await _start();
    } catch (e) {
      msg('Ошибка инициализации: $e');
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _start() async {
    final c = CameraController(_cameras[_camIdx], ResolutionPreset.high,
        enableAudio: true);
    await c.initialize();
    if (!mounted) return c.dispose();
    setState(() => _ctrl = c);
  }

  Future<void> _flip() async {
    if (_cameras.length < 2) return;
    _camIdx = (_camIdx + 1) % _cameras.length;
    final old = _ctrl;
    setState(() => _ctrl = null);
    await old?.dispose();
    await _start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (!_mobile || _cameras.isEmpty || _initializing) return;
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
      final c = _ctrl;
      if (c == null) return;
      setState(() => _ctrl = null);
      c.dispose();
    } else if (s == AppLifecycleState.resumed && _ctrl == null) {
      _start();
    }
  }

  /// Копирует снятый файл в папку приложения, сохраняет и (если надо) грузит в облако.
  Future<void> _save(XFile f, {required bool video}) async {
    final base = await getApplicationDocumentsDirectory();
    final dir =
        await Directory(p.join(base.path, 'CloudCamera')).create(recursive: true);
    final saved = await File(f.path).copy(
        p.join(dir.path, '${const Uuid().v4()}${video ? '.mp4' : '.jpg'}'));
    final item = MediaItem(
      id: const Uuid().v4(),
      localPath: saved.path,
      isVideo: video,
      createdAt: DateTime.now(),
    );
    await MediaStore.i.add(item);

    if (!_autoUpload) {
      return msg(video ? 'Видео сохранено локально' : 'Фото сохранено локально');
    }
    if (await MediaStore.i.upload(item)) {
      msg('Загружено на Яндекс.Диск ✔', success: true);
    } else {
      msg('Ошибка загрузки. Проверьте токен', error: true);
    }
  }

  Future<void> _photo() async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return msg('Камера не готова');
    if (c.value.isTakingPicture) return;
    try {
      setState(() => _flash = true);
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted) setState(() => _flash = false);
      });
      await _save(await c.takePicture(), video: false);
    } catch (e) {
      msg('Ошибка съёмки: $e');
    }
  }

  Future<void> _toggleRec() async {
    final c = _ctrl;
    if (c == null || !c.value.isInitialized) return;
    try {
      if (_recording) {
        setState(() => _recording = false);
        await _save(await c.stopVideoRecording(), video: true);
      } else {
        await c.startVideoRecording();
        setState(() => _recording = true);
      }
    } catch (e) {
      msg('Ошибка записи: $e');
      if (mounted) setState(() => _recording = false);
    }
  }

  Widget _shade(bool top, Color c, double h) => Positioned(
        top: top ? 0 : null,
        bottom: top ? null : 0,
        left: 0,
        right: 0,
        height: h,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [c, Colors.transparent],
            ),
          ),
        ),
      );

  Widget _recBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: AppColors.danger.withOpacity(0.4), blurRadius: 16),
          ],
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.fiber_manual_record, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text('REC',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.2,
              )),
        ]),
      );

  Widget _controls() {
    final r = _recording;
    final c = r ? AppColors.danger : Colors.white;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: r ? null : _flip,
            borderRadius: BorderRadius.circular(40),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.6),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(Icons.flip_camera_ios_outlined,
                  color: r ? Colors.white38 : Colors.white, size: 24),
            ),
          ),
        ),
        GestureDetector(
          onTap: _photo,
          onLongPress: _toggleRec,
          onLongPressEnd: (_) {
            if (_recording) _toggleRec();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: r ? 72 : 84,
            height: r ? 72 : 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c, width: 4),
              boxShadow: [
                BoxShadow(
                  color: (r ? AppColors.danger : AppColors.primary)
                      .withOpacity(0.4),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: r ? 26 : 62,
                height: r ? 26 : 62,
                decoration: BoxDecoration(
                  shape: r ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: r ? BorderRadius.circular(6) : null,
                  color: c,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 56),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ctrl?.value.isInitialized ?? false;
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
                color: _autoUpload ? AppColors.success : AppColors.textSecondary,
              ),
              onPressed: () => setState(() => _autoUpload = !_autoUpload),
            ),
          ),
        ],
      ),
      body: _initializing
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : !ready
              ? const _Unavailable()
              : Stack(children: [
                  Positioned.fill(child: CameraPreview(_ctrl!)),
                  _shade(true, Colors.black54, 140),
                  _shade(false, Colors.black87, 200),
                  if (_recording)
                    Positioned(
                      top: 100,
                      left: 0,
                      right: 0,
                      child: Center(child: _recBadge()),
                    ),
                  Positioned(bottom: 40, left: 0, right: 0, child: _controls()),
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
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _flash ? 1 : 0,
                      duration: const Duration(milliseconds: 90),
                      child: Container(color: Colors.white),
                    ),
                  ),
                ]),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.no_photography_outlined,
                size: 48, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          const Text('Камера недоступна',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 6),
          const Text('Проверьте разрешения и подключение',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ]),
      );
}
