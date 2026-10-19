/// API 相关常量：路径与超时时间
class ApiConstants {
  ApiConstants._();

  /// 本地后端基础地址（端口由后端启动时动态分配）
  static const String localHost = '127.0.0.1';

  /// 健康检查
  static const String health = '/health';

  /// 工作区列表/创建
  static const String workspaces = '/api/workspaces';

  /// 删除指定工作区（拼接 id）
  static String workspaceById(String id) => '/api/workspaces/$id';

  /// 设置读取/更新
  static const String settings = '/api/settings';

  /// 聊天历史
  static const String chatHistory = '/api/chat/history';

  /// 清空会话
  static const String chatClear = '/api/chat/clear';

  /// 发送消息
  static const String chatSend = '/api/chat/send';

  /// 普通请求超时时间
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// 发送消息超时时间（LLM 推理可能较慢）
  static const Duration chatTimeout = Duration(seconds: 300);

  /// 健康检查次数
  static const int healthCheckRetries = 5;

  /// 健康检查间隔
  static const Duration healthCheckInterval = Duration(milliseconds: 500);
}
