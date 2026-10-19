/// 工作区数据模型
class WorkspaceModel {
  WorkspaceModel({
    required this.id,
    required this.name,
    required this.path,
    required this.createdAt,
  });

  /// 唯一标识
  final String id;

  /// 工作区名称
  final String name;

  /// 本地目录路径
  final String path;

  /// 创建时间（ISO 8601 字符串或时间戳，由后端给定）
  final String createdAt;

  /// 从 JSON 构造
  factory WorkspaceModel.fromJson(Map<String, dynamic> json) {
    return WorkspaceModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'createdAt': createdAt,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is WorkspaceModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
