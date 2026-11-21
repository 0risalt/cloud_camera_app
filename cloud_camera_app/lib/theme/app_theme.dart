import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0E0E12);
  static const bgAlt = Color(0xFF16161E);
  static const surface = Color(0xFF1E1E28);
  static const surfaceAlt = Color(0xFF262633);
  static const primary = Color(0xFF7C6CFF);
  static const primaryAlt = Color(0xFF9F8FFF);
  static const accent = Color(0xFF4ADEDE);
  static const success = Color(0xFF4CD964);
  static const warning = Color(0xFFFFB020);
  static const danger = Color(0xFFFF4E5B);
  static const selected = Color(0xFF7C6CFF);
  static const favorite = Color(0xFFFFC93C);
  static const textPrimary = Color(0xFFF2F2F7);
  static const textSecondary = Color(0xFFA0A0B0);
  static const divider = Color(0xFF2C2C3A);
}

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.bgAlt,
        indicatorColor: AppColors.primary.withOpacity(0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary);
          }
          return const IconThemeData(color: AppColors.textSecondary);
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
    );
  }
}
