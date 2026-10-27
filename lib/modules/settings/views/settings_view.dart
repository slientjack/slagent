import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/app_constants.dart';
import '../controllers/settings_controller.dart';

/// 设置页：API Key / 模型 / 温度 / 上下文长度
class SettingsView extends GetView<SettingsController> {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.settings.value == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final settings = controller.settings.value;
        if (settings == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('设置加载失败'),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: controller.loadSettings,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重试'),
                ),
              ],
            ),
          );
        }
        return _SettingsForm(controller: controller);
      }),
    );
  }
}

/// 设置表单
class _SettingsForm extends StatefulWidget {
  const _SettingsForm({required this.controller});

  final SettingsController controller;

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  final TextEditingController _apiKeyController = TextEditingController();

  final RxBool _obscureApiKey = true.obs;

  late String? _selectedModel;

  late double _temperature;

  late int _maxContextLength;

  String? _saveError;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.settings.value!;
    _selectedModel = s.model;
    _temperature = s.temperature;
    _maxContextLength = s.maxContextLength;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  /// 保存设置
  Future<void> _save() async {
    final error = await widget.controller.saveSettings(
      apiKey: _apiKeyController.text.trim().isEmpty
          ? null
          : _apiKeyController.text.trim(),
      model: _selectedModel,
      temperature: _temperature,
      maxContextLength: _maxContextLength,
    );
    if (!mounted) return;
    if (error == null) {
      setState(() => _saveError = null);
      _apiKeyController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
    } else {
      setState(() => _saveError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.controller.settings.value!;
    final models = settings.availableModels;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.all(24),
        child: ListView(
          shrinkWrap: true,
          children: [
            // 分组一：API Key
            _groupCard(
              context,
              icon: Icons.key_rounded,
              title: 'API Key',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    settings.apiKeyConfigured
                        ? '已配置，留空则保持不变'
                        : '尚未配置，请输入模型服务 API Key',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: settings.apiKeyConfigured
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.error,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Obx(() => TextField(
                        controller: _apiKeyController,
                        obscureText: _obscureApiKey.value,
                        decoration: InputDecoration(
                          hintText: 'sk-...',
                          suffixIcon: IconButton(
                            tooltip: _obscureApiKey.value ? '显示' : '隐藏',
                            icon: Icon(
                              _obscureApiKey.value
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => _obscureApiKey.toggle(),
                          ),
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 分组二：模型与生成参数
            _groupCard(
              context,
              icon: Icons.tune_rounded,
              title: '模型与生成参数',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedModel,
                    decoration:
                        const InputDecoration(labelText: '模型'),
                    items: models
                        .map((m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.name),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedModel = v),
                  ),
                  const SizedBox(height: 16),
                  Text('温度（temperature）',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _temperature.clamp(AppConstants.minTemperature,
                              AppConstants.maxTemperature),
                          min: AppConstants.minTemperature,
                          max: AppConstants.maxTemperature,
                          divisions: AppConstants.temperatureDivisions,
                          label: _temperature.toStringAsFixed(1),
                          onChanged: (v) => setState(() => _temperature = v),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          _temperature.toStringAsFixed(1),
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: AppConstants.contextLengthOptions
                            .contains(_maxContextLength)
                        ? _maxContextLength
                        : AppConstants.contextLengthOptions.first,
                    decoration:
                        const InputDecoration(labelText: '上下文长度'),
                    items: AppConstants.contextLengthOptions
                        .map((len) => DropdownMenuItem(
                              value: len,
                              child: Text(len.toString()),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _maxContextLength = v ?? _maxContextLength),
                  ),
                ],
              ),
            ),

            // 保存错误提示
            if (_saveError != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 16, color: colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _saveError!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            // 保存按钮
            Obx(() => FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 44),
                  ),
                  onPressed:
                      widget.controller.isSaving.value ? null : _save,
                  icon: widget.controller.isSaving.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('保存设置'),
                )),
          ],
        ),
      ),
    );
  }

  /// 分组卡片：图标 + 标题 + 内容（Flat 风格：浅容器色 + 圆角，无阴影）
  Widget _groupCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
