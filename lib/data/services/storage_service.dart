import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/utils/logger.dart';

/// 本地 JSON 缓存服务：缓存工作区列表，用于启动时先行渲染
class StorageService {
  static const String _workspacesFile = 'workspaces_cache.json';

  /// 获取缓存文件（应用支持目录）
  Future<File> _cacheFile(String fileName) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  /// 读取工作区列表缓存，失败返回 null
  Future<List<Map<String, dynamic>>?> loadWorkspaces() async {
    try {
      final file = await _cacheFile(_workspacesFile);
      if (!file.existsSync()) return null;
      final text = await file.readAsString();
      final data = jsonDecode(text);
      if (data is List) {
        return data.whereType<Map<String, dynamic>>().toList();
      }
      return null;
    } catch (e) {
      Logger.w('读取工作区缓存失败: $e');
      return null;
    }
  }

  /// 写入工作区列表缓存
  Future<void> saveWorkspaces(List<Map<String, dynamic>> workspaces) async {
    try {
      final file = await _cacheFile(_workspacesFile);
      await file.writeAsString(jsonEncode(workspaces));
    } catch (e) {
      Logger.w('写入工作区缓存失败: $e');
    }
  }
}
