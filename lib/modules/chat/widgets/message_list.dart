import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../shared/widgets/loading_indicator.dart';
import '../controllers/chat_controller.dart';
import 'message_bubble.dart';

/// 消息列表：reverse 布局（新消息在底部，天然自动滚到底），虚拟化构建
class MessageList extends StatelessWidget {
  const MessageList({super.key, required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final messages = controller.messages;
      final isLoading = controller.isLoading.value;

      // 空态引导
      if (messages.isEmpty && !isLoading) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 56,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                '开始新的对话吧',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '在下方输入框中发送消息，AI 助手可以读写当前工作区目录中的文件',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
      }

      // typing 指示占用列表首项（reverse 布局下即视觉最底部）
      final itemCount = messages.length + (isLoading ? 1 : 0);

      return ListView.builder(
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (isLoading && index == 0) {
            return const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: LoadingIndicator(label: '思考中…'),
              ),
            );
          }
          // 消息按时间正序存储，reverse 列表需倒序取（最新在 index 0）
          final msgIndex =
              isLoading ? index - 1 : index;
          final message = messages[messages.length - 1 - msgIndex];
          return MessageBubble(
            message: message,
            onRetry: message.isError ? controller.retryLastFailed : null,
          );
        },
      );
    });
  }
}
