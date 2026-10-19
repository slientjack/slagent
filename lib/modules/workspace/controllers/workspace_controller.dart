import 'package:get/get.dart';

import '../../../../data/models/workspace_model.dart';
import '../../../../data/repositories/workspace_repository.dart';

/// 工作区控制器：列表管理、当前选中、增删切换
class WorkspaceController extends GetxController {
  WorkspaceController({required WorkspaceRepository repository})
      : _repository = repository;

  final WorkspaceRepository _repository;

  /// 工作区列表
  final RxList<WorkspaceModel> workspaces = <WorkspaceModel>[].obs;

  /// 当前选中工作区
  final Rxn<WorkspaceModel> currentWorkspace = Rxn<WorkspaceModel>();

  /// 列表加载中
  final RxBool isLoading = false.obs;

  /// 操作错误信息（用于 SnackBar / 对话框提示）
  final RxnString errorMessage = RxnString();

  @override
  void onInit() {
    super.onInit();
    // 先加载本地缓存，用于启动时先行渲染
    _loadCache();
  }

  /// 加载本地缓存（失败静默忽略）
  Future<void> _loadCache() async {
    final cached = await _repository.loadCached();
    if (cached.isNotEmpty && workspaces.isEmpty) {
      workspaces.assignAll(cached);
    }
  }

  /// 从后端拉取工作区列表
  Future<void> fetchWorkspaces() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final list = await _repository.fetchWorkspaces();
      workspaces.assignAll(list);
      // 若当前选中已被删除或尚未选中，则默认选中第一个
      if (currentWorkspace.value == null ||
          !list.any((e) => e.id == currentWorkspace.value!.id)) {
        currentWorkspace.value = list.isNotEmpty ? list.first : null;
      }
    } catch (e) {
      errorMessage.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  /// 创建工作区
  Future<bool> createWorkspace({
    required String name,
    required String path,
  }) async {
    errorMessage.value = null;
    try {
      final ws = await _repository.createWorkspace(name: name, path: path);
      workspaces.add(ws);
      currentWorkspace.value = ws;
      return true;
    } catch (e) {
      errorMessage.value = e.toString();
      return false;
    }
  }

  /// 删除工作区（仅移除记录，不删除本地文件）
  Future<bool> deleteWorkspace(String id) async {
    errorMessage.value = null;
    try {
      await _repository.deleteWorkspace(id);
      workspaces.removeWhere((e) => e.id == id);
      // 若删除的是当前选中，切到剩余的第一个（或空）
      if (currentWorkspace.value?.id == id) {
        currentWorkspace.value =
            workspaces.isNotEmpty ? workspaces.first : null;
      }
      return true;
    } catch (e) {
      errorMessage.value = e.toString();
      return false;
    }
  }

  /// 切换当前工作区
  void selectWorkspace(WorkspaceModel workspace) {
    currentWorkspace.value = workspace;
  }
}
