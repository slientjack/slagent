/// 可选模型项
class AvailableModel {
  AvailableModel({required this.id, required this.name});

  /// 模型标识
  final String id;

  /// 模型显示名称
  final String name;

  factory AvailableModel.fromJson(Map<String, dynamic> json) {
    return AvailableModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// 应用设置数据模型
class SettingsModel {
  SettingsModel({
    required this.model,
    required this.temperature,
    required this.maxContextLength,
    required this.apiKeyConfigured,
    this.availableModels = const [],
  });

  /// 当前模型标识
  final String model;

  /// 温度
  final double temperature;

  /// 最大上下文长度
  final int maxContextLength;

  /// 是否已配置 API Key
  final bool apiKeyConfigured;

  /// 可选模型列表
  final List<AvailableModel> availableModels;

  /// 从 JSON 构造（兼容 GET /api/settings 返回结构）
  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    final settings = (json['settings'] as Map<String, dynamic>?) ?? const {};
    final rawModels = json['available_models'];
    final models = <AvailableModel>[];
    if (rawModels is List) {
      for (final m in rawModels) {
        if (m is Map<String, dynamic>) {
          models.add(AvailableModel.fromJson(m));
        }
      }
    }
    return SettingsModel(
      model: settings['model']?.toString() ?? 'deepseek',
      temperature:
          double.tryParse(settings['temperature']?.toString() ?? '') ?? 0.7,
      maxContextLength:
          int.tryParse(settings['max_context_length']?.toString() ?? '') ??
              4096,
      apiKeyConfigured: settings['api_key_configured'] == true,
      availableModels: models,
    );
  }

  /// 序列化为 JSON（保存 settings 部分）
  Map<String, dynamic> toJson() {
    return {
      'settings': {
        'model': model,
        'temperature': temperature,
        'max_context_length': maxContextLength,
        'api_key_configured': apiKeyConfigured,
      },
      'available_models': availableModels.map((e) => e.toJson()).toList(),
    };
  }

  /// 复制并修改部分字段
  SettingsModel copyWith({
    String? model,
    double? temperature,
    int? maxContextLength,
    bool? apiKeyConfigured,
    List<AvailableModel>? availableModels,
  }) {
    return SettingsModel(
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      maxContextLength: maxContextLength ?? this.maxContextLength,
      apiKeyConfigured: apiKeyConfigured ?? this.apiKeyConfigured,
      availableModels: availableModels ?? this.availableModels,
    );
  }
}
