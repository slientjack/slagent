import 'package:flutter/material.dart';

import '../../../../data/models/workspace_model.dart';

/// 工作区列表项：选中高亮；右键（onSecondaryTapUp）弹出操作菜单
class WorkspaceListItem extends StatelessWidget {
  const WorkspaceListItem({
    super.key,
    required this.workspace,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  final WorkspaceModel workspace;

  /// 是否为当前选中项
  final bool isSelected;

  /// 单击选中
  final VoidCallback onTap;

  /// 删除动作（含二次确认，由调用方实现）
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          onSecondaryTapUp: (details) =>
              _showContextMenu(context, details.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    workspace.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : null,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 右键菜单（当前提供删除动作；删除的二次确认由上层触发）
  void _showContextMenu(BuildContext context, Offset position) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: const [
        PopupMenuItem(
          value: 'delete',
          height: 40,
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18),
              SizedBox(width: 8),
              Text('删除工作区'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        onDelete();
      }
    });
  }
}
