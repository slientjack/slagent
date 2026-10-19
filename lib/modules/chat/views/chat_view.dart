import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../data/models/workspace_model.dart';
import '../controllers/chat_controller.dart';
import '../widgets/message_input.dart';
import '../widgets/message_list.dart';

/// 聊天视图：消息列表 + 输入区
class ChatView extends StatelessWidget {
  ChatView({super.key, required this.workspace});

  /// 当前工作区
  final WorkspaceModel workspace;

  final ChatController controller = Get.find<ChatController>();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 顶部信息栏：工作区名称 + 路径 + 清空会话
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      workspace.path,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '清空会话',
                icon: const Icon(Icons.cleaning_services_outlined),
                onPressed: () => _confirmClear(context),
              ),
            ],
          ),
        ),
        // 消息列表
        Expanded(child: MessageList(controller: controller)),
        // 输入区
        Obx(() => MessageInput(
              onSend: controller.send,
              isEnabled: !controller.isLoading.value,
            )),
      ],
    );
  }

  /// 清空前二次确认
  void _confirmClear(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空会话'),
        content: const Text('确定要清空当前工作区的所有对话记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.clear();
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}
