import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../chat/views/chat_view.dart';
import '../../settings/controllers/settings_controller.dart';
import '../controllers/workspace_controller.dart';
import '../widgets/create_workspace_dialog.dart';
import '../widgets/workspace_list_item.dart';

/// 主界面骨架：左侧栏（工作区列表+新建+设置入口）+ 右侧聊天区
class WorkspaceView extends GetView<WorkspaceController> {
  const WorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 未配置 API Key 的醒目横幅
          _ApiKeyBanner(),
          Expanded(
            child: Row(
              children: [
                // 左侧栏
                _Sidebar(controller: controller),
                const VerticalDivider(width: 1),
                // 右侧内容区
                Expanded(child: Obx(() {
                  final ws = controller.currentWorkspace.value;
                  if (ws == null) {
                    return const _EmptyWorkspaceGuide();
                  }
                  return ChatView(workspace: ws);
                })),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// API Key 未配置横幅：点击跳转设置页
class _ApiKeyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final settingsController = Get.find<SettingsController>();
    return Obx(() {
      // 设置尚未加载完成或已配置 Key 时不显示
      final settings = settingsController.settings.value;
      if (settings == null || settings.apiKeyConfigured) {
        return const SizedBox.shrink();
      }
      return Material(
        color: colorScheme.errorContainer,
        child: InkWell(
          onTap: () => Get.toNamed<void>(AppRoutes.settings),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.key_off, size: 18, color: colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '尚未配置 API Key，点击设置',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onErrorContainer,
                        ),
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: colorScheme.onErrorContainer),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// 左侧栏：标题 + 新建按钮 + 工作区列表 + 底部设置齿轮
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 240,
      color: colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // 顶部标题 + 新建按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '工作区',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: '新建工作区',
                  icon: const Icon(Icons.add),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const CreateWorkspaceDialog(),
                  ),
                ),
              ],
            ),
          ),
          // 工作区列表
          Expanded(
            child: Obx(() {
              if (controller.workspaces.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      controller.isLoading.value ? '加载中…' : '暂无工作区\n点击右上角 + 创建',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                );
              }
              return ListView.builder(
                itemCount: controller.workspaces.length,
                itemBuilder: (context, index) {
                  final ws = controller.workspaces[index];
                  return WorkspaceListItem(
                    workspace: ws,
                    isSelected:
                        controller.currentWorkspace.value?.id == ws.id,
                    onTap: () => controller.selectWorkspace(ws),
                    onDelete: () => _confirmDelete(context, ws.name, ws.id),
                  );
                },
              );
            }),
          ),
          // 底部设置入口
          const Divider(height: 1),
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Get.toNamed<void>(AppRoutes.settings),
            ),
          ),
        ],
      ),
    );
  }

  /// 删除二次确认：仅移除记录，不删除本地文件
  void _confirmDelete(BuildContext context, String name, String id) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除工作区'),
        content: Text('确定删除工作区「$name」吗？\n仅移除记录，不删除本地文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.deleteWorkspace(id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 未选中工作区时的引导
class _EmptyWorkspaceGuide extends StatelessWidget {
  const _EmptyWorkspaceGuide();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.create_new_folder_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text('还没有选中的工作区',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '在左侧栏选择一个工作区，或点击「+」创建新的工作区开始使用',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
