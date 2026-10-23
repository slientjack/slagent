import 'package:flutter/material.dart';

import '../../../../data/models/permission_request_model.dart';

/// 权限确认卡片：嵌在消息列表与输入框之间的内联授权条。
///
/// 相比模态对话框更轻量：不遮挡对话，随消息流出现在"思考中…"下方，
/// AI 越界操作时用户在原位即可完成授权。
///
/// 决策常量（与后端 PermissionDecision 一致）：
/// - allow_once    仅本次放行
/// - allow_session 本轮对话允许
/// - allow_always  自动允许（写入 permissions.json）
/// - deny          不允许
class PermissionCard extends StatelessWidget {
  const PermissionCard({
    super.key,
    required this.request,
    required this.onDecision,
  });

  /// 待确认的权限请求
  final PermissionRequestModel request;

  /// 用户选择授权范围后的回调（参数为决策常量）
  final ValueChanged<String> onDecision;

  /// 决策常量（与后端 PermissionDecision 一致）
  static const String allowOnce = 'allow_once';
  static const String allowSession = 'allow_session';
  static const String allowAlways = 'allow_always';
  static const String deny = 'deny';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final highRisk = request.isHighRisk;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highRisk
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highRisk
              ? scheme.error.withValues(alpha: 0.5)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：图标 + 标题 + 高风险标记
          Row(
            children: [
              Icon(
                highRisk
                    ? Icons.gpp_maybe_outlined
                    : Icons.verified_user_outlined,
                size: 16,
                color: highRisk ? scheme.error : scheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  request.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (highRisk)
                Text(
                  '高风险',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // 目标（路径或命令）：等宽字体单行展示，悬停可看全文
          Tooltip(
            message: request.target,
            child: Text(
              request.target,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'Menlo',
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // 四个授权选项：紧凑按钮，一行放不下自动换行
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _action(
                context,
                label: '允许单次运行',
                tooltip: '仅本次放行，不记忆',
                filled: true,
                decision: allowOnce,
              ),
              _action(
                context,
                label: '本轮对话允许',
                tooltip: '本次对话内同目录/同命令不再询问',
                decision: allowSession,
              ),
              _action(
                context,
                label: '自动允许',
                tooltip: '永久允许并写入配置，以后不再询问',
                decision: allowAlways,
              ),
              _action(
                context,
                label: '不允许',
                tooltip: '拒绝本次操作',
                decision: deny,
                danger: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建一个紧凑决策按钮
  Widget _action(
    BuildContext context, {
    required String label,
    required String tooltip,
    required String decision,
    bool filled = false,
    bool danger = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // 紧凑按钮：去掉默认内边距与点击区扩展，保证卡片小巧
    final compact = const VisualDensity(
      horizontal: VisualDensity.minimumDensity,
      vertical: VisualDensity.minimumDensity,
    );
    final compactPadding =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 4);
    final labelStyle = const TextStyle(fontSize: 12);

    return Tooltip(
      message: tooltip,
      child: filled
          ? FilledButton(
              style: FilledButton.styleFrom(
                visualDensity: compact,
                padding: compactPadding,
              ),
              onPressed: () => onDecision(decision),
              child: Text(label, style: labelStyle),
            )
          : TextButton(
              style: TextButton.styleFrom(
                visualDensity: compact,
                padding: compactPadding,
                foregroundColor: danger ? scheme.error : scheme.primary,
              ),
              onPressed: () => onDecision(decision),
              child: Text(label, style: labelStyle),
            ),
    );
  }
}
