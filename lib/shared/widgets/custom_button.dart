import 'package:flutter/material.dart';

/// 通用按钮：主按钮 / 次按钮 / 危险按钮
class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isPrimary = true,
    this.isDanger = false,
    this.isLoading = false,
  });

  /// 按钮文本
  final String label;

  /// 点击回调（null 时禁用）
  final VoidCallback? onPressed;

  /// 图标（可选）
  final IconData? icon;

  /// 是否主按钮（填充样式）
  final bool isPrimary;

  /// 是否危险操作样式（红色）
  final bool isDanger;

  /// 是否显示加载中（显示时禁用点击）
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveOnPressed =
        (onPressed == null || isLoading) ? null : onPressed;

    Widget child;
    if (isLoading) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      );
    } else if (icon != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(label)],
      );
    } else {
      child = Text(label);
    }

    if (isPrimary) {
      return FilledButton(
        style: isDanger
            ? FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              )
            : null,
        onPressed: effectiveOnPressed,
        child: child,
      );
    }
    return OutlinedButton(
      style: isDanger
          ? OutlinedButton.styleFrom(
              foregroundColor: colorScheme.error,
              side: BorderSide(color: colorScheme.error),
            )
          : null,
      onPressed: effectiveOnPressed,
      child: child,
    );
  }
}
