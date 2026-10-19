/// 应用级常量
class AppConstants {
  AppConstants._();

  /// 应用名称
  static const String appName = 'slagent';

  /// 应用版本
  static const String appVersion = '1.0.0';

  /// 后端就绪标记正则（stdout 行：AGENT_SERVER_READY port=1234）
  static final RegExp serverReadyPattern = RegExp(r'AGENT_SERVER_READY port=(\d+)');

  /// 后端启动总超时
  static const Duration backendStartupTimeout = Duration(seconds: 30);

  /// 可选的上下文长度选项
  static const List<int> contextLengthOptions = [2048, 4096, 8192, 16384];

  /// 温度滑块范围
  static const double minTemperature = 0.0;
  static const double maxTemperature = 2.0;
  static const int temperatureDivisions = 20;

  /// 环境变量：完整后端启动命令（空格分隔）
  static const String backendCmdEnv = 'AGENT_BACKEND_CMD';
}
