import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../data/models/message_model.dart';
import '../controllers/chat_controller.dart';

/// 单条消息气泡：用户右/蓝、AI 左/灰；错误气泡红边框+重试；tool_calls 折叠展示
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onRetry,
  });

  final MessageModel message;

  /// 重试回调（仅错误气泡显示）
  final VoidCallback? onRetry;

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 系统错误气泡：红色边框样式 + 重试按钮
    if (message.isError) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 520),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.3),
            border: Border.all(color: colorScheme.error, width: 1.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 16, color: colorScheme.error),
                  const SizedBox(width: 6),
                  Text(
                    '请求失败',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const Spacer(),
                  if (onRetry != null)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('重试'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                message.content,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    // 普通气泡
    final bubbleColor = _isUser
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final textColor =
        _isUser ? colorScheme.onPrimary : colorScheme.onSurface;

    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(_isUser ? 12 : 4),
            bottomRight: Radius.circular(_isUser ? 4 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.content.isNotEmpty)
              SelectableText(
                message.content,
                style:
                    Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
              ),
            // tool_calls 折叠展示
            if (message.toolCalls != null && message.toolCalls!.isNotEmpty)
              _ToolCallsView(toolCalls: message.toolCalls!),
            const SizedBox(height: 4),
            Text(
              ChatController.formatTime(message.timestamp),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: textColor.withValues(alpha: 0.6),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// tool_calls 折叠面板（点开看 tool/args/result）
class _ToolCallsView extends StatelessWidget {
  const _ToolCallsView({required this.toolCalls});

  final List<ToolCallModel> toolCalls;

  /// 格式化任意结构为缩进 JSON 文本（便于阅读 args/result）
  String _pretty(Object? data) {
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Theme(
      // 去掉 ExpansionTile 默认的内边距，紧凑展示
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          '工具调用 (${toolCalls.length})',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _isOnPrimaryBubble(colorScheme),
                fontWeight: FontWeight.w600,
              ),
        ),
        iconColor: _isOnPrimaryBubble(colorScheme),
        collapsedIconColor: _isOnPrimaryBubble(colorScheme),
        children: toolCalls.map((tc) {
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🔧 ${tc.tool}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text('参数:',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: colorScheme.primary)),
                SelectableText(
                  _pretty(tc.args),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
                const SizedBox(height: 4),
                Text('结果:',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: colorScheme.primary)),
                SelectableText(
                  _pretty(tc.result),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _isOnPrimaryBubble(ColorScheme colorScheme) =>
      colorScheme.onSurface.withValues(alpha: 0.7);
}
