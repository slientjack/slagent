import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';

import '../../core/constants/api_constants.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/logger.dart';

/// 后端进程状态
enum ProcessManagerStatus {
  /// 未启动
  idle,

  /// 启动中（等待 AGENT_SERVER_READY）
  starting,

  /// 就绪（端口可用且健康检查通过）
  ready,

  /// 错误（超时/退出/找不到后端）
  error,
}

/// 后端进程管理器：负责解析启动命令、拉起子进程、等待就绪、健康检查与生命周期
class ProcessManager extends GetxService {
  /// 当前状态
  final Rx<ProcessManagerStatus> status = ProcessManagerStatus.idle.obs;

  /// 后端服务端口（就绪后有效）
  final Rxn<int> port = Rxn<int>();

  /// 错误信息（状态为 error 时有效）
  final Rxn<String> errorMessage = Rxn<String>();

  Process? _process;

  StreamSubscription<String>? _stdoutSub;

  StreamSubscription<String>? _stderrSub;

  Completer<int>? _readyCompleter;

  Timer? _startupTimer;

  bool _disposed = false;

  /// 启动后端：解析命令 → 拉起进程 → 等待就绪 → 健康检查
  Future<void> start() async {
    if (_disposed) return;
    if (status.value == ProcessManagerStatus.starting ||
        status.value == ProcessManagerStatus.ready) {
      return;
    }
    status.value = ProcessManagerStatus.starting;
    errorMessage.value = null;
    port.value = null;

    try {
      final command = _resolveBackendCommand();
      if (command == null) {
        throw StateError('未找到后端服务');
      }

      final readyPort = await _spawnAndWait(command);
      await _healthCheck(readyPort);

      port.value = readyPort;
      status.value = ProcessManagerStatus.ready;
      Logger.i('后端服务就绪，端口 $readyPort');
    } catch (e) {
      await _killProcess();
      status.value = ProcessManagerStatus.error;
      errorMessage.value = e.toString().replaceFirst('StateError: ', '');
      Logger.e('后端启动失败', e);
    }
  }

  /// 重启服务（进程意外退出后由 UI 触发）
  Future<void> restart() async {
    await _killProcess();
    status.value = ProcessManagerStatus.idle;
    await start();
  }

  /// 解析可用的 Python 解释器（尽量返回绝对路径，不依赖 PATH）。
  ///
  /// GUI 环境下（Finder/Launch Services 启动）PATH 仅含系统目录，
  /// `python3` 会解析到没有第三方库的系统 Python，因此按优先级探测：
  /// 1. python.org 官方安装（/Library/Frameworks，版本号最高者优先）
  /// 2. Homebrew（Apple Silicon: /opt/homebrew，Intel: /usr/local）
  /// 3. PATH 中的 python3 / Windows 的 python（终端启动时有效）
  String _resolvePythonExecutable() {
    if (Platform.isWindows) {
      // Windows：约定 Python 在 PATH 中（python.exe），python3.exe 不一定存在
      return 'python';
    }
    // macOS：按安装位置优先级探测
    final candidates = <String>[
      ..._frameworkPythonCandidates(),
      '/opt/homebrew/bin/python3',
      '/usr/local/bin/python3',
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        Logger.i('使用 Python 解释器: $candidate');
        return candidate;
      }
    }
    // 兜底：PATH 查找（从终端直接运行时有效）
    return 'python3';
  }

  /// 探测 python.org 官方安装的所有 Python 版本（版本号降序）。
  List<String> _frameworkPythonCandidates() {
    final versionsRoot =
        Directory('/Library/Frameworks/Python.framework/Versions');
    if (!versionsRoot.existsSync()) return const [];
    try {
      final versions = versionsRoot
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split(Platform.pathSeparator).last)
          .where((v) => RegExp(r'^\d+(\.\d+)+$').hasMatch(v))
          .toList()
        ..sort((a, b) => _compareVersions(b, a)); // 降序：新版本优先
      return [
        for (final v in versions)
          '/Library/Frameworks/Python.framework/Versions/$v/bin/python3'
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 数值化比较语义化版本字符串（如 "3.9" vs "3.14"，避免字典序误判）
  int _compareVersions(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  /// 解析后端启动命令，返回 (可执行文件, 参数列表, 工作目录)
  /// 顺序：环境变量 → 开发模式 → 打包模式
  ({String executable, List<String> arguments, String workingDirectory})?
      _resolveBackendCommand() {
    // 1) 环境变量指定完整命令
    final envCmd = Platform.environment[AppConstants.backendCmdEnv];
    if (envCmd != null && envCmd.trim().isNotEmpty) {
      final parts =
          envCmd.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        Logger.i('使用环境变量后端命令: $envCmd');
        return (
          executable: parts.first,
          arguments: parts.sublist(1),
          workingDirectory: Directory.current.path,
        );
      }
    }

    // 2) 开发模式：当前工作目录下存在 python_backend/main.py
    //    （注意：沙箱环境下 cwd 会被重置，此分支仅非沙箱/终端运行时生效）
    final devEntry = File(
        '${Directory.current.path}${Platform.pathSeparator}python_backend${Platform.pathSeparator}main.py');
    if (devEntry.existsSync()) {
      final workingDir = devEntry.parent.path;
      Logger.i('开发模式启动后端: ${_resolvePythonExecutable()} main.py ($workingDir)');
      return (
        executable: _resolvePythonExecutable(),
        arguments: ['main.py'],
        workingDirectory: workingDir,
      );
    }

    // 3) 打包/开发构建模式：从可执行文件所在目录向上探测 python_backend。
    //    每级目录同时探测两个位置：
    //    - {dir}/python_backend/ —— Windows 安装目录 / 仓库根目录（开发构建）
    //    - {dir}/Resources/python_backend/ —— macOS .app bundle 内的标准资源位置
    //    深度取 12：覆盖调试构建 .app/Contents/MacOS → 仓库根目录共 8 级、
    //    以及发布包 .app 放在任意子目录下的场景。
    final executableName = Platform.isWindows
        ? 'ai_agent_backend.exe'
        : 'ai_agent_backend';
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 12; i++) {
      for (final sub in <String>['python_backend', 'Resources/python_backend']) {
        final backendDir = Directory(
            '${dir.path}${Platform.pathSeparator}${sub.replaceAll('/', Platform.pathSeparator)}');
        // 优先探测打包好的后端可执行文件
        final backendExe = File(
            '${backendDir.path}${Platform.pathSeparator}$executableName');
        if (backendExe.existsSync()) {
          Logger.i('打包模式启动后端可执行文件: ${backendExe.path}');
          return (
            executable: backendExe.path,
            arguments: const [],
            workingDirectory: backendDir.path,
          );
        }
        // 其次探测 main.py（源码运行，用解析出的 Python 解释器）
        final backendMain = File(
            '${backendDir.path}${Platform.pathSeparator}main.py');
        if (backendMain.existsSync()) {
          Logger.i('打包模式启动后端脚本: python main.py (${backendMain.parent.path})');
          return (
            executable: _resolvePythonExecutable(),
            arguments: ['main.py'],
            workingDirectory: backendMain.parent.path,
          );
        }
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }

    Logger.w('未找到后端服务（已探测: ${File(Platform.resolvedExecutable).parent.path} 及其上级目录）');
    return null;
  }

  /// 拉起子进程并等待 AGENT_SERVER_READY 行，返回端口
  Future<int> _spawnAndWait(
      ({String executable, List<String> arguments, String workingDirectory})
          command) {
    _readyCompleter = Completer<int>();

    return Process.start(
      command.executable,
      command.arguments,
      workingDirectory: command.workingDirectory,
      environment: {
        ...Platform.environment,
        // 关闭 Python 输出缓冲，保证 stdout 实时输出
        'PYTHONUNBUFFERED': '1',
      },
    ).then((process) async {
      _process = process;

      // 总超时 30 秒
      _startupTimer = Timer(AppConstants.backendStartupTimeout, () {
        if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
          _readyCompleter!
              .completeError(StateError('后端服务启动超时（30 秒），请检查后端程序'));
        }
      });

      // 监听 stdout 行流，捕获就绪标记
      _stdoutSub = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          Logger.d('[后端 stdout] $line');
          final match = AppConstants.serverReadyPattern.firstMatch(line);
          if (match != null && _readyCompleter != null && !_readyCompleter!.isCompleted) {
            final port = int.tryParse(match.group(1) ?? '');
            if (port != null) {
              _startupTimer?.cancel();
              _readyCompleter!.complete(port);
            }
          }
        },
        onDone: _onProcessExit,
        onError: (Object e) {
          if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
            _readyCompleter!.completeError(StateError('后端输出流异常: $e'));
          }
        },
      );

      // 监听 stderr，记录日志辅助排查
      _stderrSub = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        Logger.w('[后端 stderr] $line');
      });

      // 进程退出码监听
      process.exitCode.then((code) {
        Logger.w('后端进程退出，退出码 $code');
        _onProcessExit();
      });

      return _readyCompleter!.future;
    });
  }

  /// 进程退出处理：若尚未就绪则报错；若已就绪则切换到错误状态（意外退出）
  void _onProcessExit() {
    _startupTimer?.cancel();
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(StateError('后端进程启动过程中意外退出'));
      return;
    }
    // 已就绪后进程退出 → 意外退出，UI 显示错误 + 重启按钮
    if (status.value == ProcessManagerStatus.ready && !_disposed) {
      status.value = ProcessManagerStatus.error;
      errorMessage.value = '后端服务已意外退出，请重启服务';
      port.value = null;
      Logger.e('后端进程意外退出');
    }
  }

  /// 健康检查：最多 5 次，间隔 500ms
  Future<void> _healthCheck(int port) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      for (var i = 0; i < ApiConstants.healthCheckRetries; i++) {
        try {
          final request =
              await client.getUrl(Uri(scheme: 'http', host: ApiConstants.localHost, port: port, path: ApiConstants.health));
          final response = await request.close();
          if (response.statusCode == 200) {
            Logger.i('健康检查通过（第 ${i + 1} 次尝试）');
            return;
          }
        } catch (_) {
          // 连接失败继续重试
        }
        if (i < ApiConstants.healthCheckRetries - 1) {
          await Future<void>.delayed(ApiConstants.healthCheckInterval);
        }
      }
      throw StateError('后端服务健康检查失败，请重启服务');
    } finally {
      client.close(force: true);
    }
  }

  /// 杀掉子进程并清理订阅
  Future<void> _killProcess() async {
    _startupTimer?.cancel();
    _startupTimer = null;
    await _stdoutSub?.cancel();
    _stdoutSub = null;
    await _stderrSub?.cancel();
    _stderrSub = null;
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        process.kill();
      } catch (_) {
        // 进程可能已退出
      }
    }
    port.value = null;
  }

  /// 应用退出时调用：保证 Get.delete 时杀进程
  @override
  void onClose() {
    _disposed = true;
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.completeError(StateError('应用退出，取消等待后端'));
    }
    _killProcess();
    status.value = ProcessManagerStatus.idle;
    super.onClose();
  }
}
