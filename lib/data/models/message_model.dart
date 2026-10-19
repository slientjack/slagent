/// 工具调用记录模型（消息内的 tool_calls 元素）
class ToolCallModel {
  ToolCallModel({
    required this.tool,
    required this.args,
    required this.result,
  });

  /// 工具名称
  final String tool;

  /// 调用参数（保留原始结构）
  final dynamic args;

  /// 调用结果
  final dynamic result;

  /// 从 JSON 构造（args/result 可能是任意结构）
  factory ToolCallModel.fromJson(Map<String, dynamic> json) {
    return ToolCallModel(
      tool: json['tool']?.toString() ?? '',
      args: json['args'],
      result: json['result'],
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'tool': tool,
      'args': args,
      'result': result,
    };
  }
}

/// 聊天消息数据模型
class MessageModel {
  MessageModel({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolCalls,
    this.isError = false,
  });

  /// 唯一标识
  final String id;

  /// 角色：user / assistant / system
  final String role;

  /// 消息内容
  final String content;

  /// 时间戳（ISO 8601 字符串，由后端给定或本地生成）
  final String timestamp;

  /// 工具调用列表（可为 null）
  final List<ToolCallModel>? toolCalls;

  /// 是否为本地错误气泡（前端展示用，不参与序列化）
  final bool isError;

  /// 从 JSON 构造
  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final rawToolCalls = json['tool_calls'];
    List<ToolCallModel>? toolCalls;
    if (rawToolCalls is List) {
      toolCalls = rawToolCalls
          .whereType<Map<String, dynamic>>()
          .map((e) => ToolCallModel.fromJson(e))
          .toList();
    }
    return MessageModel(
      id: json['id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? '',
      toolCalls: toolCalls,
    );
  }

  /// 序列化为 JSON（isError 为前端状态，不序列化）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'timestamp': timestamp,
      if (toolCalls != null)
        'tool_calls': toolCalls!.map((e) => e.toJson()).toList(),
    };
  }

  /// 复制并修改部分字段
  MessageModel copyWith({
    String? id,
    String? role,
    String? content,
    String? timestamp,
    List<ToolCallModel>? toolCalls,
    bool? isError,
  }) {
    return MessageModel(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      toolCalls: toolCalls ?? this.toolCalls,
      isError: isError ?? this.isError,
    );
  }
}
