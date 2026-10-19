/// 工作区输入校验工具
class Validators {
  Validators._();

  /// 工作区名称中不允许出现的字符：路径分隔符与常见非法字符
  static final RegExp _illegalChars = RegExp(r'[\\/:*?"<>|]');

  /// 校验工作区名称：非空（去首尾空白后）、长度不超过 50、不含非法字符
  /// 返回 null 表示校验通过，否则返回中文错误提示
  static String? validateWorkspaceName(String? name) {
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) {
      return '名称不能为空';
    }
    if (trimmed.length > 50) {
      return '名称长度不能超过 50 个字符';
    }
    if (_illegalChars.hasMatch(trimmed)) {
      return '名称不能包含 \\ / : * ? " < > | 等非法字符';
    }
    return null;
  }

  /// 校验工作区路径：非空、绝对路径
  /// 返回 null 表示校验通过，否则返回中文错误提示
  static String? validateWorkspacePath(String? path) {
    final trimmed = (path ?? '').trim();
    if (trimmed.isEmpty) {
      return '路径不能为空';
    }
    if (!trimmed.startsWith('/') && !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
      return '请输入有效的绝对路径';
    }
    return null;
  }
}
