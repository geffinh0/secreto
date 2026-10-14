import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_type.dart';

/// Material theme for the Swiss redesign: square corners, flat fills, no
/// borders, no resting shadows. Widgets inherit everything from here so the
/// screens only need the shared components in lib/widgets/ui/.
class AppTheme {
  AppTheme._();

  static const RoundedRectangleBorder _square = RoundedRectangleBorder();

  static OutlineInputBorder _fieldBorder(Color color, double width) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: color, width: width),
      );

  static ThemeData get darkTheme {
    final text = TextTheme(
      displayLarge: AppType.display,
      displayMedium: AppType.title,
      headlineMedium: AppType.title,
      titleLarge: AppType.title,
      titleMedium: AppType.heading,
      titleSmall: AppType.label,
      bodyLarge: AppType.body,
      bodyMedium: AppType.body,
      bodySmall: AppType.meta,
      labelLarge: AppType.bodyStrong,
      labelMedium: AppType.label,
      labelSmall: AppType.label,
    );

    const buttonShape = WidgetStatePropertyAll<OutlinedBorder>(_square);
    const minSize = WidgetStatePropertyAll<Size>(Size(48, 48));

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.canvas,
      canvasColor: AppColors.canvas,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: AppColors.raised,
      focusColor: AppColors.ink.withValues(alpha: 0.4),
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        onPrimary: AppColors.onAccent,
        secondary: AppColors.accent,
        onSecondary: AppColors.onAccent,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        error: AppColors.danger,
        onError: AppColors.ink,
        surfaceContainerHighest: AppColors.raised,
      ),
      textTheme: text,
      primaryTextTheme: text,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      }),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: _square,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.raised,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        isDense: false,
        border: _fieldBorder(Colors.transparent, 0),
        enabledBorder: _fieldBorder(Colors.transparent, 0),
        disabledBorder: _fieldBorder(Colors.transparent, 0),
        focusedBorder: _fieldBorder(AppColors.accent, 2),
        errorBorder: _fieldBorder(AppColors.danger, 2),
        focusedErrorBorder: _fieldBorder(AppColors.danger, 2),
        labelStyle: AppType.meta,
        floatingLabelStyle: AppType.label,
        hintStyle: AppType.meta,
        errorStyle: AppType.label.copyWith(color: AppColors.danger),
        helperStyle: AppType.meta,
        prefixIconColor: AppColors.muted,
        suffixIconColor: AppColors.muted,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.accent,
        selectionColor: AppColors.accent.withValues(alpha: 0.35),
        selectionHandleColor: AppColors.accent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.accent),
          foregroundColor: const WidgetStatePropertyAll(AppColors.onAccent),
          minimumSize: minSize,
          elevation: const WidgetStatePropertyAll(0),
          shape: buttonShape,
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
          textStyle: WidgetStatePropertyAll(AppType.bodyStrong),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.accent),
          foregroundColor: const WidgetStatePropertyAll(AppColors.onAccent),
          minimumSize: minSize,
          shape: buttonShape,
          textStyle: WidgetStatePropertyAll(AppType.bodyStrong),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(AppColors.raised),
          foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
          side: const WidgetStatePropertyAll(BorderSide.none),
          minimumSize: minSize,
          shape: buttonShape,
          textStyle: WidgetStatePropertyAll(AppType.bodyStrong),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
          minimumSize: minSize,
          shape: buttonShape,
          textStyle: WidgetStatePropertyAll(AppType.bodyStrong),
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: minSize,
          shape: buttonShape,
          foregroundColor: WidgetStatePropertyAll(AppColors.ink),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.onAccent
                : AppColors.muted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.raised),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: _square,
        side: const BorderSide(color: AppColors.muted, width: 2),
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.accent
                : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(AppColors.onAccent),
      ),
      chipTheme: ChipThemeData(
        shape: _square,
        side: BorderSide.none,
        backgroundColor: AppColors.raised,
        selectedColor: AppColors.accent,
        labelStyle: AppType.label,
      ),
      dividerTheme: const DividerThemeData(
        color: Colors.transparent,
        thickness: 0,
        space: 0,
      ),
      listTileTheme: ListTileThemeData(
        shape: _square,
        iconColor: AppColors.ink,
        textColor: AppColors.ink,
        titleTextStyle: AppType.bodyStrong,
        subtitleTextStyle: AppType.meta,
      ),
      iconTheme: const IconThemeData(color: AppColors.ink, size: 24),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.raised,
        circularTrackColor: AppColors.raised,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 8,
        shape: _square,
        titleTextStyle: AppType.title,
        contentTextStyle: AppType.body,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 8,
        shape: _square,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.raised,
        elevation: 8,
        shape: _square,
        textStyle: AppType.body,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: AppType.body,
        menuStyle: const MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.raised),
          shape: WidgetStatePropertyAll(_square),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.ink,
        unselectedLabelColor: AppColors.muted,
        labelStyle: AppType.label,
        unselectedLabelStyle: AppType.label,
        indicatorColor: AppColors.accent,
        dividerColor: Colors.transparent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(color: AppColors.raised),
        textStyle: AppType.label,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.raised,
        contentTextStyle: AppType.body,
        shape: _square,
        behavior: SnackBarBehavior.floating,
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(AppColors.raisedHover),
        radius: Radius.zero,
      ),
    );
  }
}
