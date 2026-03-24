import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/auth_service.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/baidu_speech_service.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/foreground_task_handler.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/local_notification_service.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/AudioRecordingService.dart';
import 'package:ai_anti_fraud_detection_system_frontend/utils/DioRequest.dart';
import 'package:ai_anti_fraud_detection_system_frontend/contants/index.dart';

/// 实时检测服务
class RealTimeDetectionService {
  // WebSocket 连接
  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  
  // ✅ 新的音频录制服务（使用 VOICE_COMMUNICATION 源）
  final AudioRecordingServiceDart _audioRecordingService = AudioRecordingServiceDart();
  bool _isAudioRecordingActive = false;
  
  // 音频缓冲区（用于积攒数据后发送）
  final List<int> _audioBuffer = [];
  static const int AUDIO_BATCH_SIZE = 32000; // 1秒的音频数据（16000Hz × 2bytes/sample × 1channel）
  Timer? _audioSendTimer;
  
  // 屏幕截图控制
  static const platform = MethodChannel('com.example.ai_anti_fraud_detection_system_frontend/screen_capture');
  bool _isScreenCaptureActive = false;
  Timer? _videoFrameTimer;
  bool _isCapturingFrame = false; // 防止并发截图
  
  // ✅ 百度语音识别服务（用于文字流检测）
  final BaiduSpeechService _speechService = BaiduSpeechService();
  bool _isSpeechRecognitionActive = false;
  
  // ✅ 本地通知服务（用于后台警告）
  final LocalNotificationService _notificationService = LocalNotificationService();
  
  // 音频波形数据（使用可变列表）
  final List<double> _audioWaveformData = List.generate(50, (_) => 0.0);
  
  // 连接状态
  bool _isConnected = false;
  bool _isDisconnecting = false;  // ✅ 主动断开标志：主动断开时不触发 onDisconnected
  String? _callRecordId;
  
  // ✅ 三级防御机制
  int _currentDefenseLevel = 1;  // 当前防御等级（1/2/3）
  double _currentVideoFPS = 1.0;  // 当前视频帧率
  bool _isRecordingCall = false;  // 是否正在录音
  
  // ✅ 定时通知
  Timer? _notificationTimer;
  int _notificationCount = 0;
  
  // 回调函数
  Function(Map<String, dynamic>)? onDetectionResult;  // 检测结果回调
  Function(String)? onStatusChange;                    // 状态变化回调
  Function(String)? onError;                           // 错误回调
  Function()? onConnected;                             // 连接成功回调
  Function()? onDisconnected;                          // 断开连接回调
  Function(List<double>)? onAudioWaveformUpdate;      // 音频波形回调
  Function(Map<String, dynamic>)? onControlMessage;   // 控制消息回调（防御升级等）
  Function(String, String)? onAckReceived;            // ACK 确认回调
  Function(int)? onDefenseLevelChanged;               // 防御等级变化回调
  Function(Map<String, dynamic>)? onEnvironmentDetected; // 环境识别回调
  Function(Map<String, dynamic>)? onFamilyAlert;      // ✅ 家庭预警回调（管理员接收）
  Function(Map<String, dynamic>)? onEmergencyAlert;   // ✅ 紧急报警回调
  
  // WebSocket URL - 动态获取，与 HTTP 地址保持一致
  String get _wsBaseUrl {
    // 将 http:// 替换为 ws://
    return GlobalConstants.BASE_URL.replaceFirst('http://', 'ws://');
  }
  
  /// 开始实时监测
  Future<bool> startDetection() async {
    try {
      // ✅ 0. 检查 CallDetectionService 是否启用
      print('🔍 检查 CallDetectionService 状态...');
      final isCallDetectionEnabled = await _checkCallDetectionService();
      if (!isCallDetectionEnabled) {
        print('⚠️ 警告: CallDetectionService 未启用！');
        print('   这会导致无法自动检测通话，麦克风可能无法获取声音');
        onError?.call('⚠️ 无障碍服务未启用\n\n请在权限设置中启用"无障碍服务"，否则无法获取通话音频！');
        return false;
      }
      print('✅ CallDetectionService 已启用');
      
      // ✅ 0. 初始化本地通知服务
      await _notificationService.initialize();
      
      // ✅ 1. 初始化并启动前台服务
      final foregroundServiceStarted = await _startForegroundService();
      if (!foregroundServiceStarted) {
        onError?.call('启动前台服务失败');
        return false;
      }
      
      // 2. 创建通话记录
      final recordId = await _createCallRecord();
      if (recordId == null) {
        onError?.call('创建通话记录失败');
        await _stopForegroundService();
        return false;
      }
      _callRecordId = recordId;
      
      // 3. 连接 WebSocket
      final connected = await _connectWebSocket();
      if (!connected) {
        onError?.call('连接服务器失败');
        await _stopForegroundService();
        return false;
      }
      
      // 4. 开始录音
      final recordingStarted = await _startAudioRecording();
      if (!recordingStarted) {
        onError?.call('启动录音失败');
        await _disconnectWebSocket();
        await _stopForegroundService();
        return false;
      }
      
      // 5. 开始屏幕截图
      final screenCaptureStarted = await _startScreenCapture();
      if (!screenCaptureStarted) {
        print('⚠️ 屏幕截图启动失败，仅使用音频检测');
        // 不阻断流程，继续使用音频检测
      }
      
      // ✅ 6. 启动语音识别（用于文字流检测）
      final speechStarted = await _startSpeechRecognition();
      if (!speechStarted) {
        print('⚠️ 语音识别启动失败，仅使用音视频检测');
        // 不阻断流程，继续使用音视频检测
      }
      
      // ✅ 7. 启动定时通知（每5秒弹一次）
      _startPeriodicNotifications();
      
      onStatusChange?.call('监测已启动');
      return true;
    } catch (e) {
      onError?.call('启动失败: $e');
      return false;
    }
  }
  
  /// 停止实时监测
  Future<void> stopDetection() async {
    try {
      // 0. 停止定时通知
      _stopPeriodicNotifications();
      
      // 1. 停止录音
      await _stopAudioRecording();
      
      // 2. 停止屏幕截图
      await _stopScreenCapture();
      
      // ✅ 3. 停止语音识别
      await _stopSpeechRecognition();
      
      // 4. 断开 WebSocket（根据文档，关闭连接即可，无需调用结束接口）
      await _disconnectWebSocket();
      
      // ✅ 5. 停止前台服务
      await _stopForegroundService();
      
      // ✅ 6. 取消所有通知
      await _notificationService.cancelAll();
      
      onStatusChange?.call('监测已停止');
    } catch (e) {
      onError?.call('停止失败: $e');
    }
  }
  
  /// 检查 CallDetectionService 是否启用
  Future<bool> _checkCallDetectionService() async {
    try {
      // 使用 CallDetectionService 中的方法检查无障碍服务状态
      const platform = MethodChannel('com.example.ai_anti_fraud_detection_system_frontend/call_detection');
      final result = await platform.invokeMethod<bool>('isAccessibilityServiceEnabled');
      
      final isEnabled = result ?? false;
      print('📱 CallDetectionService 状态检查结果: $isEnabled');
      
      if (!isEnabled) {
        print('❌ CallDetectionService 未启用');
        print('   原因: 无障碍服务未在系统设置中启用');
        print('   影响: 无法自动检测通话，麦克风无法获取声音');
        print('   解决: 请在权限设置中启用"无障碍服务"');
      } else {
        print('✅ CallDetectionService 已启用');
        print('   可以自动检测通话');
        print('   麦克风可以获取通话声音');
      }
      
      return isEnabled;
    } catch (e) {
      print('❌ 检查 CallDetectionService 失败: $e');
      print('   这可能表示无障碍服务配置有问题');
      return false;
    }
  }
  
  /// 创建通话记录
  Future<String?> _createCallRecord() async {
    try {
      final token = AuthService().getToken();
      if (token.isEmpty) {
        print('❌ 创建通话记录失败: 未登录');
        return null;
      }
      
      print('📞 创建通话记录...');
      
      // 使用 POST 请求，参数作为 query parameters
      final response = await dioRequest.post(
        '/api/call-records/start',
        params: {
          'platform': 'android',
          'target_identifier': 'realtime_detection',
        },
      );
      
      // 后端返回的是 call_id，不是 id
      if (response != null && response['call_id'] != null) {
        print('✅ 通话记录创建成功: call_id=${response['call_id']}');
        return response['call_id'].toString();
      }
      
      print('❌ 创建通话记录失败: 响应无效 - $response');
      return null;
    } catch (e) {
      print('❌ 创建通话记录失败: $e');
      return null;
    }
  }
  
  /// 连接 WebSocket
  Future<bool> _connectWebSocket() async {
    try {
      final token = AuthService().getToken();
      if (token.isEmpty) {
        print('❌ WebSocket 连接失败: 未登录');
        return false;
      }
      
      // 获取用户信息
      final userInfo = await AuthService().getCurrentUser();
      if (userInfo == null || userInfo['user_id'] == null) {
        print('❌ WebSocket 连接失败: 无法获取用户ID');
        print('   用户信息: $userInfo');
        return false;
      }
      
      final userId = userInfo['user_id'];
      
      // 按照文档格式构建 WebSocket URL
      // ws://172.20.16.1:8000/api/detection/ws/{user_id}/{call_id}?token={jwt_token}
      final wsUrl = '$_wsBaseUrl/api/detection/ws/$userId/$_callRecordId?token=$token';
      print('🔌 连接 WebSocket: $wsUrl');
      
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      // 监听消息
      _channelSubscription = _channel!.stream.listen(
        (message) {
          _handleWebSocketMessage(message);
        },
        onError: (error) {
          print('❌ WebSocket 错误: $error');
          _isConnected = false;
          if (!_isDisconnecting) {
            // ✅ 只在非主动断开时（如网络抖动、前后台切换）才通知外部
            onError?.call('连接错误: $error');
            onDisconnected?.call();
          }
        },
        onDone: () {
          print('🔌 WebSocket 连接关闭');
          _isConnected = false;
          if (!_isDisconnecting) {
            // ✅ 只在非主动断开时才触发 onDisconnected
            // 前后台切换导致的断开不应改变 UI 检测状态
            onDisconnected?.call();
          }
        },
      );
      
      _isConnected = true;
      onConnected?.call();
      onStatusChange?.call('已连接到服务器');
      
      print('✅ WebSocket 连接成功');
      
      // 发送心跳
      _startHeartbeat();
      
      return true;
    } catch (e) {
      print('❌ 连接 WebSocket 失败: $e');
      return false;
    }
  }
  
  /// 断开 WebSocket（主动断开，不触发 onDisconnected）
  Future<void> _disconnectWebSocket() async {
    _isDisconnecting = true;  // ✅ 标记为主动断开
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    // 先取消订阅，再关闭 sink，避免 onDone 触发 onDisconnected
    await _channelSubscription?.cancel();
    _channelSubscription = null;
    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _isDisconnecting = false;  // ✅ 重置标志
  }
  
  /// 处理 WebSocket 消息（按照接口文档格式）
  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = json.decode(message);
      final type = data['type'];
      
      print('📨 收到消息: type=$type');
      
      switch (type) {
        case 'ack':
          // ACK 确认消息
          final msgType = data['msg_type'] ?? 'unknown';
          final status = data['status'] ?? '';
          final timestamp = data['timestamp'] ?? '';
          
          if (status == 'ready') {
            print('✅ ACK: $msgType (缓冲区已满，已投递检测任务)');
          } else if (status == 'buffering') {
            print('✅ ACK: $msgType (正在积攒帧...)');
          } else {
            print('✅ ACK: $msgType');
          }
          
          onAckReceived?.call(msgType, status);
          break;
          
        case 'heartbeat_ack':
          // 心跳响应
          print('💓 心跳响应');
          break;
          
        case 'detection_result':
          // 检测结果消息（按照文档格式）
          final detectionType = data['detection_type'] ?? '未知';
          final isRisk = data['is_risk'] ?? false;
          final confidence = data['confidence'] ?? 0.0;
          final message = data['message'] ?? '';
          final timestamp = data['timestamp'] ?? '';
          
          print('🔍 检测结果:');
          print('   类型: $detectionType');
          print('   风险: ${isRisk ? "是" : "否"}');
          print('   置信度: ${(confidence * 100).toStringAsFixed(1)}%');
          print('   消息: $message');
          print('   时间: $timestamp');
          
          // 回调给 UI
          onDetectionResult?.call({
            'detection_type': detectionType,
            'is_risk': isRisk,
            'confidence': confidence,
            'message': message,
            'timestamp': timestamp,
          });
          break;
          
        case 'control':
          // 控制消息（防御升级等）
          final action = data['action'] ?? '';
          
          if (action == 'upgrade_level') {
            final targetLevel = data['target_level'] ?? 1;
            final reason = data['reason'] ?? '';
            final config = data['config'] ?? {};
            
            print('⚠️ 防御升级:');
            print('   目标等级: Level $targetLevel');
            print('   原因: $reason');
            print('   配置: $config');
            
            // ✅ 应用防御等级（只升不降）
            _applyDefenseLevel(targetLevel, config);
            
            // 回调给 UI 处理
            onControlMessage?.call({
              'action': action,
              'target_level': targetLevel,
              'reason': reason,
              'config': config,
            });
          } else {
            print('❓ 未知控制动作: $action');
          }
          break;
          
        case 'info':
          // 后端实际返回的消息类型（兼容处理）
          final infoData = data['data'] ?? {};
          final title = infoData['title'] ?? '';
          final infoMessage = infoData['message'] ?? '';
          final riskLevel = infoData['risk_level'] ?? 'safe';
          final confidence = (infoData['confidence'] ?? 0.0).toDouble();
          final timestamp = infoData['timestamp'] ?? '';
          
          print('ℹ️ 信息消息:');
          print('   标题: $title');
          print('   消息: $infoMessage');
          print('   风险等级: $riskLevel');
          print('   置信度: ${(confidence * 100).toStringAsFixed(1)}%');
          
          // 转换为标准格式回调给 UI
          final isRisk = riskLevel != 'safe';
          final detectionType = title.contains('语音') || title.contains('音频') 
              ? '语音' 
              : title.contains('视频') 
                  ? '视频' 
                  : '文本';
          
          onDetectionResult?.call({
            'detection_type': detectionType,
            'is_risk': isRisk,
            'confidence': confidence,
            'message': infoMessage,
            'timestamp': timestamp,
          });
          break;
          
        case 'error':
          // 错误消息
          final errorMsg = data['message'] ?? '未知错误';
          print('❌ 服务器错误: $errorMsg');
          onError?.call(errorMsg);
          break;
          
        case 'status':
          // 状态更新
          final statusMsg = data['message'] ?? '';
          print('📊 状态更新: $statusMsg');
          onStatusChange?.call(statusMsg);
          break;
          
        case 'environment_detected':
          // 环境识别结果
          final environment = data['environment'] ?? 'unknown';
          final platform = data['platform'] ?? 'unknown';
          final speakers = data['chat_speakers'] ?? [];
          final enabledModalities = data['enabled_modalities'] ?? [];
          
          print('🌍 环境识别结果:');
          print('   环境类型: $environment');
          print('   平台: $platform');
          print('   聊天双方: $speakers');
          print('   启用模态: $enabledModalities');
          
          onEnvironmentDetected?.call({
            'environment': environment,
            'platform': platform,
            'chat_speakers': speakers,
            'enabled_modalities': enabledModalities,
            'timestamp': data['timestamp'] ?? '',
          });
          break;
          
        case 'family_alert':
          // ✅ 家庭预警（管理员接收）
          final alertData = data['data'] ?? {};
          print('🚨 收到家庭预警:');
          print('   标题: ${alertData['title']}');
          print('   消息: ${alertData['message']}');
          print('   风险等级: ${alertData['risk_level']}');
          print('   显示模式: ${alertData['display_mode']}');
          print('   动作: ${alertData['action']}');
          
          onFamilyAlert?.call({
            'title': alertData['title'] ?? '家人安全预警',
            'message': alertData['message'] ?? '',
            'risk_level': alertData['risk_level'] ?? 'medium',
            'victim_id': alertData['victim_id'],
            'victim_name': alertData['victim_name'] ?? '未知',
            'victim_phone': alertData['victim_phone'],
            'call_id': alertData['call_id'],
            'family_id': alertData['family_id'],
            'timestamp': alertData['timestamp'] ?? '',
            'display_mode': alertData['display_mode'] ?? 'popup',
            'action': alertData['action'] ?? 'vibrate',
          });
          break;
          
        case 'emergency_alert':
          // ✅ 紧急报警（一键报警）
          final alertData = data['data'] ?? {};
          print('🆘 收到紧急报警:');
          print('   标题: ${alertData['title']}');
          print('   消息: ${alertData['message']}');
          print('   受害者: ${alertData['victim_name']}');
          
          onEmergencyAlert?.call({
            'title': alertData['title'] ?? '🚨 紧急报警',
            'message': alertData['message'] ?? '',
            'victim_id': alertData['victim_id'],
            'victim_name': alertData['victim_name'] ?? '未知',
            'victim_phone': alertData['victim_phone'],
            'call_id': alertData['call_id'],
            'family_id': alertData['family_id'],
            'timestamp': alertData['timestamp'] ?? '',
            'display_mode': alertData['display_mode'] ?? 'fullscreen',
            'action': alertData['action'] ?? 'alarm',
            'alert_type': alertData['alert_type'] ?? 'emergency',
          });
          break;
          
        default:
          print('❓ 未知消息类型: $type');
          print('   完整消息: $data');
      }
    } catch (e) {
      print('❌ 处理 WebSocket 消息失败: $e');
      print('   原始消息: $message');
    }
  }
  
  /// 开始心跳
  Timer? _heartbeatTimer;
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_isConnected && _channel != null) {
        _channel!.sink.add(json.encode({'type': 'heartbeat'}));
        print('💓 发送心跳');
      }
    });
  }
  
  /// 开始音频录制（使用 VOICE_COMMUNICATION 源）
  Future<bool> _startAudioRecording() async {
    try {
      print('🎤 启动音频录制（VOICE_COMMUNICATION 源）...');
      
      // 检查权限
      final status = await Permission.microphone.status;
      if (!status.isGranted) {
        print('❌ 没有录音权限');
        return false;
      }
      
      // 设置音频数据回调
      _audioRecordingService.onAudioDataReceived = (audioBytes) {
        _onAudioDataReceived(audioBytes);
      };
      
      // 设置状态变化回调
      _audioRecordingService.onStatusChanged = (status) {
        print('📊 音频状态: $status');
        onStatusChange?.call('音频: $status');
      };
      
      // 设置错误回调
      _audioRecordingService.onError = (error) {
        print('❌ 音频错误: $error');
        onError?.call('音频错误: $error');
      };
      
      // 启动音频录制
      final started = await _audioRecordingService.startRecording();
      if (!started) {
        print('❌ 启动音频录制失败');
        return false;
      }
      
      _isAudioRecordingActive = true;
      
      // 获取当前使用的音频源
      final audioSource = await _audioRecordingService.getCurrentAudioSource();
      print('✅ 音频录制已启动，使用音频源: $audioSource');
      
      // 启动音频发送定时器
      _startAudioSendTimer();
      
      return true;
    } catch (e) {
      print('❌ 启动音频录制失败: $e');
      return false;
    }
  }
  
  /// 处理接收到的音频数据
  void _onAudioDataReceived(List<int> audioBytes) {
    // 将音频数据添加到缓冲区
    _audioBuffer.addAll(audioBytes);
    
    // 更新波形数据（用于 UI 显示）
    if (audioBytes.isNotEmpty) {
      // 计算音量（简单的 RMS 计算）
      double sum = 0;
      for (int i = 0; i < audioBytes.length; i += 2) {
        if (i + 1 < audioBytes.length) {
          int sample = (audioBytes[i] & 0xFF) | ((audioBytes[i + 1] & 0xFF) << 8);
          if (sample > 32767) sample -= 65536;
          sum += sample * sample;
        }
      }
      double rms = sqrt(sum / (audioBytes.length / 2));
      double normalizedLevel = (rms / 32768).clamp(0.0, 1.0);
      
      // 计算分贝值（dB）
      double decibels = 20 * log((rms / 32768) + 0.00001) / log(10); // 使用换底公式计算 log10
      print('🎤 分贝值: ${decibels.toStringAsFixed(1)} dB, 音量: ${(normalizedLevel * 100).toStringAsFixed(1)}%');
      
      // 更新波形数据
      _audioWaveformData.removeAt(0);
      _audioWaveformData.add(normalizedLevel);
      onAudioWaveformUpdate?.call(List.from(_audioWaveformData));
    }
  }
  
  /// 启动音频发送定时器
  void _startAudioSendTimer() {
    _audioSendTimer?.cancel();
    
    // 每 1 秒发送一次音频数据
    _audioSendTimer = Timer.periodic(Duration(seconds: 1), (timer) async {
      if (!_isAudioRecordingActive || !_isConnected || _channel == null) {
        timer.cancel();
        return;
      }
      
      // 如果缓冲区有数据，发送
      if (_audioBuffer.isNotEmpty) {
        try {
          // 取出缓冲区中的数据（最多 1 秒）
          final sendSize = _audioBuffer.length > AUDIO_BATCH_SIZE 
              ? AUDIO_BATCH_SIZE 
              : _audioBuffer.length;
          
          final audioData = Uint8List.fromList(_audioBuffer.sublist(0, sendSize));
          _audioBuffer.removeRange(0, sendSize);
          
          // ✅ 构建 WAV 文件头（44 字节）
          final wavHeader = _buildWavHeader(audioData.length, 16000, 1);
          
          // ✅ 拼接 WAV 头 + PCM 数据
          final BytesBuilder builder = BytesBuilder();
          builder.add(wavHeader);
          builder.add(audioData);
          final wavBytes = builder.toBytes();
          
          // Base64 编码
          final base64Audio = base64Encode(wavBytes);
          
          // 发送音频数据（附带格式元数据，方便后端解码）
          _channel!.sink.add(json.encode({
            'type': 'audio',
            'data': base64Audio,
            'sample_rate': 16000,
            'channels': 1,
            'encoding': 'wav',
            'duration_ms': (audioData.length / 32.0).round(), // 每32字节=1ms
          }));
          
          print('🎵 发送音频数据: ${wavBytes.length} bytes (含 WAV 头)');
        } catch (e) {
          print('❌ 发送音频数据失败: $e');
        }
      }
    });
  }
  
  /// 停止音频录制
  Future<void> _stopAudioRecording() async {
    try {
      // 先取消定时器
      _audioSendTimer?.cancel();
      _audioSendTimer = null;
      
      if (_isAudioRecordingActive) {
        // 发送缓冲区中剩余的数据
        if (_audioBuffer.isNotEmpty) {
          try {
            final audioData = Uint8List.fromList(_audioBuffer);
            _audioBuffer.clear();
            
            final base64Audio = base64Encode(audioData);
            _channel?.sink.add(json.encode({
              'type': 'audio',
              'data': base64Audio,
            }));
            
            print('🎵 发送剩余音频数据: ${audioData.length} bytes');
          } catch (e) {
            print('⚠️ 发送剩余音频数据失败: $e');
          }
        }
        
        // 停止音频录制
        await _audioRecordingService.stopRecording();
        _isAudioRecordingActive = false;
        print('🎤 音频录制已停止');
      }
    } catch (e) {
      print('❌ 停止音频录制失败: $e');
    }
  }
  
  /// 开始屏幕截图
  Future<bool> _startScreenCapture() async {
    try {
      print('📱 开始屏幕截图...');
      
      // 1. 请求屏幕截图权限
      final result = await platform.invokeMethod('startCapture');
      
      if (result != true) {
        print('❌ 屏幕截图权限获取失败');
        return false;
      }
      
      _isScreenCaptureActive = true;
      
      // 2. 开始定期截图
      _startScreenshotCapture();
      
      print('✅ 屏幕截图已启动');
      return true;
    } catch (e) {
      print('❌ 启动屏幕截图失败: $e');
      return false;
    }
  }
  
  /// 开始截图采集
  void _startScreenshotCapture() {
    _videoFrameTimer?.cancel();
    
    // ✅ 根据当前防御等级动态调整帧率
    final interval = Duration(milliseconds: (1000 / _currentVideoFPS).round());
    print('📸 截图采集间隔: ${interval.inMilliseconds}ms ($_currentVideoFPS fps)');
    
    _videoFrameTimer = Timer.periodic(interval, (timer) async {
      if (!_isScreenCaptureActive || !_isConnected || _channel == null) {
        timer.cancel();
        return;
      }
      
      // 防止并发截图
      if (_isCapturingFrame) {
        print('⏭️ 跳过本次采集（上次未完成）');
        return;
      }
      
      _isCapturingFrame = true;
      
      try {
        // 调用原生方法截图
        final Uint8List? jpegData = await platform.invokeMethod('captureScreen');
        
        if (jpegData != null && jpegData.isNotEmpty) {
          // Base64 编码
          final base64Frame = base64Encode(jpegData);
          
          // 发送视频帧
          _channel!.sink.add(json.encode({
            'type': 'video',
            'data': base64Frame,
          }));
          
          print('📸 发送屏幕截图: ${jpegData.length} bytes');
        }
      } catch (e) {
        print('❌ 截图失败: $e');
      } finally {
        _isCapturingFrame = false;
      }
    });
  }
  
  /// 停止屏幕截图
  Future<void> _stopScreenCapture() async {
    try {
      // 先取消定时器
      _videoFrameTimer?.cancel();
      _videoFrameTimer = null;
      
      // 等待当前采集完成
      while (_isCapturingFrame) {
        await Future.delayed(Duration(milliseconds: 100));
      }
      
      if (_isScreenCaptureActive) {
        _isScreenCaptureActive = false;
        
        // 停止屏幕截图
        await platform.invokeMethod('stopCapture');
        
        print('📱 屏幕截图已停止');
      }
    } catch (e) {
      print('❌ 停止屏幕截图失败: $e');
    }
  }
  
  /// 获取最近的截图（用于验证）
  Future<List<Uint8List>> getRecentScreenshots() async {
    try {
      final result = await platform.invokeMethod('getRecentScreenshots');
      if (result != null && result is List) {
        return result.map((e) => e as Uint8List).toList();
      }
      return [];
    } catch (e) {
      print('❌ 获取截图失败: $e');
      return [];
    }
  }
  
  // ============================================================
  // ✅ 语音识别（文字流检测）
  // ============================================================
  
  /// 启动语音识别（用于文字流检测）
  Future<bool> _startSpeechRecognition() async {
    try {
      print('🎤 启动语音识别（文字流检测）...');
      
      // 1. 初始化语音识别服务
      final initialized = await _speechService.initialize();
      if (!initialized) {
        print('❌ 语音识别初始化失败');
        return false;
      }
      
      // 2. 设置回调函数
      _setupSpeechRecognitionCallbacks();
      
      // 3. 开始识别
      final started = await _speechService.startRecognition();
      if (!started) {
        print('❌ 语音识别启动失败');
        return false;
      }
      
      _isSpeechRecognitionActive = true;
      print('✅ 语音识别已启动');
      return true;
    } catch (e) {
      print('❌ 启动语音识别失败: $e');
      return false;
    }
  }
  
  /// 设置语音识别回调
  void _setupSpeechRecognitionCallbacks() {
    // 临时识别结果（实时显示，不发送给后端）
    _speechService.onPartialResult = (text) {
      print('🎤 临时识别: $text');
      // 可以在这里更新 UI 显示实时识别结果
    };
    
    // ✅ 最终识别结果（发送给后端进行文本检测）
    _speechService.onFinalResult = (text, startTime, endTime) {
      print('✅ 最终识别: $text (${startTime}ms - ${endTime}ms)');
      
      // 将识别的文本发送给后端进行检测
      if (text.isNotEmpty && _isConnected && _channel != null) {
        sendText(text);
      }
    };
    
    // 状态变化
    _speechService.onStatusChange = (status) {
      print('🎤 语音识别状态: $status');
    };
    
    // 错误处理
    _speechService.onError = (error) {
      print('❌ 语音识别错误: $error');
      // 不影响主流程，继续监测
    };
    
    // 连接状态
    _speechService.onConnected = () {
      print('✅ 语音识别已连接');
    };
    
    _speechService.onDisconnected = () {
      print('🔌 语音识别已断开');
    };
  }
  
  /// 停止语音识别
  Future<void> _stopSpeechRecognition() async {
    try {
      if (_isSpeechRecognitionActive) {
        await _speechService.stopRecognition();
        _isSpeechRecognitionActive = false;
        print('🎤 语音识别已停止');
      }
    } catch (e) {
      print('❌ 停止语音识别失败: $e');
    }
  }
  
  /// 发送文本数据（用于文本检测）
  void sendText(String text) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(json.encode({
        'type': 'text',
        'data': text,
      }));
      print('📝 发送文本数据: $text');
    } else {
      print('⚠️ 无法发送文本: WebSocket 未连接');
    }
  }
  
  /// 发送视频帧（用于视频检测）
  void sendVideoFrame(String base64Frame) {
    if (_isConnected && _channel != null) {
      _channel!.sink.add(json.encode({
        'type': 'video',
        'data': base64Frame,
      }));
    }
  }
  
  // ============================================================
  // ✅ 定时通知功能
  // ============================================================
  
  /// 启动定时通知（每10秒弹一次，仅Level 1）
  void _startPeriodicNotifications() {
    _notificationTimer?.cancel();
    _notificationCount = 0;
    
    // 立即发送第一次通知
    _sendPeriodicNotification();
    
    // 每10秒发送一次通知
    _notificationTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _sendPeriodicNotification();
    });
    
    print('🔔 定时通知已启动（每10秒一次，仅Level 1）');
  }
  
  /// 发送定时通知（仅在Level 1时发送）
  void _sendPeriodicNotification() {
    _notificationCount++;
    
    print('🔔 [定时通知] 第 $_notificationCount 次，当前防御等级: Level $_currentDefenseLevel');
    
    // ✅ 只在 Level 1 时发送定时通知
    // Level 2 和 Level 3 只在检测到风险时才发送通知
    if (_currentDefenseLevel == 1) {
      print('🔔 [定时通知] 发送正在检测通知...');
      _notificationService.showLowRiskAlert(
        title: '🛡️ 实时监测中',
        message: '正在保护您的通话安全（第 $_notificationCount 次检测）',
        payload: 'periodic_level_1',
      );
      print('🔔 [定时通知] 已发送第 $_notificationCount 次定时通知');
    } else {
      print('🔔 [定时通知] Level $_currentDefenseLevel - 跳过定时通知（仅在检测到风险时提示）');
    }
  }
  
  /// 停止定时通知
  void _stopPeriodicNotifications() {
    _notificationTimer?.cancel();
    _notificationTimer = null;
    _notificationCount = 0;
    print('🔕 定时通知已停止');
  }
  
  /// 清理资源
  Future<void> dispose() async {
    _heartbeatTimer?.cancel();
    _audioSendTimer?.cancel();  // ✅ 清理音频发送定时器
    _videoFrameTimer?.cancel();
    _notificationTimer?.cancel();  // ✅ 清理定时通知
    await _stopAudioRecording();
    await _stopScreenCapture();  // ✅ 停止屏幕截图
    await _stopSpeechRecognition();  // ✅ 停止语音识别
    _stopCallRecording();  // ✅ 停止通话录音（不需要 await，因为是同步方法）
    await _disconnectWebSocket();
    await _speechService.dispose();  // ✅ 清理语音识别服务
    await _stopForegroundService();  // ✅ 停止前台服务
  }
  
  // ============================================================
  // ✅ 前台服务管理
  // ============================================================
  
  /// 初始化前台服务
  Future<void> _initForegroundService() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'realtime_detection_channel',
        channelName: '实时监测服务',
        channelDescription: '保持实时监测功能在后台运行',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), // 每 5 秒触发一次
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }
  
  /// 启动前台服务
  Future<bool> _startForegroundService() async {
    try {
      print('🚀 启动前台服务...');
      
      // 1. 初始化前台服务
      await _initForegroundService();
      
      // 2. 检查并请求通知权限（Android 13+）
      if (await FlutterForegroundTask.isIgnoringBatteryOptimizations == false) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      
      // 3. 启动前台服务（只使用 microphone 类型）
      // ⚠️ 注意：mediaProjection 类型需要在获取权限后才能使用
      final serviceResult = await FlutterForegroundTask.startService(
        notificationTitle: '🛡️ 实时监测中',
        notificationText: '正在保护您的通话安全',
        callback: startCallback,
        // ✅ 暂时只使用 microphone 类型启动服务
        // mediaProjection 会在用户授权后自动生效
      );
      
      // ✅ 使用模式匹配检查结果
      if (serviceResult is ServiceRequestSuccess) {
        print('✅ 前台服务启动成功');
        return true;
      } else {
        print('❌ 前台服务启动失败');
        return false;
      }
    } catch (e) {
      print('❌ 启动前台服务失败: $e');
      return false;
    }
  }
  
  /// 停止前台服务
  Future<void> _stopForegroundService() async {
    try {
      print('🛑 停止前台服务...');
      await FlutterForegroundTask.stopService();
      print('✅ 前台服务已停止');
    } catch (e) {
      print('❌ 停止前台服务失败: $e');
    }
  }
  
  /// 更新前台服务通知
  Future<void> _updateForegroundServiceNotification({
    String? title,
    String? text,
  }) async {
    // ✅ isRunningService 是一个 getter，返回 bool
    final isRunning = await FlutterForegroundTask.isRunningService;
    if (isRunning) {
      FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    }
  }
  
  /// 获取连接状态
  bool get isConnected => _isConnected;
  
  /// 获取音频录制状态
  bool get isRecording => _isAudioRecordingActive;
  
  /// 获取屏幕截图状态
  bool get isScreenCaptureActive => _isScreenCaptureActive;
  
  /// 获取当前通话记录ID
  String? get callRecordId => _callRecordId;
  
  /// 获取当前防御等级
  int get currentDefenseLevel => _currentDefenseLevel;
  
  /// 是否正在进行语音识别
  bool get isSpeechRecognitionActive => _isSpeechRecognitionActive;
  
  /// 应用防御等级（只升不降）
  void _applyDefenseLevel(int targetLevel, Map<String, dynamic> config) {
    // ✅ 防御等级只升不降
    if (targetLevel <= _currentDefenseLevel) {
      print('⚠️ 忽略降级指令: Level $_currentDefenseLevel → Level $targetLevel');
      return;
    }
    
    print('🛡️ 防御升级: Level $_currentDefenseLevel → Level $targetLevel');
    _currentDefenseLevel = targetLevel;
    
    // 通知 UI 防御等级变化
    onDefenseLevelChanged?.call(targetLevel);
    
    // 根据等级应用不同策略
    switch (targetLevel) {
      case 1:
        _applyLevel1(config);
        break;
      case 2:
        _applyLevel2(config);
        break;
      case 3:
        _applyLevel3(config);
        break;
    }
  }
  
  /// Level 1: 正常模式（绿色）
  void _applyLevel1(Map<String, dynamic> config) {
    print('✅ 切换到正常模式');
    
    // 恢复正常检测频率
    _currentVideoFPS = 1.0;
    
    // 重启视频采集（应用新帧率）
    if (_isScreenCaptureActive) {
      _startScreenshotCapture();
    }
    
    onStatusChange?.call('正常监测中');
  }
  
  /// Level 2: 警惕模式（黄色）
  void _applyLevel2(Map<String, dynamic> config) {
    print('⚠️ 切换到警惕模式');
    
    // ✅ 发送中风险警告通知
    final uiMessage = config['ui_message'] ?? '检测到可疑行为，请提高警惕！';
    _notificationService.showMediumRiskAlert(
      title: '⚠️ 中风险警告',
      message: uiMessage,
      payload: 'level_2',
    );
    
    // 提高检测频率
    final videoFps = config['video_fps'];
    if (videoFps != null) {
      _currentVideoFPS = (videoFps is int) ? videoFps.toDouble() : videoFps;
      print('📹 提高视频帧率: $_currentVideoFPS fps');
      
      // 重启视频采集（应用新帧率）
      if (_isScreenCaptureActive) {
        _startScreenshotCapture();
      }
    }
    
    // 开启录音（如果配置要求）
    final enableRecording = config['enable_call_recording'];
    if (enableRecording == true && !_isRecordingCall) {
      _startCallRecording();
    }
    
    onStatusChange?.call('警惕模式 - 已提高检测频率');
  }
  
  /// Level 3: 危险模式（红色）
  void _applyLevel3(Map<String, dynamic> config) {
    print('🚨 切换到危险模式');
    
    // ✅ 发送高风险警告通知（全屏显示）
    final uiMessage = config['ui_message'] ?? '检测到高风险诈骗行为，强烈建议立即挂断！';
    _notificationService.showHighRiskAlert(
      title: '🚨 高风险警告',
      message: uiMessage,
      payload: 'level_3',
    );
    
    // 最高检测频率
    final videoFps = config['video_fps'];
    if (videoFps != null) {
      _currentVideoFPS = (videoFps is int) ? videoFps.toDouble() : videoFps;
      print('📹 最高视频帧率: $_currentVideoFPS fps');
      
      // 重启视频采集（应用新帧率）
      if (_isScreenCaptureActive) {
        _startScreenshotCapture();
      }
    }
    
    // 强制开启录音
    if (!_isRecordingCall) {
      _startCallRecording();
    }
    
    onStatusChange?.call('危险模式 - 强烈建议挂断');
  }
  
  /// 开始通话录音（保存证据）
  void _startCallRecording() {
    if (_isRecordingCall) return;
    
    try {
      print('🎙️ 开始通话录音（保存证据）');
      _isRecordingCall = true;
      // 注意：这里的录音是为了保存证据，与实时检测的录音是分开的
      // 实际实现可能需要另一个录音器实例
    } catch (e) {
      print('❌ 开始通话录音失败: $e');
    }
  }
  
  /// 停止通话录音
  void _stopCallRecording() {
    if (!_isRecordingCall) return;
    
    try {
      print('🎙️ 停止通话录音');
      _isRecordingCall = false;
    } catch (e) {
      print('❌ 停止通话录音失败: $e');
    }
  }
}

  /// ✅ 构建 44 字节的标准 WAV 文件头
  /// 
  /// 参数：
  /// - dataLength: PCM 数据长度（字节）
  /// - sampleRate: 采样率（Hz）
  /// - channels: 声道数（1=单声道，2=立体声）
  Uint8List _buildWavHeader(int dataLength, int sampleRate, int channels) {
    int byteRate = sampleRate * channels * 2; // 16-bit = 2 bytes per sample
    int blockAlign = channels * 2;
    
    var header = ByteData(44);
    
    // RIFF 头
    header.setUint32(0, 0x52494646, Endian.big);      // "RIFF"
    header.setUint32(4, 36 + dataLength, Endian.little); // 文件大小 - 8
    
    // WAVE 头
    header.setUint32(8, 0x57415645, Endian.big);      // "WAVE"
    
    // fmt 子块
    header.setUint32(12, 0x666D7420, Endian.big);     // "fmt "
    header.setUint32(16, 16, Endian.little);          // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little);           // AudioFormat (1 = PCM)
    header.setUint16(22, channels, Endian.little);    // NumChannels
    header.setUint32(24, sampleRate, Endian.little);  // SampleRate
    header.setUint32(28, byteRate, Endian.little);    // ByteRate
    header.setUint16(32, blockAlign, Endian.little);  // BlockAlign
    header.setUint16(34, 16, Endian.little);          // BitsPerSample
    
    // data 子块
    header.setUint32(36, 0x64617461, Endian.big);     // "data"
    header.setUint32(40, dataLength, Endian.little);  // Subchunk2Size
    
    return header.buffer.asUint8List();
  }


// ============================================================
// ✅ 前台服务回调函数（必须是顶层函数）
// ============================================================

/// 前台服务启动回调
/// 
/// 这个函数会在前台服务启动时被调用
/// 注意：这个函数必须是顶层函数，不能是类的成员方法
@pragma('vm:entry-point')
void startCallback() {
  // 初始化前台任务处理器
  FlutterForegroundTask.setTaskHandler(ForegroundTaskHandler());
}
