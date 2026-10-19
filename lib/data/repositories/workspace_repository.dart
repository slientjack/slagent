import 'package:get/get.dart';

import '../../core/utils/logger.dart';
import '../models/workspace_model.dart';
import '../services/backend_service.dart';
import '../services/storage_service.dart';

/// 工作区数据仓库：基于后端 API 的工作区操作（带本地缓存）
class WorkspaceRepository extends GetxService {
  WorkspaceRepository({
    required BackendService backendService,
    required StorageService storageService,
  })  : _backend = backendService,
        _storage = storageService;

  final BackendService _backend;
  final StorageService _storage;

  /// 读取缓存的列表（启动时先行渲染用）
  Future<List<WorkspaceModel>> loadCached() async {
    final cached = await _storage.loadWorkspaces();
    if (cached == null) return [];
    try {
      return cached.map(WorkspaceModel.fromJson).toList();
    } catch (e) {
      Logger.w('解析缓存工作区失败: $e');
      return [];
    }
  }

  /// 获取工作区列表
  Future<List<WorkspaceModel>> fetchWorkspaces() async {
    final data = await _backend.get('/api/workspaces');
    final list = (data['workspaces'] as List? ?? []);
    final result =
        list.whereType<Map<String, dynamic>>().map(WorkspaceModel.fromJson).toList();
    // 同步写缓存
    await _storage.saveWorkspaces(result.map((e) => e.toJson()).toList());
    return result;
  }

  /// 创建工作区（400=名称/路径非法，404=目录不存在，错误信息由后端 detail 提供）
  Future<WorkspaceModel> createWorkspace({
    required String name,
    required String path,
  }) async {
    final data = await _backend.post(
      '/api/workspaces',
      body: {'name': name, 'path': path},
    );
    final ws = data['workspace'];
    if (ws is! Map<String, dynamic>) {
      throw AppException('创建工作区失败：响应格式错误');
    }
    return WorkspaceModel.fromJson(ws);
  }

  /// 删除工作区（仅移除记录，不删除本地文件——由后端保证）
  Future<void> deleteWorkspace(String id) async {
    await _backend.delete('/api/workspaces/$id');
  }
}
