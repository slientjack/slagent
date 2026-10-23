/// 后端发起的越界操作授权请求
class PermissionRequestModel {
  PermissionRequestModel({
    required this.id,
    required this.workspaceId,
    required this.type,
    required this.target,
    required this.detail,
    required this.risk,
    required this.createdAt,
  });

  /// 请求唯一标识（提交决策时回传）
  final String id;

  /// 所属工作区 id
  final String workspaceId;

  /// 请求类型：file_access / command
  final String type;

  /// 请求目标：文件绝对路径或完整命令
  final String target;

  /// 给用户看的说明文本
  final String detail;

  /// 风险级别：normal / high
  final String risk;

  /// 创建时间（ISO 8601）
  final String createdAt;

  /// 是否文件访问类请求
  bool get isFileAccess => type == 'file_access';

  /// 是否为高风险操作（危险命令等）
  bool get isHighRisk => risk == 'high';

  /// 对话框标题
  String get title => isFileAccess ? '访问工作区外文件' : '执行白名单外命令';

  /// 从 JSON 构造
  factory PermissionRequestModel.fromJson(Map<String, dynamic> json) {
    return PermissionRequestModel(
      id: json['id']?.toString() ?? '',
      workspaceId: json['workspace_id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      target: json['target']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      risk: json['risk']?.toString() ?? 'normal',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}
