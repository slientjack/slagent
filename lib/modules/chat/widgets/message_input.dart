import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// 多行消息输入框（1~6 行）+ 发送/停止按钮
/// Enter 发送，Shift+Enter 换行；思考中按钮变为"停止"并可终止生成
class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.onSend,
    this.isEnabled = true,
    this.isThinking = false,
    this.onStop,
    this.hintText,
  });

  /// 发送回调
  final ValueChanged<String> onSend;

  /// 是否可用（loading 时禁用输入）
  final bool isEnabled;

  /// 模型是否正在思考（按钮切换为停止图标）
  final bool isThinking;

  /// 停止生成本次回复的回调（思考中点击按钮触发）
  final VoidCallback? onStop;

  /// 占位提示
  final String? hintText;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();

  final FocusNode _focusNode = FocusNode();

  final RxBool _canSend = false.obs;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      _canSend.value = widget.isEnabled && _controller.text.trim().isNotEmpty;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 发送并清空输入
  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.isEnabled) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            // Enter（无修饰键）发送；Shift+Enter 走默认行为（插入换行）
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): _send,
                const SingleActivator(LogicalKeyboardKey.numpadEnter): _send,
              },
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.isEnabled,
                // 高度随内容从 1 行增长到最多 6 行，超出后内部滚动
                maxLines: 6,
                minLines: 1,
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: widget.hintText ?? '输入消息，Enter 发送，Shift+Enter 换行',
                  suffixIcon: widget.isEnabled
                      ? null
                      : const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 思考中显示"停止"按钮（终止本次生成），否则显示发送按钮
          Obx(() {
            // 无条件读取：Obx 要求回调内至少访问一个响应式变量
            final canSend = _canSend.value;
            if (widget.isThinking) {
              return IconButton.filled(
                onPressed: widget.onStop,
                icon: const Icon(Icons.stop_rounded),
                tooltip: '停止生成',
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.errorContainer,
                  foregroundColor: colorScheme.onErrorContainer,
                ),
              );
            }
            return IconButton.filled(
              onPressed: canSend ? _send : null,
              icon: const Icon(Icons.send_rounded),
              tooltip: '发送',
            );
          }),
        ],
      ),
    );
  }
}
