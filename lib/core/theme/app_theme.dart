import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_shape.dart';
import 'app_type.dart';

/// Material theme for the Herbarium redesign, in a day and a night mood: paper
/// (or deep green) grounds, forest (or cream) ink, terracotta action, quiet corners with the leaf shape reserved
/// for signature surfaces, hairline rules, no resting shadows. Widgets inherit
/// everything from here so the screens only need lib/widgets/ui/.
class AppTheme {
  AppTheme._();

  static const RoundedRectangleBorder _square = AppShape.quietBorder;

  static OutlineInputBorder _fieldBorder(Color color, double width) =>
      OutlineInputBorder(
        borderRadius: AppShape.fieldRadius,
        borderSide: BorderSide(color: color, width: width),
      );

  static ThemeData get lightTheme => build(Brightness.light);
  static ThemeData get darkTheme => build(Brightness.dark);

  /// Builds the theme for [brightness]. It also switches [AppColors] to the
  /// matching palette first, because every colour below reads from it.
  static ThemeData build(Brightness brightness) {
    AppColors.dark = brightness == Brightness.dark;
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
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.canvas,
      canvasColor: AppColors.canvas,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: AppColors.raised,
      focusColor: AppColors.ink.withValues(alpha: 0.2),
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.accent,
        onPrimary: AppColors.onAccent,
        secondary: AppColors.accent,
        onSecondary: AppColors.onAccent,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        error: AppColors.danger,
        onError: AppColors.canvas,
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
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: _square,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        isDense: false,
        border: _fieldBorder(AppColors.muted, 1.5),
        enabledBorder: _fieldBorder(AppColors.muted, 1.5),
        disabledBorder: _fieldBorder(AppColors.rule, 1.5),
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
          backgroundColor: WidgetStatePropertyAll(AppColors.accent),
          foregroundColor: WidgetStatePropertyAll(AppColors.onAccent),
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
          backgroundColor: WidgetStatePropertyAll(AppColors.accent),
          foregroundColor: WidgetStatePropertyAll(AppColors.onAccent),
          minimumSize: minSize,
          shape: buttonShape,
          textStyle: WidgetStatePropertyAll(AppType.bodyStrong),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          foregroundColor: WidgetStatePropertyAll(AppColors.ink),
          side: WidgetStatePropertyAll(
              BorderSide(color: AppColors.ink, width: 1.5)),
          minimumSize: minSize,
          shape: buttonShape,
          textStyle: WidgetStatePropertyAll(AppType.bodyStrong),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(AppColors.ink),
          minimumSize: minSize,
          shape: buttonShape,
          textStyle: WidgetStatePropertyAll(AppType.bodyStrong),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
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
        trackOutlineColor: WidgetStatePropertyAll(AppColors.muted),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: _square,
        side: BorderSide(color: AppColors.muted, width: 2),
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? AppColors.accent
                : Colors.transparent),
        checkColor: WidgetStatePropertyAll(AppColors.onAccent),
      ),
      chipTheme: ChipThemeData(
        shape: _square,
        side: BorderSide.none,
        backgroundColor: AppColors.raised,
        selectedColor: AppColors.accent,
        labelStyle: AppType.label,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.rule,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        shape: _square,
        iconColor: AppColors.ink,
        textColor: AppColors.ink,
        titleTextStyle: AppType.bodyStrong,
        subtitleTextStyle: AppType.meta,
      ),
      iconTheme: IconThemeData(color: AppColors.ink, size: 24),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.raised,
        circularTrackColor: AppColors.raised,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 4,
        shape: AppShape.leafBorder,
        titleTextStyle: AppType.title,
        contentTextStyle: AppType.body,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 4,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        elevation: 4,
        shape: _square,
        textStyle: AppType.body,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: AppType.body,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppColors.surface),
          shape: const WidgetStatePropertyAll(_square),
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
        decoration: const BoxDecoration(
          color: AppColors.forest,
          borderRadius: AppShape.quiet,
        ),
        textStyle: AppType.label.copyWith(color: AppColors.onForest),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: AppType.body,
        shape: RoundedRectangleBorder(
          borderRadius: AppShape.quiet,
          side: BorderSide(color: AppColors.ink, width: 1.5),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(AppColors.raisedHover),
        radius: const Radius.circular(4),
      ),
    );
  }
}
