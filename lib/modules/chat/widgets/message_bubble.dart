import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/utils/logger.dart';
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
              // 用户消息保持纯文本；AI 消息用 Markdown 渲染（代码块/链接/表格）
              _isUser
                  ? SelectableText(
                      message.content,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: textColor),
                    )
                  : _AiMarkdown(content: message.content, textColor: textColor),
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

/// AI 消息的 Markdown 渲染：支持代码块、链接、表格、列表等。
/// 使用 [GptMarkdown]（专为 LLM 输出设计，容错半截/流式 Markdown）。
class _AiMarkdown extends StatelessWidget {
  const _AiMarkdown({required this.content, required this.textColor});

  final String content;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return GptMarkdown(
      content,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
      // 链接点击：用系统默认浏览器打开
      onLinkTap: (url, title) async {
        final uri = Uri.tryParse(url);
        if (uri == null) return;
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          Logger.w('打开链接失败: $url, $e');
        }
      },
      // 代码块：深色卡片 + 语言标签 + 复制按钮 + 语法高亮
      codeBuilder: (context, name, code, closed) =>
          _CodeBlockView(language: name, code: code),
    );
  }
}

/// Markdown 代码块：深色卡片，带语言标签、复制按钮与语法高亮，
/// 超长代码在块内水平/垂直滚动（类似主流 AI 聊天应用）。
class _CodeBlockView extends StatefulWidget {
  const _CodeBlockView({required this.language, required this.code});

  /// 代码块标注的语言（```dart 中的 dart），可能为空
  final String language;
  final String code;

  @override
  State<_CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<_CodeBlockView> {
  bool _copied = false;

  // 深色代码卡片配色（VS Code Dark+ 风格）
  static const Color _bg = Color(0xFF1E1E24);
  static const Color _defaultCodeColor = Color(0xFFD4D4D4);

  /// highlight 包 token class → 颜色（精简版 Dark+ 主题）
  static const Map<String, Color> _tokenColors = {
    'comment': Color(0xFF6A9955),
    'keyword': Color(0xFF569CD6),
    'built_in': Color(0xFFDCDCAA),
    'type': Color(0xFF4EC9B0),
    'class': Color(0xFF4EC9B0),
    'title': Color(0xFFDCDCAA),
    'function': Color(0xFFDCDCAA),
    'string': Color(0xFFCE9178),
    'number': Color(0xFFB5CEA8),
    'literal': Color(0xFF569CD6),
    'variable': Color(0xFF9CDCFE),
    'property': Color(0xFF9CDCFE),
    'params': Color(0xFF9CDCFE),
    'attribute': Color(0xFF9CDCFE),
    'tag': Color(0xFF569CD6),
    'name': Color(0xFF569CD6),
    'meta': Color(0xFF808080),
    'regexp': Color(0xFFD16969),
    'deletion': Color(0xFFD16969),
    'addition': Color(0xFF6A9955),
    'section': Color(0xFFDCDCAA),
    'selector-tag': Color(0xFF569CD6),
    'selector-class': Color(0xFFD7BA7D),
    'selector-id': Color(0xFFD7BA7D),
    'bullet': Color(0xFFD7BA7D),
    'quote': Color(0xFF6A9955),
  };

  /// 复制代码到剪贴板，按钮短暂变为"已复制"
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// 递归把 highlight 解析树转换为 TextSpan
  List<InlineSpan> _convertNodes(List<hl.Node>? nodes) {
    final spans = <InlineSpan>[];
    if (nodes == null) return spans;
    for (final node in nodes) {
      TextStyle? style;
      if (node.className != null) {
        final color = _tokenColors[node.className!];
        if (color != null) style = TextStyle(color: color);
      }
      if (node.value != null && node.value!.isNotEmpty) {
        spans.add(TextSpan(text: node.value, style: style));
      }
      spans.addAll(_convertNodes(node.children));
    }
    return spans;
  }

  /// 生成高亮 TextSpan；未知语言或解析失败时回退为纯色文本
  TextSpan _highlightSpan() {
    const base = TextStyle(
      color: _defaultCodeColor,
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.5,
    );
    if (widget.language.isEmpty) {
      return TextSpan(text: widget.code, style: base);
    }
    try {
      final result = hl.highlight.parse(widget.code, language: widget.language);
      return TextSpan(
        text: '',
        style: base,
        children: _convertNodes(result.nodes),
      );
    } catch (_) {
      return TextSpan(text: widget.code, style: base);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // 固定占满气泡可用宽度，视觉上与 ChatGPT 等代码块一致
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部：语言标签 + 复制按钮
          Container(
            padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
            color: Colors.white.withValues(alpha: 0.06),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.language.isEmpty ? '代码' : widget.language,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: _copy,
                  icon: Icon(
                    _copied ? Icons.check : Icons.copy,
                    size: 14,
                    color: Colors.white70,
                  ),
                  label: Text(
                    _copied ? '已复制' : '复制',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          // 代码区：纵向最大高度限制 + 横向滚动
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                child: SelectableText.rich(_highlightSpan()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
