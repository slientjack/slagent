import 'package:flutter/material.dart';

/// 三点跳动 loading 指示器
class LoadingIndicator extends StatefulWidget {
  const LoadingIndicator({
    super.key,
    this.size = 8,
    this.color,
    this.label,
  });

  /// 圆点直径
  final double size;

  /// 圆点颜色（默认取主题主色）
  final Color? color;

  /// 附带文本（如"思考中…"）
  final String? label;

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                // 每个点错开 1/3 周期跳动
                final t = (_controller.value * 3 - i).clamp(0.0, 1.0);
                final bounce = (t < 0.5) ? t * 2 : (1 - t) * 2;
                final dy = -4 * bounce;
                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: widget.size * 0.3),
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.4 + 0.6 * bounce),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
        if (widget.label != null) ...[
          const SizedBox(width: 8),
          Text(
            widget.label!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}
