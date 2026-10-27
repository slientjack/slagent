import 'package:flutter/material.dart';

/// 亮/暗主题配置（Material 3）
///
/// 设计基调（ui-ux-pro-max 生成的设计系统）：
/// - 风格：Flat Design —— 无渐变、无阴影，靠色块与圆角建立层级
/// - 主色：Teal #0D9488（开发者工具气质，冷静专业）
/// - 过渡：150-200ms ease（桌面端 hover/press 反馈）
/// - 对比度：正文 ≥ 4.5:1，选中态用容器色而非投影
class AppTheme {
  AppTheme._();

  /// 主色（Teal 600）
  static const Color seedColor = Color(0xFF0D9488);

  /// 统一圆角
  static const double radiusSm = 8;
  static const double radiusMd = 10;
  static const double radiusLg = 14;

  /// 亮色主题
  static ThemeData get light => _base(Brightness.light).copyWith(
        inputDecorationTheme: _inputTheme(Brightness.light),
      );

  /// 暗色主题
  static ThemeData get dark => _base(Brightness.dark).copyWith(
        inputDecorationTheme: _inputTheme(Brightness.dark),
      );

  /// 公共主题骨架：配色 + 组件圆角/形态
  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // 桌面端字体走系统默认（macOS SF Pro / Windows Segoe UI，与 Inter 同气质），
      // 避免引入运行时下载的字体资产
      splashFactory: InkRipple.splashFactory,
      scaffoldBackgroundColor:
          brightness == Brightness.light ? scheme.surface : scheme.surface,
      // ---- 组件主题：统一圆角，克制过渡 ----
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        ),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
          )),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        ),
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(radiusSm)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        ),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: seedColor,
        inactiveTrackColor: Color(0x1A0D9488),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
    );
  }

  /// 输入框主题：圆角外边框 + filled 底色，focus 时主色描边
  static InputDecorationTheme _inputTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final border = OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(radiusMd)),
      borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
    );
    return InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.light
          ? scheme.onSurface.withValues(alpha: 0.03)
          : scheme.onSurface.withValues(alpha: 0.05),
      isDense: true,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(radiusMd)),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}
