import 'package:flutter/material.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _pages = [
    CameraScreen(),
    GalleryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bg, AppColors.bgAlt],
          ),
        ),
        child: IndexedStack(index: _index, children: _pages),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.bgAlt,
          border: Border(
            top: BorderSide(color: AppColors.divider.withOpacity(0.5)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          height: 68,
          backgroundColor: Colors.transparent,
          elevation: 0,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.camera_alt_outlined),
              selectedIcon: Icon(Icons.camera_alt, color: AppColors.primary),
              label: 'Камера',
            ),
            NavigationDestination(
              icon: Icon(Icons.photo_library_outlined),
              selectedIcon: Icon(Icons.photo_library, color: AppColors.primary),
              label: 'Галерея',
            ),
          ],
        ),
      ),
    );
  }
}
