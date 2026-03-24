import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ai_anti_fraud_detection_system_frontend/services/RealTimeDetectionService.dart';

/// 家庭预警管理器
/// 
/// 功能：
/// 1. 监听家庭预警消息（family_alert / emergency_alert）
/// 2. 后台常驻，即使 App 在后台也能接收预警
/// 3. 根据风险等级显示不同级别的警告（toast / popup / fullscreen）
/// 4. 震动/响铃提醒
/// 5. 一键拨打电话
class FamilyAlertManager {
  static final FamilyAlertManager _instance = FamilyAlertManager._internal();
  factory FamilyAlertManager() => _instance;
  FamilyAlertManager._internal();

  // 预警状态流
  final _alertStreamController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get alertStream => _alertStreamController.stream;

  // 是否正在显示警告
  bool _isShowingAlert = false;

  // 震动间隔（毫秒）
  static const int _vibrateInterval = 1000;
  Timer? _vibrateTimer;

  /// 初始化并监听 WebSocket 消息
  void initialize(RealTimeDetectionService detectionService) {
    // 监听家庭预警
    detectionService.onFamilyAlert = (alertData) {
      _handleFamilyAlert(alertData);
    };

    // 监听紧急报警
    detectionService.onEmergencyAlert = (alertData) {
      _handleEmergencyAlert(alertData);
    };

    print('✅ 家庭预警管理器已初始化');
  }

  /// 处理家庭预警
  void _handleFamilyAlert(Map<String, dynamic> alertData) {
    print('🚨 FamilyAlertManager 收到家庭预警');
    
    // 发送到流
    _alertStreamController.add(alertData);
    
    // 根据动作执行震动/响铃
    final action = alertData['action'] ?? 'none';
    if (action == 'vibrate') {
      _startVibrate();
    } else if (action == 'alarm') {
      _startAlarm();
    }
  }

  /// 处理紧急报警
  void _handleEmergencyAlert(Map<String, dynamic> alertData) {
    print('🆘 FamilyAlertManager 收到紧急报警');
    
    // 发送到流
    _alertStreamController.add(alertData);
    
    // 紧急报警始终响铃 + 震动
    _startAlarm();
  }

  /// 开始震动
  void _startVibrate() {
    _stopVibrate();
    
    // 立即震动一次
    HapticFeedback.heavyImpact();
    
    // 定时震动
    _vibrateTimer = Timer.periodic(Duration(milliseconds: _vibrateInterval), (_) {
      HapticFeedback.heavyImpact();
    });
    
    // 5秒后自动停止
    Timer(Duration(seconds: 5), _stopVibrate);
  }

  /// 开始响铃（震动 + 系统提示音）
  void _startAlarm() {
    _stopVibrate();
    
    // 立即震动
    HapticFeedback.heavyImpact();
    
    // 更频繁的震动（每500ms）
    _vibrateTimer = Timer.periodic(Duration(milliseconds: 500), (_) {
      HapticFeedback.heavyImpact();
      // 同时触发轻震动
      HapticFeedback.lightImpact();
    });
    
    // 10秒后自动停止
    Timer(Duration(seconds: 10), _stopVibrate);
  }

  /// 停止震动
  void _stopVibrate() {
    _vibrateTimer?.cancel();
    _vibrateTimer = null;
  }

  /// 一键拨打电话
  Future<bool> makeEmergencyCall(String phoneNumber) async {
    if (phoneNumber.isEmpty) {
      print('❌ 电话号码为空');
      return false;
    }
    
    final uri = Uri.parse('tel:$phoneNumber');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return true;
      } else {
        print('❌ 无法拨打电话: $phoneNumber');
        return false;
      }
    } catch (e) {
      print('❌ 拨打电话失败: $e');
      return false;
    }
  }

  /// 显示全屏警告（用于 Level 3）
  void showFullScreenAlert(
    BuildContext context, 
    Map<String, dynamic> alertData,
    {VoidCallback? onDismiss}
  ) {
    if (_isShowingAlert) return;
    _isShowingAlert = true;

    final String title = alertData['title'] ?? '家人安全预警';
    final String message = alertData['message'] ?? '';
    final String victimName = alertData['victim_name'] ?? '未知';
    final String? victimPhone = alertData['victim_phone'];
    final String riskLevel = alertData['risk_level'] ?? 'high';

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) => WillPopScope(
        onWillPop: () async => false, // 禁止返回键关闭
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.red.shade700,
                  Colors.red.shade900,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 警告图标
                    Icon(
                      Icons.warning_rounded,
                      color: Colors.white,
                      size: 80,
                    ),
                    SizedBox(height: 24),
                    
                    // 标题
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 16),
                    
                    // 风险等级标签
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        '风险等级: ${riskLevel.toUpperCase()}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    
                    // 消息内容
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '家人 "$victimName" 正在遭遇诈骗！',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 12),
                          Text(
                            message,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 32),
                    
                    // 一键拨打电话按钮
                    if (victimPhone != null && victimPhone.isNotEmpty)
                      ElevatedButton.icon(
                        onPressed: () {
                          makeEmergencyCall(victimPhone);
                        },
                        icon: Icon(Icons.phone, size: 24),
                        label: Text(
                          '立即拨打 $victimPhone',
                          style: TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.red.shade700,
                          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    SizedBox(height: 16),
                    
                    // 我知道了按钮
                    TextButton(
                      onPressed: () {
                        _stopVibrate();
                        _isShowingAlert = false;
                        Navigator.of(context).pop();
                        onDismiss?.call();
                      },
                      child: Text(
                        '我知道了',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 显示弹窗警告（用于 Level 2）
  void showPopupAlert(
    BuildContext context,
    Map<String, dynamic> alertData,
    {VoidCallback? onDismiss}
  ) {
    final String title = alertData['title'] ?? '家人安全预警';
    final String message = alertData['message'] ?? '';
    final String victimName = alertData['victim_name'] ?? '未知';
    final String? victimPhone = alertData['victim_phone'];

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('家人 "$victimName" 疑似遭遇诈骗'),
            SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _stopVibrate();
              Navigator.of(context).pop();
              onDismiss?.call();
            },
            child: Text('稍后处理'),
          ),
          if (victimPhone != null && victimPhone.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () {
                makeEmergencyCall(victimPhone);
              },
              icon: Icon(Icons.phone, size: 18),
              label: Text('联系家人'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  /// 根据显示模式显示相应警告
  void showAlertByDisplayMode(
    BuildContext context,
    Map<String, dynamic> alertData,
    {VoidCallback? onDismiss}
  ) {
    final String displayMode = alertData['display_mode'] ?? 'popup';
    
    switch (displayMode) {
      case 'fullscreen':
        showFullScreenAlert(context, alertData, onDismiss: onDismiss);
        break;
      case 'popup':
        showPopupAlert(context, alertData, onDismiss: onDismiss);
        break;
      case 'toast':
        // Toast 由调用方处理
        break;
      default:
        showPopupAlert(context, alertData, onDismiss: onDismiss);
    }
  }

  /// 清理资源
  void dispose() {
    _stopVibrate();
    _alertStreamController.close();
  }
}
