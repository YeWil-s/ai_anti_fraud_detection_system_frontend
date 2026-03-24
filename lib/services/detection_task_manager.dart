import 'dart:async';
import 'package:flutter/material.dart';

/// 检测任务类型
enum DetectionTaskType {
  audio,    // 音频检测
  video,    // 视频检测
  text,     // 文本检测
  screenshot, // 截图OCR检测
}

/// 通话环境类型
enum CallEnvironment {
  textChat,    // 纯文字聊天（QQ/微信文字）
  voiceChat,   // 语音聊天（QQ/微信语音）
  phoneCall,   // 电话通话
  videoCall,   // 视频通话
  unknown,     // 未知环境
}

/// 检测任务配置
class DetectionTaskConfig {
  final DetectionTaskType type;
  final bool enabled;
  final Duration interval;
  final Map<String, dynamic> params;

  DetectionTaskConfig({
    required this.type,
    this.enabled = true,
    required this.interval,
    this.params = const {},
  });
}

/// 环境信息
class EnvironmentInfo {
  final CallEnvironment environment;
  final String platform;           // wechat/qq/phone/video_call/other
  final String description;
  final List<DetectionTaskType> activeTasks;
  final Map<String, double> weights;
  final bool isTextChat;
  final Map<String, dynamic>? chatSpeakers;  // 聊天双方信息

  EnvironmentInfo({
    required this.environment,
    required this.platform,
    required this.description,
    required this.activeTasks,
    required this.weights,
    this.isTextChat = false,
    this.chatSpeakers,
  });

  factory EnvironmentInfo.fromJson(Map<String, dynamic> json) {
    final envType = json['environment_type'] ?? 'unknown';
    final platform = json['platform'] ?? 'unknown';
    
    // 解析环境类型
    CallEnvironment env;
    switch (envType) {
      case 'text_chat':
        env = CallEnvironment.textChat;
        break;
      case 'voice_chat':
        env = CallEnvironment.voiceChat;
        break;
      case 'phone_call':
        env = CallEnvironment.phoneCall;
        break;
      case 'video_call':
        env = CallEnvironment.videoCall;
        break;
      default:
        env = CallEnvironment.unknown;
    }
    
    // 解析启用的检测模态
    final activeModalities = json['active_modalities'] as List<dynamic>? ?? [];
    final activeTasks = activeModalities.map((m) {
      switch (m) {
        case 'text':
          return DetectionTaskType.text;
        case 'audio':
          return DetectionTaskType.audio;
        case 'vision':
        case 'video':
          return DetectionTaskType.video;
        default:
          return DetectionTaskType.screenshot;
      }
    }).toList();
    
    // 解析权重
    final weightsMap = json['weights'] as Map<String, dynamic>? ?? {};
    final weights = weightsMap.map((k, v) => MapEntry(k, (v as num).toDouble()));
    
    return EnvironmentInfo(
      environment: env,
      platform: platform,
      description: json['description'] ?? '未知环境',
      activeTasks: activeTasks,
      weights: weights,
      isTextChat: json['is_text_chat'] ?? false,
      chatSpeakers: json['chat_speakers'],
    );
  }
}

/// 检测任务状态
class TaskState {
  final DetectionTaskType type;
  bool isRunning;
  DateTime? lastRunTime;
  dynamic lastResult;
  String? error;

  TaskState({
    required this.type,
    this.isRunning = false,
    this.lastRunTime,
    this.lastResult,
    this.error,
  });
}

/// 检测任务管理器
/// 
/// 功能：
/// 1. 根据通话环境动态管理检测任务
/// 2. 启动/停止特定检测任务
/// 3. 监听环境变化自动调整任务
class DetectionTaskManager extends ChangeNotifier {
  static final DetectionTaskManager _instance = DetectionTaskManager._internal();
  factory DetectionTaskManager() => _instance;
  DetectionTaskManager._internal();

  // 当前环境信息
  EnvironmentInfo? _currentEnvironment;
  EnvironmentInfo? get currentEnvironment => _currentEnvironment;

  // 任务状态映射
  final Map<DetectionTaskType, TaskState> _taskStates = {};
  Map<DetectionTaskType, TaskState> get taskStates => Map.unmodifiable(_taskStates);

  // 任务定时器
  final Map<DetectionTaskType, Timer> _timers = {};

  // 任务配置
  final Map<CallEnvironment, List<DetectionTaskConfig>> _environmentConfigs = {
    // 纯文字聊天：只启用截图OCR文本检测
    CallEnvironment.textChat: [
      DetectionTaskConfig(
        type: DetectionTaskType.screenshot,
        enabled: true,
        interval: Duration(seconds: 3), // 每3秒截图一次
      ),
      DetectionTaskConfig(
        type: DetectionTaskType.text,
        enabled: true,
        interval: Duration(seconds: 2),
      ),
    ],
    
    // 语音聊天：音频 + 文本
    CallEnvironment.voiceChat: [
      DetectionTaskConfig(
        type: DetectionTaskType.audio,
        enabled: true,
        interval: Duration(seconds: 2),
      ),
      DetectionTaskConfig(
        type: DetectionTaskType.text,
        enabled: true,
        interval: Duration(seconds: 3),
      ),
      DetectionTaskConfig(
        type: DetectionTaskType.screenshot,
        enabled: true,
        interval: Duration(seconds: 5),
      ),
    ],
    
    // 电话通话：音频 + 文本
    CallEnvironment.phoneCall: [
      DetectionTaskConfig(
        type: DetectionTaskType.audio,
        enabled: true,
        interval: Duration(seconds: 2),
      ),
      DetectionTaskConfig(
        type: DetectionTaskType.text,
        enabled: true,
        interval: Duration(seconds: 3),
      ),
    ],
    
    // 视频通话：三模态
    CallEnvironment.videoCall: [
      DetectionTaskConfig(
        type: DetectionTaskType.audio,
        enabled: true,
        interval: Duration(seconds: 2),
      ),
      DetectionTaskConfig(
        type: DetectionTaskType.video,
        enabled: true,
        interval: Duration(seconds: 2),
      ),
      DetectionTaskConfig(
        type: DetectionTaskType.text,
        enabled: true,
        interval: Duration(seconds: 3),
      ),
      DetectionTaskConfig(
        type: DetectionTaskType.screenshot,
        enabled: true,
        interval: Duration(seconds: 5),
      ),
    ],
    
    // 未知环境：启用所有检测
    CallEnvironment.unknown: [
      DetectionTaskConfig(
        type: DetectionTaskType.audio,
        enabled: true,
        interval: Duration(seconds: 2),
      ),
      DetectionTaskConfig(
        type: DetectionTaskType.video,
        enabled: true,
        interval: Duration(seconds: 2),
      ),
      DetectionTaskConfig(
        type: DetectionTaskType.text,
        enabled: true,
        interval: Duration(seconds: 3),
      ),
      DetectionTaskConfig(
        type: DetectionTaskType.screenshot,
        enabled: true,
        interval: Duration(seconds: 3),
      ),
    ],
  };

  // 任务执行回调
  final Map<DetectionTaskType, Function> _taskCallbacks = {};

  /// 设置任务执行回调
  void setTaskCallback(DetectionTaskType type, Function callback) {
    _taskCallbacks[type] = callback;
  }

  /// 更新环境并自动调整任务
  void updateEnvironment(EnvironmentInfo environment) {
    print('🌍 [任务管理器] 环境更新: ${environment.description}');
    print('   平台: ${environment.platform}');
    print('   启用的任务: ${environment.activeTasks.map((t) => t.name).join(", ")}');
    print('   权重: ${environment.weights}');
    
    final oldEnvironment = _currentEnvironment;
    _currentEnvironment = environment;
    
    // 如果环境发生变化，重新配置任务
    if (oldEnvironment?.environment != environment.environment) {
      _reconfigureTasks(environment);
    }
    
    notifyListeners();
  }

  /// 重新配置检测任务
  void _reconfigureTasks(EnvironmentInfo environment) {
    print('🔧 [任务管理器] 重新配置任务...');
    
    // 停止所有当前任务
    stopAllTasks();
    
    // 获取新环境的任务配置
    final configs = _environmentConfigs[environment.environment] ?? 
                    _environmentConfigs[CallEnvironment.unknown]!;
    
    // 根据环境启用的模态过滤任务
    for (final config in configs) {
      // 检查该任务类型是否在环境启用的模态中
      final shouldEnable = environment.activeTasks.contains(config.type);
      
      if (shouldEnable && config.enabled) {
        _startTask(config);
      } else {
        print('   ⏹️ ${config.type.name} 任务被禁用');
      }
    }
    
    print('✅ [任务管理器] 任务配置完成');
  }

  /// 启动单个任务
  void _startTask(DetectionTaskConfig config) {
    print('   ▶️ 启动 ${config.type.name} 任务，间隔: ${config.interval.inSeconds}秒');
    
    // 初始化任务状态
    _taskStates[config.type] = TaskState(type: config.type, isRunning: true);
    
    // 创建定时器
    _timers[config.type] = Timer.periodic(config.interval, (_) {
      _executeTask(config.type);
    });
    
    // 立即执行一次
    _executeTask(config.type);
  }

  /// 执行检测任务
  void _executeTask(DetectionTaskType type) {
    final callback = _taskCallbacks[type];
    if (callback != null) {
      try {
        callback();
        _taskStates[type]?.lastRunTime = DateTime.now();
        _taskStates[type]?.error = null;
      } catch (e) {
        print('❌ [任务管理器] ${type.name} 任务执行失败: $e');
        _taskStates[type]?.error = e.toString();
      }
    }
  }

  /// 停止指定任务
  void stopTask(DetectionTaskType type) {
    print('⏹️ [任务管理器] 停止 ${type.name} 任务');
    _timers[type]?.cancel();
    _timers.remove(type);
    _taskStates[type]?.isRunning = false;
    notifyListeners();
  }

  /// 停止所有任务
  void stopAllTasks() {
    print('⏹️ [任务管理器] 停止所有任务');
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    
    for (final state in _taskStates.values) {
      state.isRunning = false;
    }
    notifyListeners();
  }

  /// 手动启动特定任务（用于调试或特殊场景）
  void startTask(DetectionTaskType type, {Duration? interval}) {
    if (_timers.containsKey(type)) {
      print('⚠️ [任务管理器] ${type.name} 任务已在运行');
      return;
    }
    
    final config = DetectionTaskConfig(
      type: type,
      enabled: true,
      interval: interval ?? Duration(seconds: 2),
    );
    
    _startTask(config);
    notifyListeners();
  }

  /// 获取任务状态
  TaskState? getTaskState(DetectionTaskType type) {
    return _taskStates[type];
  }

  /// 检查任务是否运行中
  bool isTaskRunning(DetectionTaskType type) {
    return _taskStates[type]?.isRunning ?? false;
  }

  /// 获取环境描述
  String getEnvironmentDescription() {
    return _currentEnvironment?.description ?? '未知环境';
  }

  /// 获取平台图标
  IconData getPlatformIcon() {
    final platform = _currentEnvironment?.platform ?? 'unknown';
    switch (platform) {
      case 'wechat':
        return Icons.chat;
      case 'qq':
        return Icons.chat_bubble;
      case 'phone':
        return Icons.phone;
      case 'video_call':
        return Icons.video_call;
      default:
        return Icons.device_unknown;
    }
  }

  /// 获取平台颜色
  Color getPlatformColor() {
    final platform = _currentEnvironment?.platform ?? 'unknown';
    switch (platform) {
      case 'wechat':
        return Color(0xFF07C160); // 微信绿
      case 'qq':
        return Color(0xFF12B7F5); // QQ蓝
      case 'phone':
        return Color(0xFF2196F3); // 电话蓝
      case 'video_call':
        return Color(0xFF9C27B0); // 视频紫
      default:
        return Colors.grey;
    }
  }

  /// 清理资源
  void dispose() {
    stopAllTasks();
    super.dispose();
  }
}
