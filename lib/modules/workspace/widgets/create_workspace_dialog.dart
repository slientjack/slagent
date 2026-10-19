import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/utils/validators.dart';
import '../controllers/workspace_controller.dart';

/// 新建工作区对话框：名称输入 + 浏览目录（file_picker）+ 校验错误提示
class CreateWorkspaceDialog extends StatefulWidget {
  const CreateWorkspaceDialog({super.key});

  @override
  State<CreateWorkspaceDialog> createState() => _CreateWorkspaceDialogState();
}

class _CreateWorkspaceDialogState extends State<CreateWorkspaceDialog> {
  final TextEditingController _nameController = TextEditingController();

  final TextEditingController _pathController = TextEditingController();

  /// 前端校验错误提示（名称/路径格式）
  String? _nameError;

  String? _pathError;

  /// 后端返回的错误信息（如目录不存在）
  String? _serverError;

  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  /// 打开目录选择器
  Future<void> _pickDirectory() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择工作区目录',
    );
    if (dir != null) {
      setState(() {
        _pathController.text = dir;
        _pathError = null;
      });
    }
  }

  /// 提交创建
  Future<void> _submit() async {
    // 前端校验
    final nameError = Validators.validateWorkspaceName(_nameController.text);
    final pathError = Validators.validateWorkspacePath(_pathController.text);
    setState(() {
      _nameError = nameError;
      _pathError = pathError;
      _serverError = null;
    });
    if (nameError != null || pathError != null) return;

    setState(() => _submitting = true);
    final controller = Get.find<WorkspaceController>();
    final ok = await controller.createWorkspace(
      name: _nameController.text.trim(),
      path: _pathController.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _serverError = controller.errorMessage.value ?? '创建失败，请稍后重试';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建工作区'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '名称',
                hintText: '例如：我的项目',
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: '目录路径',
                      hintText: '点击右侧按钮选择目录',
                      errorText: _pathError,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickDirectory,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('浏览目录'),
                ),
              ],
            ),
            if (_serverError != null) ...[
              const SizedBox(height: 12),
              Text(
                _serverError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('创建'),
        ),
      ],
    );
  }
}
