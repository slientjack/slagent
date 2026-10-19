import 'package:get/get.dart';

import '../../../../data/models/settings_model.dart';
import '../../../../data/services/backend_service.dart';

/// 设置控制器：加载/保存模型设置
class SettingsController extends GetxService {
  SettingsController({required BackendService backendService})
      : _backend = backendService;

  final BackendService _backend;

  /// 当前设置（含可选模型列表）
  final Rxn<SettingsModel> settings = Rxn<SettingsModel>();

  /// 加载中
  final RxBool isLoading = false.obs;

  /// 保存中
  final RxBool isSaving = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadSettings();
  }

  /// 是否已配置 API Key
  bool get apiKeyConfigured => settings.value?.apiKeyConfigured ?? false;

  /// 从后端加载设置
  Future<void> loadSettings() async {
    isLoading.value = true;
    try {
      final data = await _backend.get('/api/settings');
      Map<String, dynamic> map;
      if (data is Map<String, dynamic>) {
        map = data;
      } else {
        map = const {};
      }
      settings.value = SettingsModel.fromJson(map);
    } catch (_) {
      // 加载失败保持 null，页面显示错误提示
      settings.value = null;
    } finally {
      isLoading.value = false;
    }
  }

  /// 保存设置（部分更新：api_key / model / temperature / max_context_length）
  Future<String?> saveSettings({
    String? apiKey,
    String? model,
    double? temperature,
    int? maxContextLength,
  }) async {
    isSaving.value = true;
    try {
      final body = <String, dynamic>{};
      if (apiKey != null && apiKey.trim().isNotEmpty) body['api_key'] = apiKey.trim();
      if (model != null) body['model'] = model;
      if (temperature != null) body['temperature'] = temperature;
      if (maxContextLength != null) body['max_context_length'] = maxContextLength;

      await _backend.put('/api/settings', body: body);
      // 保存成功后刷新一次设置状态
      await loadSettings();
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      isSaving.value = false;
    }
  }
}
