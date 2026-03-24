import 'package:flutter/material.dart';
import 'package:ai_anti_fraud_detection_system_frontend/contants/theme.dart';
import 'package:ai_anti_fraud_detection_system_frontend/contants/index.dart';
import 'package:ai_anti_fraud_detection_system_frontend/utils/PermissionManager.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/RealTimeDetectionService.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/detection_task_manager.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/family_alert_manager.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/auth_service.dart';
import 'package:ai_anti_fraud_detection_system_frontend/components/environment_indicator.dart';
import 'package:ai_anti_fraud_detection_system_frontend/components/detection_floating_widget.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:get/get.dart';
import 'package:action_slider/action_slider.dart';
import 'package:step_progress_indicator/step_progress_indicator.dart';
import 'package:dio/dio.dart';
import 'dart:math' as math;

class DetectionPage extends StatefulWidget {
  const DetectionPage({super.key});

  @override
  State<DetectionPage> createState() => _DetectionPageState();
}

// 监测状态枚举
enum DetectionState {
  idle,        // 空闲
  preparing,   // 准备中
  connecting,  // 连接中
  monitoring,  // 监测中
  warning,     // 警告中
  stopping,    // 停止中
  error,       // 错误
}

// 风险等级枚举
enum RiskLevel {
  safe,      // 安全
  low,       // 低风险
  medium,    // 中风险
  high,      // 高风险
  critical,  // 严重风险
}

class _DetectionPageState extends State<DetectionPage> with TickerProviderStateMixin {
  // 当前状态
  DetectionState _currentState = DetectionState.idle;
  
  // 检测结果
  double _audioConfidence = 0.0;
  bool _audioIsFake = false;
  double _videoConfidence = 0.0;
  bool _videoIsDeepfake = false;
  String _textRiskLevel = 'safe';
  double _textConfidence = 0.0;  // ✅ 新增：保存文本检测的实际置信度
  List<String> _textKeywords = [];
  
  // 综合风险等级
  RiskLevel _overallRisk = RiskLevel.safe;
  
  // ✅ 三级防御机制
  int _currentDefenseLevel = 1;  // 当前防御等级（1/2/3）
  
  // 连接状态
  bool _isConnected = false;
  String _statusMessage = '点击开始按钮启动实时监测';
  
  // ✅ 用户意图标志：只有用户主动滑动开关才能改变检测状态
  bool _isUserStopping = false;  // 正在执行用户主动停止流程
  
  // 实时检测服务
  final RealTimeDetectionService _detectionService = RealTimeDetectionService();
  
  // ✅ 检测任务管理器（环境感知）
  final DetectionTaskManager _taskManager = DetectionTaskManager();
  
  // ✅ 常驻悬浮窗管理器
  final DetectionFloatingManager _floatingManager = DetectionFloatingManager();
  
  // ✅ 当前通话环境
  String _currentEnvironment = 'unknown';
  String _currentPlatform = 'unknown';
  List<Map<String, dynamic>> _chatSpeakers = [];
  List<String> _enabledModalities = [];
  
  // 真实音频波形数据
  List<double> _realAudioWaveform = List.filled(50, 0.0);
  
  // 动画控制器
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // 初始化脉冲动画（用于监测中的指示器）
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // 初始化波形动画
    _waveController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    
    // 设置检测服务回调
    _setupDetectionServiceCallbacks();
    
    // ✅ 添加前台服务监听
    _initForegroundTask();
    
    // ✅ 初始化家庭预警管理器（连接 WebSocket）
    _initFamilyAlertManager();
  }
  
  /// ✅ 初始化家庭预警管理器
  void _initFamilyAlertManager() {
    final familyAlertManager = FamilyAlertManager();
    familyAlertManager.initialize(_detectionService);
    print('✅ DetectionPage: 家庭预警管理器已连接');
  }
  
  /// ✅ 更新常驻悬浮窗
  void _updateFloatingWidget() {
    final isMonitoring = _currentState == DetectionState.monitoring ||
                         _currentState == DetectionState.warning;
    
    if (isMonitoring && mounted) {
      _floatingManager.show(
        context,
        isMonitoring: true,
        defenseLevel: _currentDefenseLevel,
        callRecordId: _detectionService.callRecordId,
        onEmergencyTap: () {
          _triggerEmergencyAlert();
        },
        onExpandTap: () {
          print('悬浮窗展开');
        },
      );
    } else {
      _floatingManager.hide();
    }
  }
  
  /// ✅ 初始化前台服务监听
  void _initForegroundTask() {
    // 监听前台服务的数据
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }
  
  /// 处理前台服务数据
  void _onReceiveTaskData(dynamic data) {
    print('📨 收到前台服务数据: $data');
    
    if (data == 'stop_requested') {
      // 用户点击了通知栏的"停止监测"按钮
      _stopMonitoring();
    } else if (data == 'notification_pressed') {
      // 用户点击了通知
      // 可以在这里做一些 UI 更新
    }
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    // ✅ 不在 dispose 里停止检测服务：
    // 使用 IndexedStack 后 dispose 基本不会被调用（除非整个 MainPage 被销毁）
    // 即使被调用，检测服务应由用户主动滑动开关来停止，不应随页面生命周期自动停止
    // _detectionService.dispose() 已移除
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    super.dispose();
  }
  
  /// 设置检测服务回调
  void _setupDetectionServiceCallbacks() {
    // 检测结果回调（按照接口文档格式）
    _detectionService.onDetectionResult = (result) {
      if (mounted) {
        print('📊 收到检测结果: $result');
        
        setState(() {
          // 按照接口文档格式解析
          final detectionType = result['detection_type'] ?? '';
          final isRisk = result['is_risk'] ?? false;
          final confidence = (result['confidence'] ?? 0.0).toDouble();
          final message = result['message'] ?? '';
          
          // 根据检测类型更新对应的结果
          if (detectionType == '语音' || detectionType == 'audio') {
            _audioConfidence = confidence;
            _audioIsFake = isRisk;
            
            // 显示提示消息
            if (isRisk) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⚠️ 音频风险: $message'),
                  backgroundColor: AppColors.error,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          } else if (detectionType == '视频' || detectionType == 'video') {
            _videoConfidence = confidence;
            _videoIsDeepfake = isRisk;
            
            // 显示提示消息
            if (isRisk) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⚠️ 视频风险: $message'),
                  backgroundColor: AppColors.error,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          } else if (detectionType == '文本' || detectionType == 'text') {
            _textRiskLevel = isRisk ? 'high' : 'safe';
            _textConfidence = confidence;  // ✅ 保存实际置信度
            
            // ✅ 提取关键词
            final keywords = result['keywords'];
            if (keywords != null && keywords is List) {
              _textKeywords = List<String>.from(keywords);
            }
            
            // 显示提示消息
            if (isRisk) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⚠️ 文本风险: $message${_textKeywords.isNotEmpty ? "\n关键词: ${_textKeywords.join(", ")}" : ""}'),
                  backgroundColor: AppColors.error,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
          
          // 计算综合风险等级
          _overallRisk = _calculateOverallRisk();
          
          // 如果是高风险，切换到警告状态
          if (_overallRisk == RiskLevel.high || _overallRisk == RiskLevel.critical) {
            _currentState = DetectionState.warning;
          }
        });
      }
    };
    
    // 控制消息回调（防御升级等）
    _detectionService.onControlMessage = (control) {
      if (mounted) {
        print('🎮 收到控制消息: $control');
        
        final action = control['action'] ?? '';
        
        if (action == 'upgrade_level') {
          final targetLevel = control['target_level'] ?? 1;
          final reason = control['reason'] ?? '';
          final config = control['config'] ?? {};
          
          // ✅ 根据后端文档的 warning_mode 决定显示方式
          final warningMode = config['warning_mode'] ?? 'modal';
          final uiMessage = config['ui_message'] ?? '⚠️ 检测到风险，请提高警惕！';
          
          if (warningMode == 'fullscreen' || config['show_full_screen_warning'] == true) {
            // 全屏警告（Level 3）
            _showFullScreenWarning(uiMessage, targetLevel, reason, config);
          } else if (warningMode == 'modal') {
            // 弹窗警告（Level 2）
            _showModalWarning(uiMessage, targetLevel, reason, config);
          } else if (warningMode == 'toast') {
            // 轻量提示（Level 1）
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(uiMessage),
                backgroundColor: AppColors.warning,
                duration: Duration(seconds: 3),
              ),
            );
          }
          
          // 更新状态为警告
          setState(() {
            _currentState = DetectionState.warning;
          });
        }
      }
    };
    
    // ✅ 防御等级变化回调
    _detectionService.onDefenseLevelChanged = (level) {
      if (mounted) {
        setState(() {
          _currentDefenseLevel = level;
        });
        print('🛡️ UI 防御等级已更新: Level $level');
        
        // 更新悬浮窗
        _updateFloatingWidget();
      }
    };
    
    // ✅ 环境识别回调
    _detectionService.onEnvironmentDetected = (environmentData) {
      if (mounted) {
        _handleEnvironmentDetected(environmentData);
      }
    };
    
    // ACK 确认回调
    _detectionService.onAckReceived = (msgType, status) {
      // 可以在这里显示发送状态（可选）
      // print('✅ $msgType 已确认: $status');
    };
    
    // 新增：监听真实音频波形数据
    _detectionService.onAudioWaveformUpdate = (waveformData) {
      if (mounted) {
        setState(() {
          _realAudioWaveform = waveformData;
        });
      }
    };
    
    _detectionService.onStatusChange = (message) {
      if (mounted) {
        setState(() {
          _statusMessage = message;
        });
      }
    };
    
    _detectionService.onError = (error) {
      if (mounted) {
        // ✅ 不改变 _currentState：后台错误（如网络抖动、录音中断）
        // 只是弹出提示，不把 UI 强制切回"未检测"状态。
        // 只有 startDetection 返回 false 时才设置 error 状态。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ $error'),
            backgroundColor: Colors.orange[700],
            duration: Duration(seconds: 3),
          ),
        );
      }
    };
    
    _detectionService.onConnected = () {
      if (mounted) {
        setState(() {
          _isConnected = true;
        });
      }
    };
    
    _detectionService.onDisconnected = () {
      if (mounted) {
        setState(() {
          _isConnected = false;
          // ✅ 不自动改变 _currentState：
          // 前后台切换会导致 WebSocket 短暂断开，但服务仍在运行。
          // 只有用户主动滑动开关（_stopMonitoring）才能把状态改为 idle。
        });
      }
    };
  }
  
  // 开始监测
  Future<void> _startMonitoring() async {
    // 1. 检查权限
    final permissionManager = PermissionManager();
    await permissionManager.checkAllPermissions();
    
    if (!permissionManager.hasMicrophonePermission.value) {
      // 显示权限说明对话框
      final shouldRequest = await _showPermissionRequiredDialog();
      if (!shouldRequest) {
        return;
      }
      
      // 请求麦克风权限
      final granted = await permissionManager.requestMicrophonePermission(context);
      if (!granted) {
        _showPermissionDeniedDialog();
        return;
      }
    }
    
    // 2. 更新状态为准备中
    setState(() {
      _currentState = DetectionState.preparing;
      _statusMessage = '正在准备...';
    });
    
    // 3. 延迟一下，显示准备状态
    await Future.delayed(Duration(milliseconds: 500));
    
    // 4. 更新状态为连接中
    if (mounted) {
      setState(() {
        _currentState = DetectionState.connecting;
        _statusMessage = '正在连接服务器...';
      });
    }
    
    // 5. 启动检测服务
    final success = await _detectionService.startDetection();
    
    if (success) {
      if (mounted) {
        setState(() {
          _currentState = DetectionState.monitoring;
          _statusMessage = '监测中...';
        });
        
        // ✅ 显示常驻悬浮窗
        _updateFloatingWidget();
        
        // ✅ 使用 ScaffoldMessenger 替代 Get.snackbar，避免 context 问题
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('实时监测已启动'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
        setState(() {
          _currentState = DetectionState.error;
          _statusMessage = '启动失败，请重试';
        });
      }
    }
  }
  
  // 停止监测（仅由用户主动触发）
  Future<void> _stopMonitoring() async {
    // ✅ 防止重复触发（如 warning 弹窗「立即挂断」和通知栏按钮同时触发）
    if (_isUserStopping) return;
    _isUserStopping = true;

    setState(() {
      _currentState = DetectionState.stopping;
      _statusMessage = '正在停止...';
    });
    
    // ✅ 获取最近的截图
    final screenshots = await _detectionService.getRecentScreenshots();
    
    await _detectionService.stopDetection();

    _isUserStopping = false; // ✅ 停止流程结束，重置标志
    
    if (mounted) {
      setState(() {
        _currentState = DetectionState.idle;
        _isConnected = false;
        _statusMessage = '已停止监测';
        _audioConfidence = 0.0;
        _videoConfidence = 0.0;
        _audioIsFake = false;
        _videoIsDeepfake = false;
        _textRiskLevel = 'safe';
        _textConfidence = 0.0;
        _textKeywords = [];
        _overallRisk = RiskLevel.safe;
        _currentDefenseLevel = 1; // ✅ 重置防御等级
        _currentEnvironment = 'unknown'; // ✅ 重置环境
        _currentPlatform = 'unknown';
        _chatSpeakers = [];
        _enabledModalities = [];
      });
      
      // ✅ 停止所有检测任务
      _taskManager.stopAllTasks();
      
      // ✅ 隐藏常驻悬浮窗
      _floatingManager.hide();
      
      // ✅ 展示截图
      if (screenshots.isNotEmpty) {
        _showScreenshotsDialog(screenshots);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('实时监测已停止'),
          backgroundColor: Colors.grey[700],
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
  
  /// 展示截图对话框
  void _showScreenshotsDialog(List<dynamic> screenshots) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.photo_library, color: Colors.blue),
            SizedBox(width: 8),
            Text('监测期间的截图'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: screenshots.length,
            itemBuilder: (context, index) {
              return Card(
                margin: EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        '截图 ${index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Image.memory(
                      screenshots[index],
                      fit: BoxFit.contain,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭'),
          ),
        ],
      ),
    );
  }
  
  /// 显示权限必需对话框
  Future<bool> _showPermissionRequiredDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 8),
            Text('需要权限'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '实时监测功能需要以下权限：',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.mic, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('麦克风权限 - 录制音频进行实时分析'),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.block, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '不授予权限将无法使用此功能',
                      style: TextStyle(
                        color: Colors.red[900],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text('授予权限'),
          ),
        ],
      ),
    ) ?? false;
  }
  
  /// 显示权限被拒绝对话框
  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('权限被拒绝'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('您拒绝了麦克风权限，无法使用实时监测功能。'),
            SizedBox(height: 12),
            Text(
              '您可以在以下位置重新授予权限：',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('• 我的 → 权限设置'),
            Text('• 系统设置 → 应用权限'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('知道了'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              PermissionManager().openSettings();
            },
            child: Text('前往设置'),
          ),
        ],
      ),
    );
  }
  
  /// 显示弹窗警告（Level 2）
  void _showModalWarning(String message, int level, String reason, Map<String, dynamic> config) {
    showDialog(
      context: context,
      barrierDismissible: true,  // 允许点击外部关闭
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          side: BorderSide(color: AppColors.warning, width: 3),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: AppColors.warning, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '⚠️ 风险警告',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeLarge,
                  fontWeight: FontWeight.bold,
                  color: AppColors.warning,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 防御等级
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.paddingMedium,
                vertical: AppTheme.paddingSmall,
              ),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Text(
                '防御等级: Level $level',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.bold,
                  color: AppColors.warning,
                ),
              ),
            ),
            
            SizedBox(height: AppTheme.paddingMedium),
            
            // 警告消息
            Text(
              message,
              style: TextStyle(
                fontSize: AppTheme.fontSizeMedium,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
            
            SizedBox(height: AppTheme.paddingSmall),
            
            // 原因
            Text(
              '原因: $reason',
              style: TextStyle(
                fontSize: AppTheme.fontSizeSmall,
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
            
            SizedBox(height: AppTheme.paddingMedium),
            
            // 提示信息
            Container(
              padding: EdgeInsets.all(AppTheme.paddingSmall),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已提高检测频率，已通知家人',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeSmall,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '继续通话',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _stopMonitoring();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            child: Text('立即挂断'),
          ),
        ],
      ),
    );
  }
  
  /// 显示全屏警告对话框（Level 3）
  void _showFullScreenWarning(String message, int level, String reason, Map<String, dynamic> config) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.error,
                AppColors.error.withOpacity(0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: AppColors.error.withOpacity(0.5),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          padding: EdgeInsets.all(AppTheme.paddingLarge * 1.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 警告图标（带动画）
              TweenAnimationBuilder(
                tween: Tween<double>(begin: 0.8, end: 1.2),
                duration: Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                builder: (context, double scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 80,
                    ),
                  );
                },
              ),
              
              SizedBox(height: AppTheme.paddingLarge),
              
              // 警告标题
              Text(
                '🚨 风险警告',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              
              SizedBox(height: AppTheme.paddingMedium),
              
              // 防御等级
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.paddingMedium,
                  vertical: AppTheme.paddingSmall,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  '防御等级: Level $level',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeLarge,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              
              SizedBox(height: AppTheme.paddingLarge),
              
              // 警告消息
              Container(
                padding: EdgeInsets.all(AppTheme.paddingMedium),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: Colors.white,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              SizedBox(height: AppTheme.paddingSmall),
              
              // 原因
              Text(
                '原因: $reason',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeSmall,
                  color: Colors.white.withOpacity(0.9),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              
              SizedBox(height: AppTheme.paddingMedium),
              
              // ✅ 额外提示信息
              Container(
                padding: EdgeInsets.all(AppTheme.paddingSmall),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: Colors.white.withOpacity(0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          '已通知家人',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeSmall,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fiber_manual_record, color: Colors.white, size: 16),
                        SizedBox(width: 8),
                        Text(
                          '正在录音保存证据',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeSmall,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: AppTheme.paddingLarge * 1.5),
              
              // 按钮
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        // 停止监测
                        _stopMonitoring();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.error,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                        ),
                      ),
                      child: Text(
                        '停止监测',
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeMedium,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: AppTheme.paddingMedium),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white, width: 2),
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                        ),
                      ),
                      child: Text(
                        '继续监测',
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeMedium,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // ✅ 解析环境字符串为枚举
  CallEnvironment _parseCallEnvironment(String environment) {
    switch (environment) {
      case 'text_chat':
        return CallEnvironment.textChat;
      case 'voice_chat':
        return CallEnvironment.voiceChat;
      case 'phone_call':
        return CallEnvironment.phoneCall;
      case 'video_call':
        return CallEnvironment.videoCall;
      default:
        return CallEnvironment.unknown;
    }
  }
  
  // ✅ 解析模态字符串列表为枚举列表
  List<DetectionTaskType> _parseModalities(List<String> modalities) {
    return modalities.map((m) {
      switch (m) {
        case 'text':
          return DetectionTaskType.text;
        case 'audio':
          return DetectionTaskType.audio;
        case 'vision':
        case 'video':
          return DetectionTaskType.video;
        case 'screenshot':
          return DetectionTaskType.screenshot;
        default:
          return DetectionTaskType.screenshot;
      }
    }).toList();
  }
  
  // ✅ 获取环境描述
  String _getEnvironmentDescription(String environment, String platform) {
    switch (environment) {
      case 'text_chat':
        return '$platform 文字聊天';
      case 'voice_chat':
        return '$platform 语音聊天';
      case 'phone_call':
        return '电话通话';
      case 'video_call':
        return '$platform 视频通话';
      default:
        return '未知环境';
    }
  }
  
  // ✅ 处理环境识别结果
  void _handleEnvironmentDetected(Map<String, dynamic> environmentData) {
    final environment = environmentData['environment'] ?? 'unknown';
    final platform = environmentData['platform'] ?? 'unknown';
    final speakers = List<Map<String, dynamic>>.from(environmentData['chat_speakers'] ?? []);
    final modalities = List<String>.from(environmentData['enabled_modalities'] ?? []);
    
    print('🌍 处理环境识别结果:');
    print('   环境: $environment');
    print('   平台: $platform');
    print('   聊天双方: $speakers');
    print('   启用模态: $modalities');
    
    setState(() {
      _currentEnvironment = environment;
      _currentPlatform = platform;
      _chatSpeakers = speakers;
      _enabledModalities = modalities;
    });
    
    // 根据环境更新检测任务
    _taskManager.updateEnvironment(
      EnvironmentInfo(
        environment: _parseCallEnvironment(environment),
        platform: platform,
        description: _getEnvironmentDescription(environment, platform),
        activeTasks: _parseModalities(modalities),
        weights: {},
        isTextChat: environment == 'text_chat',
        chatSpeakers: speakers.isNotEmpty ? {'speakers': speakers} : null,
      ),
    );
    
    // 显示环境识别提示
    _showEnvironmentNotification(environment, platform);
  }
  
  // ✅ 显示环境详情对话框
  void _showEnvironmentDetails() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('环境详情'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('环境类型', _getEnvironmentDescription(_currentEnvironment, _currentPlatform)),
            _buildDetailRow('平台', _currentPlatform),
            _buildDetailRow('启用模态', _enabledModalities.join(', ')),
            if (_chatSpeakers.isNotEmpty) ...[
              SizedBox(height: 12),
              Text(
                '聊天双方:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              ..._chatSpeakers.map((speaker) => Padding(
                padding: EdgeInsets.only(left: 16, bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      speaker['is_user'] == true ? Icons.person : Icons.person_outline,
                      size: 16,
                      color: speaker['is_user'] == true ? Colors.green : Colors.orange,
                    ),
                    SizedBox(width: 8),
                    Text(speaker['name'] ?? '未知'),
                    if (speaker['role'] != null)
                      Text(
                        ' (${speaker['role']})',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                  ],
                ),
              )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(value),
        ],
      ),
    );
  }
  
  // ✅ 显示环境识别提示
  void _showEnvironmentNotification(String environment, String platform) {
    String message;
    IconData icon;
    Color color;
    
    switch (environment) {
      case 'text_chat':
        message = '检测到文字聊天环境（$platform）';
        icon = Icons.chat_bubble_outline;
        color = Colors.blue;
        break;
      case 'voice_chat':
        message = '检测到语音聊天环境（$platform）';
        icon = Icons.mic;
        color = Colors.green;
        break;
      case 'phone_call':
        message = '检测到电话通话环境';
        icon = Icons.phone;
        color = Colors.orange;
        break;
      case 'video_call':
        message = '检测到视频通话环境（$platform）';
        icon = Icons.videocam;
        color = Colors.purple;
        break;
      default:
        message = '正在识别通话环境...';
        icon = Icons.help_outline;
        color = Colors.grey;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
  
  // 计算综合风险等级
  RiskLevel _calculateOverallRisk() {
    // 严重风险：音频或视频检测到伪造且置信度高
    if (_audioIsFake && _audioConfidence > 0.8) return RiskLevel.critical;
    if (_videoIsDeepfake && _videoConfidence > 0.8) return RiskLevel.critical;
    
    // 高风险：文本检测到高风险
    if (_textRiskLevel == 'high') return RiskLevel.high;
    
    // 中风险：音频或视频检测到伪造但置信度较低，或文本中等风险
    if (_audioIsFake || _videoIsDeepfake) return RiskLevel.medium;
    if (_textRiskLevel == 'medium') return RiskLevel.medium;
    
    // 低风险：有一些可疑迹象
    if (_textRiskLevel == 'low') return RiskLevel.low;
    
    // 安全
    return RiskLevel.safe;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - 50;
    
    return WithForegroundTask(
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          toolbarHeight: 50,
          automaticallyImplyLeading: false, // 移除左上角的返回按钮
          title: Padding(
            padding: EdgeInsets.only(left: 8),
            child: Text(
            '实时监测',
            style: TextStyle(
                color: Color(0xFF1F2937),
                fontSize: 18,
              fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('lib/UIimages/检测页背景.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  // ✅ 环境指示器（仅在检测到环境后显示）
                  if (_currentEnvironment != 'unknown')
                    EnvironmentIndicator(
                      environment: EnvironmentInfo(
                        environment: _parseCallEnvironment(_currentEnvironment),
                        platform: _currentPlatform,
                        description: _getEnvironmentDescription(_currentEnvironment, _currentPlatform),
                        activeTasks: _parseModalities(_enabledModalities),
                        weights: {},
                        isTextChat: _currentEnvironment == 'text_chat',
                        chatSpeakers: _chatSpeakers.isNotEmpty 
                            ? {'user': _chatSpeakers[0]['name'] ?? '我', 'other': _chatSpeakers.length > 1 ? _chatSpeakers[1]['name'] ?? '对方' : '对方'}
                            : null,
                      ),
                      onTap: () {
                        // 点击可查看详细环境信息
                        _showEnvironmentDetails();
                      },
                    ),
                  
                  if (_currentEnvironment != 'unknown')
                    SizedBox(height: 12),
                  
                  // 上部留白，让主卡片居中
                  Spacer(flex: 2),
                  
                  // 中间主卡片（ActionSlider + 两个矩形，自适应高度）
                  SizedBox(
                    height: 222,  // 固定高度：60(slider) + 12(spacing) + 150(containerA) = 222
                    child: _buildMainCardWithToggle(),
                  ),
                  
                  Spacer(flex: 1),
                  
                  // 两个并列矩形
                  Container(
                    height: screenHeight * 0.2,
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildLeftCard(),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: _buildRightCard(),
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: 16),
                  
                  // 底部矩形（音频波形）
                  Container(
                    height: screenHeight * 0.15,
                    child: _buildBottomCard(),
                  ),
                  
                  SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // 主卡片（ActionSlider + 两个矩形重新布局）
  Widget _buildMainCardWithToggle() {
    // ✅ warning 状态也属于「正在检测中」，开关应显示「滑动停止检测」
    final isMonitoring = _currentState == DetectionState.monitoring ||
                         _currentState == DetectionState.warning;
    final isProcessing = _currentState == DetectionState.preparing ||
                        _currentState == DetectionState.connecting ||
                        _currentState == DetectionState.stopping;
    
    // 尺寸定义
    const double sliderWidth = 200.0;
    const double sliderHeight = 60.0;
    const double cardRadius = 16.0;
    const double containerAHeight = 150.0;  // 矩形A固定高度（增大了30）
    const double containerBHeight = 50.0;   // 矩形B高度
    const double spacing = 12.0;  // 间距
    
    // 计算矩形A的top位置
    final double containerATop = sliderHeight + spacing;
    
    return Stack(
      children: [
        // ActionSlider（左上角）
        Positioned(
          top: 0,
          left: 0,
          child: Container(
            width: sliderWidth,
            height: sliderHeight,
      decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(sliderHeight / 2),
        boxShadow: [
          BoxShadow(
                  color: (isMonitoring ? Color(0xFFFF6B6B) : AppColors.primary).withOpacity(0.4),
                  blurRadius: 15,
            offset: Offset(0, 4),
          ),
        ],
      ),
            child: isProcessing
                ? Container(
                decoration: BoxDecoration(
                      color: AppColors.borderMedium,
                      borderRadius: BorderRadius.circular(sliderHeight / 2),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.textDark),
                        ),
                      ),
                    ),
                  )
                : ActionSlider.standard(
                    width: sliderWidth,
                    height: sliderHeight,
                    backgroundColor: isMonitoring 
                        ? Color(0xFFFF6B6B).withOpacity(0.3)
                        : AppColors.primary.withOpacity(0.3),
                    toggleColor: isMonitoring 
                        ? Color(0xFFFF6B6B)
                        : AppColors.primary,
                    action: (controller) async {
                      controller.loading();
                      if (isMonitoring) {
                        await _stopMonitoring();
                      } else {
                        await _startMonitoring();
                      }
                      controller.success();
                      await Future.delayed(Duration(milliseconds: 500));
                      controller.reset();
                    },
                    child: Text(
                      isMonitoring ? '滑动停止检测' : '滑动开始检测',
                style: TextStyle(
                        fontSize: 12,
                  fontWeight: FontWeight.bold,
                        color: AppColors.textDark,
                      ),
                    ),
                    icon: Icon(
                      isMonitoring ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      size: 24,
                      color: AppColors.textDark,
                ),
              ),
          ),
          ),
        
        // 矩形A（在ActionSlider下方，显示具体检测状态信息）
        Positioned(
          top: containerATop,
          left: 0,
          right: 0,
          child: Container(
            height: containerAHeight,
            decoration: BoxDecoration(
              color: Color(0xFF25282B),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(cardRadius),
                topRight: Radius.circular(0),  // 右上角无圆角，和B连接
                bottomLeft: Radius.circular(cardRadius),
                bottomRight: Radius.circular(cardRadius),
              ),
              // 根据防御等级显示不同的背景图片
              image: (_currentState == DetectionState.monitoring || _currentState == DetectionState.warning)
                  ? DecorationImage(
                      image: AssetImage(
                        _currentDefenseLevel == 1
                            ? 'lib/UIimages/检测状态-安全.png'
                            : _currentDefenseLevel == 2
                                ? 'lib/UIimages/检测状态-可疑.png'
                                : 'lib/UIimages/检测状态-危险.png',
                      ),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.left,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_currentState == DetectionState.monitoring || _currentState == DetectionState.warning) ...[
                    SizedBox(height: 12),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _currentDefenseLevel == 1 
                            ? AppColors.success.withOpacity(0.2)
                            : _currentDefenseLevel == 2
                                ? AppColors.warning.withOpacity(0.2)
                                : AppColors.error.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _currentDefenseLevel == 1 
                              ? AppColors.success
                              : _currentDefenseLevel == 2
                                  ? AppColors.warning
                                  : AppColors.error,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        'Level $_currentDefenseLevel',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _currentDefenseLevel == 1 
                              ? AppColors.success
                              : _currentDefenseLevel == 2
                                  ? AppColors.warning
                                  : AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        
        // 矩形B（在ActionSlider右侧，显示"检测状态"，下边和A的上边连接）
        Positioned(
          top: containerATop - containerBHeight,  // B的下边 = A的上边
          left: sliderWidth + spacing,
          right: 0,
      child: Container(
            height: containerBHeight,
        decoration: BoxDecoration(
              color: Color(0xFF25282B),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(cardRadius),
                topRight: Radius.circular(cardRadius),
                bottomLeft: Radius.circular(0),
                bottomRight: Radius.circular(0),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _isConnected ? AppColors.primary : AppColors.textLight,
                      shape: BoxShape.circle,
                      boxShadow: _isConnected ? [
            BoxShadow(
                          color: AppColors.primary.withOpacity(0.6),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ] : [],
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    '检测状态',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
      ),
          ),
        ),
      ],
    );
  }
  
  // 左侧卡片C（视频检测 - 带背景图片和环形进度条）
  Widget _buildLeftCard() {
    final confidence = _videoConfidence;
    final isActive = _currentState == DetectionState.monitoring ||
                     _currentState == DetectionState.warning;
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: DecorationImage(
          image: AssetImage('lib/UIimages/视频检测背景.png'),
          fit: BoxFit.cover,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: EdgeInsets.only(left: 8, right: 16, top: 12, bottom: 12),
          child: Row(
            children: [
              // 左侧：环形进度条（60%宽度）
              Expanded(
                flex: 60,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 根据可用高度动态调整进度条大小
                    final availableHeight = constraints.maxHeight;
                    final progressSize = math.min(availableHeight * 0.6, 70.0);
                    
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 环形进度条
                        SizedBox(
                          width: progressSize,
                          height: progressSize,
                          child: Stack(
                            children: [
                              // 圆形进度条 - 浅绿色系
                              CircularStepProgressIndicator(
                                totalSteps: 100,
                                currentStep: (confidence * 100).toInt(),
                                stepSize: 5,
                                selectedColor: Color(0xFF34D399),
                                unselectedColor: Colors.white.withOpacity(0.3),
                                padding: 0,
                                width: progressSize,
                                height: progressSize,
                                selectedStepSize: 6,
                                unselectedStepSize: 4,
                                roundedCap: (_, __) => true,
                                gradientColor: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFF6EE7B7), // 浅绿色
                                    Color(0xFF34D399), // 翠绿色
                                  ],
                                ),
                              ),
                              
                              // 中心内容 - 白色文字
                              Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
        children: [
                                    Icon(
                                      Icons.videocam,
                                      color: Colors.white,
                                      size: progressSize * 0.3,
                                    ),
                                    SizedBox(height: 2),
          Text(
                                      '${(confidence * 100).toStringAsFixed(0)}%',
            style: TextStyle(
                                        fontSize: progressSize * 0.22,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        SizedBox(height: 6),
                        
                        // 标签 - 白色，左对齐
                        Text(
                          '视频',
                          style: TextStyle(
                            fontSize: 13,
              fontWeight: FontWeight.w600,
                            color: Colors.white,
            ),
          ),
                        
                        SizedBox(height: 2),
                        
                        // 状态 - 白色，左对齐
          Text(
                          isActive ? '监测中' : '未监测',
            style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
            ),
          ),
        ],
                    );
                  },
                ),
              ),
              
              // 右侧：留白（40%宽度）
              Expanded(
                flex: 40,
                child: SizedBox(),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // 右侧卡片D（文本检测 - 带背景图片和环形进度条）
  Widget _buildRightCard() {
    final confidence = _textConfidence;
    final isActive = _currentState == DetectionState.monitoring ||
                     _currentState == DetectionState.warning;
    final hasKeywords = _textKeywords.isNotEmpty;
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: DecorationImage(
          image: AssetImage('lib/UIimages/文本检测背景.png'),
          fit: BoxFit.cover,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: EdgeInsets.only(left: 16, right: 8, top: 12, bottom: 12),
          child: Row(
            children: [
              // 左侧：留白（50%宽度）
              Expanded(
                flex: 50,
                child: SizedBox(),
              ),
              
              // 右侧：环形进度条（50%宽度）
              Expanded(
                flex: 50,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 根据可用高度动态调整进度条大小
                    final availableHeight = constraints.maxHeight;
                    final progressSize = math.min(availableHeight * 0.6, 70.0);
                    
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // 环形进度条
                        SizedBox(
                          width: progressSize,
                          height: progressSize,
                          child: Stack(
                            children: [
                              // 圆形进度条 - 墨绿色
                              CircularStepProgressIndicator(
                                totalSteps: 100,
                                currentStep: (confidence * 100).toInt(),
                                stepSize: 5,
                                selectedColor: Color(0xFF047857),
                                unselectedColor: Colors.white.withOpacity(0.3),
                                padding: 0,
                                width: progressSize,
                                height: progressSize,
                                selectedStepSize: hasKeywords ? 6 : 5,
                                unselectedStepSize: 4,
                                roundedCap: (_, __) => true,
                                gradientColor: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFF059669), // 深绿色
                                    Color(0xFF047857), // 墨绿色
                                  ],
                                ),
                              ),
                              
                              // 中心内容 - 深色文字
                              Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
        children: [
                                    Icon(
                                      hasKeywords ? Icons.warning_amber : Icons.text_fields,
                                      color: Color(0xFF2D3748),
                                      size: progressSize * 0.3,
                                    ),
                                    SizedBox(height: 2),
          Text(
                                      '${(confidence * 100).toStringAsFixed(0)}%',
            style: TextStyle(
                                        fontSize: progressSize * 0.22,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF2D3748),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        SizedBox(height: 6),
                        
                        // 标签 - 深色，右对齐
                        Text(
                          '文本',
                          style: TextStyle(
                            fontSize: 13,
              fontWeight: FontWeight.w600,
                            color: Color(0xFF2D3748),
            ),
          ),
                        
                        SizedBox(height: 2),
                        
                        // 状态 - 深色，右对齐
          Text(
                          hasKeywords 
                              ? '${_textKeywords.length}个关键词' 
                              : (isActive ? '监测中' : '未监测'),
            style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
            ),
          ),
        ],
          ),
        ),
      ),
    );
  }
  
  // 底部卡片E（音频检测 - 带背景图片和线性进度条）
  Widget _buildBottomCard() {
    final isActive = _currentState == DetectionState.monitoring ||
                     _currentState == DetectionState.warning;
    final confidence = _audioConfidence;
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        image: DecorationImage(
          image: AssetImage('lib/UIimages/音频检测背景.png'),
          fit: BoxFit.cover,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              // 左侧：线性进度条（30%宽度）
              Expanded(
                flex: 30,
      child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
                    // 进度条（文本叠加在上方）
                    Container(
                      height: 36,
                      child: Stack(
            children: [
                          // 底层：进度条
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: StepProgressIndicator(
                                totalSteps: 100,
                                currentStep: (confidence * 100).toInt(),
                                size: 36,
                                padding: 0,
                                selectedGradientColor: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Color(0xFF10B981), // 翠绿色
                                    Color(0xFF34D399), // 浅绿色
                                  ],
                                ),
                                unselectedGradientColor: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    Color(0xFFE5E7EB),
                                    Color(0xFFE5E7EB),
                                  ],
                                ),
                                roundedEdges: Radius.circular(18),
                              ),
                            ),
                          ),
                          
                          // 上层：文本
                          Positioned.fill(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
              Text(
                                    '音频',
                style: TextStyle(
                  fontSize: 14,
                                      color: Color(0xFF2D3748),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${(confidence * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 18,
                  fontWeight: FontWeight.bold,
                                      color: Color(0xFF10B981),
                                      shadows: [
                                        Shadow(
                                          color: Colors.white,
                                          blurRadius: 2,
                                        ),
                                      ],
                ),
              ),
            ],
          ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
          SizedBox(height: 8),
                    
                    // 状态文字
                    Center(
                      child: Text(
                        isActive ? '正在监测...' : '未监测',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(width: 16),
              
              // 中间：音频波形（45%宽度）
          Expanded(
                flex: 45,
                child: Container(
                  decoration: BoxDecoration(
                    color: Color(0xFFF8FAF9), // 指定的背景颜色
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: isActive
                ? CustomPaint(
                    painter: RealWaveformPainter(
                      waveformData: _realAudioWaveform,
                              color: Color(0xFF059669), // 深绿色
                    ),
                    size: Size.infinite,
                  )
                : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.graphic_eq,
                                  color: Color(0xFF9CA3AF),
                                  size: 32,
                                ),
                                SizedBox(height: 8),
                                Text(
                      '未监测',
                      style: TextStyle(
                        fontSize: 12,
                                    color: Color(0xFF6B7280),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                      ),
                    ),
                  ),
              ),
              
              // 右侧：留白（25%宽度）
              Expanded(
                flex: 25,
                child: SizedBox(),
          ),
        ],
          ),
        ),
      ),
    );
  }
  
  // ✅ 一键报警按钮
  Widget _buildEmergencyButton() {
    return GestureDetector(
      onTap: _triggerEmergencyAlert,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFFDC2626), // 红色
              Color(0xFFB91C1C), // 深红色
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Color(0xFFDC2626).withOpacity(0.4),
              blurRadius: 12,
              spreadRadius: 2,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emergency,
              color: Colors.white,
              size: 20,
            ),
            SizedBox(width: 8),
            Text(
              '一键报警',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // ✅ 触发一键报警
  Future<void> _triggerEmergencyAlert() async {
    // 显示确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red),
            SizedBox(width: 8),
            Text('确认报警'),
          ],
        ),
        content: Text(
          '您确定要触发紧急报警吗？这将立即通知您的家庭组管理员。',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('确认报警'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // 获取当前通话记录ID
    final callId = _detectionService.callRecordId;
    if (callId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('未找到当前通话记录，无法发送报警'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    // 显示加载中
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    try {
      // 调用一键报警 API
      final dio = Dio();
      final token = AuthService().getToken();
      
      final response = await dio.post(
        '${GlobalConstants.BASE_URL}/api/call-records/$callId/emergency-alert',
        data: {
          'call_id': int.parse(callId),
          'alert_type': 'emergency',
          'message': '用户主动触发紧急报警，可能正在遭遇诈骗！',
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );
      
      // 关闭加载对话框
      Navigator.pop(context);
      
      if (response.statusCode == 200) {
        final data = response.data;
        final notifiedCount = data['data']?['notified_admins'] ?? 0;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 紧急报警已发送，已通知 $notifiedCount 位管理员'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        throw Exception('发送失败');
      }
    } catch (e) {
      // 关闭加载对话框
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ 发送报警失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // 状态信息卡片
  Widget _buildStatusInfoCard() {
    String statusText;
    Color statusColor;
    
    // 根据防御等级显示不同颜色
    Color defenseColor;
    String defenseText;
    
    switch (_currentDefenseLevel) {
      case 1:
        defenseColor = AppColors.success;
        defenseText = 'Level 1 - 正常';
        break;
      case 2:
        defenseColor = AppColors.warning;
        defenseText = 'Level 2 - 警惕';
        break;
      case 3:
        defenseColor = AppColors.error;
        defenseText = 'Level 3 - 危险';
        break;
      default:
        defenseColor = AppColors.textSecondary;
        defenseText = 'Level 1 - 正常';
    }
    
    switch (_currentState) {
      case DetectionState.idle:
        statusText = '点击开始按钮启动实时监测';
        statusColor = AppColors.textLight;
        break;
      case DetectionState.preparing:
        statusText = '正在准备...';
        statusColor = AppColors.warning;
        break;
      case DetectionState.connecting:
        statusText = '正在连接服务器...';
        statusColor = AppColors.primary;
        break;
      case DetectionState.monitoring:
        statusText = '监测中...';
        statusColor = defenseColor;
        break;
      case DetectionState.warning:
        statusText = '⚠️ 检测到风险！';
        statusColor = AppColors.error;
        break;
      case DetectionState.stopping:
        statusText = '正在停止...';
        statusColor = AppColors.textLight;
        break;
      case DetectionState.error:
        statusText = _statusMessage;
        statusColor = AppColors.error;
        break;
    }
    
    return Container(
      padding: EdgeInsets.all(AppTheme.paddingLarge),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: AppColors.borderMedium,
          width: AppTheme.borderMedium,
        ),
        boxShadow: AppTheme.shadowSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_isConnected)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    border: Border.all(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    '已连接',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeSmall,
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          if (_currentState == DetectionState.monitoring || _currentState == DetectionState.warning) ...[
            SizedBox(height: AppTheme.paddingMedium),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.paddingMedium,
                vertical: AppTheme.paddingSmall,
              ),
              decoration: BoxDecoration(
                color: defenseColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(
                  color: defenseColor,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: defenseColor.withOpacity(0.3),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield, color: defenseColor, size: 18),
                  SizedBox(width: 8),
                  Text(
                    defenseText,
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeMedium,
                      fontWeight: FontWeight.bold,
                      color: defenseColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  // 底部三个检测数据卡片（纵向排列）
  Widget _buildDetectionDataCards() {
    return Column(
      children: [
        Expanded(
          child: _buildSmallDataCard(
            icon: Icons.mic,
            label: '音频',
            confidence: _audioConfidence,
            isSafe: !_audioIsFake,
            color: Color(0xFF00D9FF),
          ),
        ),
        SizedBox(height: 8),
        Expanded(
          child: _buildSmallDataCard(
            icon: Icons.videocam,
            label: '视频',
            confidence: _videoConfidence,
            isSafe: !_videoIsDeepfake,
            color: Color(0xFFFF6B9D),
          ),
        ),
        SizedBox(height: 8),
        Expanded(
          child: _buildSmallDataCard(
            icon: Icons.text_fields,
            label: '文本',
            confidence: _textConfidence,
            isSafe: _textRiskLevel == 'safe',
            color: Color(0xFFFFC107),
          ),
        ),
      ],
    );
  }
  
  // 小数据卡片
  Widget _buildSmallDataCard({
    required IconData icon,
    required String label,
    required double confidence,
    required bool isSafe,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: color,
          width: AppTheme.borderMedium,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '${(confidence * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 16,
                    color: color,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: color.withOpacity(0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSafe ? AppColors.success : AppColors.error,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Text(
              isSafe ? '安全' : '风险',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textDark,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // 状态卡片（旧的，保留以防需要）
  Widget _buildStatusCard() {
    Color statusColor;
    IconData statusIcon;
    String statusText;
    
    // ✅ 根据防御等级显示不同颜色
    Color defenseColor;
    String defenseText;
    
    switch (_currentDefenseLevel) {
      case 1:
        defenseColor = AppColors.success;
        defenseText = 'Level 1 - 正常';
        break;
      case 2:
        defenseColor = AppColors.warning;
        defenseText = 'Level 2 - 警惕';
        break;
      case 3:
        defenseColor = AppColors.error;
        defenseText = 'Level 3 - 危险';
        break;
      default:
        defenseColor = AppColors.textSecondary;
        defenseText = 'Level 1 - 正常';
    }
    
    switch (_currentState) {
      case DetectionState.idle:
        statusColor = AppColors.textLight;
        statusIcon = Icons.radio_button_unchecked;
        statusText = '未启动';
        break;
      case DetectionState.preparing:
        statusColor = AppColors.warning;
        statusIcon = Icons.hourglass_empty;
        statusText = '准备中';
        break;
      case DetectionState.connecting:
        statusColor = AppColors.primary;
        statusIcon = Icons.sync;
        statusText = '连接中';
        break;
      case DetectionState.monitoring:
        statusColor = defenseColor;  // ✅ 使用防御等级颜色
        statusIcon = Icons.radio_button_checked;
        statusText = '监测中';
        break;
      case DetectionState.warning:
        statusColor = AppColors.error;
        statusIcon = Icons.warning;
        statusText = '警告';
        break;
      case DetectionState.stopping:
        statusColor = AppColors.textLight;
        statusIcon = Icons.stop_circle;
        statusText = '停止中';
        break;
      case DetectionState.error:
        statusColor = AppColors.error;
        statusIcon = Icons.error;
        statusText = '错误';
        break;
    }
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: statusColor,
          width: AppTheme.borderThick,
        ),
        boxShadow: _currentState == DetectionState.monitoring
            ? [
                BoxShadow(
                  color: statusColor.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : AppTheme.shadowMedium,
      ),
      padding: EdgeInsets.all(AppTheme.paddingLarge),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: statusColor,
                width: 3,
              ),
            ),
            child: Icon(statusIcon, color: statusColor, size: 48),
          ),
          SizedBox(height: AppTheme.paddingMedium),
          Text(
            statusText,
            style: TextStyle(
              fontSize: AppTheme.fontSizeXLarge,
              fontWeight: FontWeight.bold,
              color: statusColor,
              shadows: _currentState == DetectionState.monitoring
                  ? [
                      Shadow(
                        color: statusColor.withOpacity(0.5),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
          ),
          SizedBox(height: AppTheme.paddingSmall),
          Text(
            _statusMessage,
            style: TextStyle(
              fontSize: AppTheme.fontSizeMedium,
              color: AppColors.textLight,
            ),
            textAlign: TextAlign.center,
          ),
          
          // ✅ 显示防御等级
          if (_currentState == DetectionState.monitoring || _currentState == DetectionState.warning) ...[
            SizedBox(height: AppTheme.paddingMedium),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.paddingMedium,
                vertical: AppTheme.paddingSmall,
              ),
              decoration: BoxDecoration(
                color: defenseColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(
                  color: defenseColor,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: defenseColor.withOpacity(0.3),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield, color: defenseColor, size: 20),
                  SizedBox(width: 8),
                  Text(
                    defenseText,
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeMedium,
                      fontWeight: FontWeight.bold,
                      color: defenseColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  // 音频波形显示
  Widget _buildAudioWaveform() {
    // ✅ 计算当前平均分贝值（用于显示）
    final avgDecibel = _realAudioWaveform.isEmpty 
        ? 0.0 
        : _realAudioWaveform.reduce((a, b) => a + b) / _realAudioWaveform.length * 60;
    
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: AppColors.borderMedium,
          width: AppTheme.borderMedium,
        ),
        boxShadow: AppTheme.shadowSmall,
      ),
      padding: EdgeInsets.all(AppTheme.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq, color: AppColors.primary, size: 20),
              SizedBox(width: AppTheme.paddingSmall),
              Text(
                '音频监测',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Spacer(),
              if (_currentState == DetectionState.monitoring)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    border: Border.all(
                      color: AppColors.success,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.volume_up, color: AppColors.success, size: 14),
                      SizedBox(width: 4),
                      Text(
                        '${avgDecibel.toStringAsFixed(1)} dB',
                        style: TextStyle(
                          fontSize: AppTheme.fontSizeSmall,
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: AppTheme.paddingSmall),
          Expanded(
            child: _currentState == DetectionState.monitoring
                ? Container(
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      border: Border.all(
                        color: AppColors.secondary.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: CustomPaint(
                      painter: RealWaveformPainter(
                        waveformData: _realAudioWaveform,
                        color: AppColors.primary,
                      ),
                      size: Size.infinite,
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.mic_off,
                          color: AppColors.textLight,
                          size: 32,
                        ),
                        SizedBox(height: 8),
                        Text(
                          '未监测',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeSmall,
                            color: AppColors.textLight,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
  
  // 检测结果显示
  Widget _buildDetectionResults() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(
          color: AppColors.borderMedium,
          width: AppTheme.borderMedium,
        ),
        boxShadow: AppTheme.shadowSmall,
      ),
      padding: EdgeInsets.all(AppTheme.paddingLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.analytics,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Text(
                '检测结果',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeLarge,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          SizedBox(height: AppTheme.paddingMedium),
          
          // 音频检测
          _buildResultItem(
            icon: Icons.mic,
            label: '音频检测',
            confidence: _audioConfidence,
            isSafe: !_audioIsFake,
          ),
          
          SizedBox(height: AppTheme.paddingSmall),
          
          // 视频检测
          _buildResultItem(
            icon: Icons.videocam,
            label: '视频检测',
            confidence: _videoConfidence,
            isSafe: !_videoIsDeepfake,
          ),
          
          SizedBox(height: AppTheme.paddingSmall),
          
          // 文本检测
          _buildResultItem(
            icon: Icons.text_fields,
            label: '文本检测',
            confidence: _textConfidence,
            isSafe: _textRiskLevel == 'safe',
            keywords: _textKeywords,
          ),
        ],
      ),
    );
  }
  
  // 单个检测结果项
  Widget _buildResultItem({
    required IconData icon,
    required String label,
    required double confidence,
    required bool isSafe,
    List<String>? keywords,
  }) {
    final color = isSafe ? AppColors.success : AppColors.error;
    final statusText = isSafe ? '安全' : '风险';
    
    return Container(
      padding: EdgeInsets.all(AppTheme.paddingMedium),
      decoration: BoxDecoration(
        color: isSafe 
            ? AppColors.secondary.withOpacity(0.1)
            : AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: color,
          width: 2,
        ),
        boxShadow: !isSafe
            ? [
                BoxShadow(
                  color: color.withOpacity(0.2),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color, width: 2),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              SizedBox(width: AppTheme.paddingMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                            child: LinearProgressIndicator(
                              value: confidence,
                              minHeight: 8,
                              backgroundColor: AppColors.secondary.withOpacity(0.2),
                              valueColor: AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                        ),
                        SizedBox(width: AppTheme.paddingSmall),
                        Text(
                          '${(confidence * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeSmall,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: AppTheme.paddingMedium),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  boxShadow: !isSafe
                      ? [
                          BoxShadow(
                            color: color.withOpacity(0.4),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppColors.textDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          // ✅ 显示关键词（如果有）
          if (keywords != null && keywords.isNotEmpty) ...[
            SizedBox(height: AppTheme.paddingSmall),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(AppTheme.paddingSmall),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Icon(Icons.warning_amber, color: color, size: 14),
                  Text(
                    '关键词:',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeSmall,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  ...keywords.map((keyword) => Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color, width: 1),
                    ),
                    child: Text(
                      keyword,
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeSmall,
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  // 风险警告
  Widget _buildRiskWarning() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.error,
            AppColors.error.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: AppColors.accent,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withOpacity(0.4),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: EdgeInsets.all(AppTheme.paddingLarge),
      child: Row(
        children: [
          Icon(Icons.warning, color: AppColors.accent, size: 32),
          SizedBox(width: AppTheme.paddingMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '⚠️ 风险警告',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeLarge,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '检测到可疑内容，请提高警惕！',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeMedium,
                    color: AppColors.cream,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // 控制按钮
  Widget _buildControlButtons() {
    // ✅ warning 状态也属于「正在检测中」，按钮应显示「停止监测」
    final isMonitoring = _currentState == DetectionState.monitoring ||
                         _currentState == DetectionState.warning;
    final isProcessing = _currentState == DetectionState.preparing ||
                        _currentState == DetectionState.connecting ||
                        _currentState == DetectionState.stopping;
    
    return Container(
      height: 60,
      decoration: BoxDecoration(
        gradient: isMonitoring
            ? LinearGradient(
                colors: [AppColors.error, AppColors.error.withOpacity(0.8)],
              )
            : AppTheme.gradientGreen,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: isMonitoring ? AppColors.accent : AppColors.primary,
          width: 3,
        ),
        boxShadow: isProcessing
            ? []
            : isMonitoring
                ? [
                    BoxShadow(
                      color: AppColors.error.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : AppTheme.glowGreen,
      ),
      child: ElevatedButton.icon(
        onPressed: isProcessing
            ? null
            : isMonitoring
                ? _stopMonitoring
                : _startMonitoring,
        icon: isProcessing
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.textDark),
                ),
              )
            : Icon(
                isMonitoring ? Icons.stop : Icons.play_arrow,
                size: 32,
              ),
        label: Text(
          isProcessing
              ? '处理中...'
              : isMonitoring
                  ? '停止监测'
                  : '开始监测',
          style: TextStyle(
            fontSize: AppTheme.fontSizeLarge,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.textDark,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
        ),
      ),
    );
  }
  
  // 权限提示
  Widget _buildPermissionHint() {
    return Container(
      padding: EdgeInsets.all(AppTheme.paddingMedium),
      decoration: BoxDecoration(
        color: AppColors.secondary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: AppColors.secondary,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.primary, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '权限说明',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '实时监测需要麦克风和摄像头权限。如未授权，点击开始时会提示授权。',
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeSmall,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pushNamed(context, '/permission-settings');
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
            ),
            child: Text(
              '查看',
              style: TextStyle(
                fontSize: AppTheme.fontSizeSmall,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 半圆仪表盘绘制器（三个半圆环形进度条）
class SemiCircularGaugePainter extends CustomPainter {
  final double audioProgress;
  final double videoProgress;
  final double textProgress;
  final bool isMonitoring;
  
  SemiCircularGaugePainter({
    required this.audioProgress,
    required this.videoProgress,
    required this.textProgress,
    required this.isMonitoring,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 40);
    final baseRadius = size.width / 2 - 40;
    
    // 定义三种漂亮的颜色
    final audioColor = Color(0xFF00D9FF); // 青蓝色
    final videoColor = Color(0xFFFF6B9D); // 粉红色
    final textColor = Color(0xFFFFC107);  // 金黄色
    
    // 绘制三层半圆环（从外到内）
    _drawSemiCircle(canvas, center, baseRadius + 40, audioProgress, audioColor);
    _drawSemiCircle(canvas, center, baseRadius + 20, videoProgress, videoColor);
    _drawSemiCircle(canvas, center, baseRadius, textProgress, textColor);
  }
  
  void _drawSemiCircle(Canvas canvas, Offset center, double radius, double progress, Color color) {
    // 背景半圆环（黑色）
    final bgPaint = Paint()
      ..color = Color(0xFF1A1C1F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      bgPaint,
    );
    
    // 进度半圆环（彩色）
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    
    // 添加发光效果
    final glowPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10);
    
    final sweepAngle = math.pi * progress;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      sweepAngle,
      false,
      glowPaint,
    );
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      sweepAngle,
      false,
      progressPaint,
    );
  }
  
  @override
  bool shouldRepaint(SemiCircularGaugePainter oldDelegate) {
    return oldDelegate.audioProgress != audioProgress ||
           oldDelegate.videoProgress != videoProgress ||
           oldDelegate.textProgress != textProgress ||
           oldDelegate.isMonitoring != isMonitoring;
  }
}

// 向下凹陷的曲线分隔线绘制器
class CurveDividerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Color(0xFFD0E8D0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    final path = Path();
    
    // 从左边开始
    path.moveTo(0, 0);
    
    // 绘制向下凹陷的贝塞尔曲线
    path.quadraticBezierTo(
      size.width / 2, // 控制点 x（中心）
      80,             // 控制点 y（向下凹陷的深度）
      size.width,     // 终点 x
      0,              // 终点 y
    );
    
    canvas.drawPath(path, paint);
    
    // 添加阴影效果
    final shadowPaint = Paint()
      ..color = Color(0xFFD0E8D0).withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);
    
    canvas.drawPath(path, shadowPaint);
  }
  
  @override
  bool shouldRepaint(CurveDividerPainter oldDelegate) => false;
}

// 圆形仪表盘绘制器（三个环形进度条）
class CircularGaugePainter extends CustomPainter {
  final double audioProgress;
  final double videoProgress;
  final double textProgress;
  final bool isMonitoring;
  
  CircularGaugePainter({
    required this.audioProgress,
    required this.videoProgress,
    required this.textProgress,
    required this.isMonitoring,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = math.min(size.width, size.height) / 2 - 40;
    
    // 定义三种漂亮的颜色
    final audioColor = Color(0xFF00D9FF); // 青蓝色
    final videoColor = Color(0xFFFF6B9D); // 粉红色
    final textColor = Color(0xFFFFC107);  // 金黄色
    
    // 绘制三层圆环（从外到内）
    _drawCircle(canvas, center, baseRadius + 30, audioProgress, audioColor);
    _drawCircle(canvas, center, baseRadius + 15, videoProgress, videoColor);
    _drawCircle(canvas, center, baseRadius, textProgress, textColor);
  }
  
  void _drawCircle(Canvas canvas, Offset center, double radius, double progress, Color color) {
    // 背景圆环（黑色）
    final bgPaint = Paint()
      ..color = Color(0xFF1A1C1F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    
    canvas.drawCircle(center, radius, bgPaint);
    
    // 进度圆环（彩色）
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    
    // 添加发光效果
    final glowPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8);
    
    final sweepAngle = 2 * math.pi * progress;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      glowPaint,
    );
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }
  
  @override
  bool shouldRepaint(CircularGaugePainter oldDelegate) {
    return oldDelegate.audioProgress != audioProgress ||
           oldDelegate.videoProgress != videoProgress ||
           oldDelegate.textProgress != textProgress ||
           oldDelegate.isMonitoring != isMonitoring;
  }
}

// 环形进度条绘制器（用于矩形E的音频百分比显示）
class CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color backgroundColor;
  final Color progressColor;
  final double strokeWidth;
  
  CircularProgressPainter({
    required this.progress,
    required this.backgroundColor,
    required this.progressColor,
    required this.strokeWidth,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    
    // 背景圆环
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    
    canvas.drawCircle(center, radius, bgPaint);
    
    // 进度圆环
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    
    // 添加发光效果
    final glowPaint = Paint()
      ..color = progressColor.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 4
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8);
    
    final sweepAngle = 2 * math.pi * progress;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      glowPaint,
    );
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }
  
  @override
  bool shouldRepaint(CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// 真实音频波形绘制器
class RealWaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final Color color;
  
  RealWaveformPainter({required this.waveformData, required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 6.0  // 增加线条粗细
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;
    
    final barWidth = size.width / waveformData.length;
    final centerY = size.height / 2;
    
    for (int i = 0; i < waveformData.length; i++) {
      final x = i * barWidth;
      final normalizedValue = waveformData[i];
      
      // 增强显示效果
      final enhancedValue = math.sqrt(normalizedValue) * 1.5;
      final barHeight = math.max(enhancedValue * size.height * 0.9, 6.0);  // 增加最小高度
      
      // 从中心向上下绘制
      final topY = centerY - barHeight / 2;
      final bottomY = centerY + barHeight / 2;
      
      // 使用绿色渐变增强视觉效果
      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withOpacity(0.5),
          color,
          color.withOpacity(0.5),
        ],
      );
      
      final rect = Rect.fromLTRB(x, topY, x + barWidth - 2, bottomY);  // 增加条形宽度
      final gradientPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.fill;
      
      // 绘制圆角矩形，增加圆角半径
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(3),
      );
      canvas.drawRRect(rrect, gradientPaint);
      
      // 添加绿色发光效果
      final glowPaint = Paint()
        ..color = color.withOpacity(0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawRRect(rrect, glowPaint);
    }
  }
  
  @override
  bool shouldRepaint(RealWaveformPainter oldDelegate) {
    return oldDelegate.waveformData != waveformData;
  }
}

// 旧的波形绘制器（已废弃，保留以防需要）
class WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;
  
  WaveformPainter({required this.progress, required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    final path = Path();
    final waveCount = 3;
    final amplitude = size.height / 4;
    
    for (int i = 0; i < size.width.toInt(); i++) {
      final x = i.toDouble();
      final y = size.height / 2 +
          math.sin((i / size.width * waveCount * 2 * math.pi) + (progress * 2 * math.pi)) *
              amplitude *
              (0.5 + math.Random(i).nextDouble() * 0.5);
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
