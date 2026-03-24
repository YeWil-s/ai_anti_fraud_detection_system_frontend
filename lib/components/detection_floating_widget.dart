import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 检测状态常驻悬浮窗
/// 
/// 功能：
/// - 开启检测后一直显示在屏幕上
/// - 可拖动位置
/// - 显示当前检测状态
/// - 集成一键报警按钮
/// - 实时风险提醒
class DetectionFloatingWidget extends StatefulWidget {
  final bool isMonitoring;
  final int defenseLevel;
  final String? callRecordId;
  final VoidCallback? onEmergencyTap;
  final VoidCallback? onExpandTap;

  const DetectionFloatingWidget({
    Key? key,
    required this.isMonitoring,
    this.defenseLevel = 1,
    this.callRecordId,
    this.onEmergencyTap,
    this.onExpandTap,
  }) : super(key: key);

  @override
  State<DetectionFloatingWidget> createState() => _DetectionFloatingWidgetState();
}

class _DetectionFloatingWidgetState extends State<DetectionFloatingWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  bool _isExpanded = false;
  Offset _position = Offset(20, 120); // 初始位置

  @override
  void initState() {
    super.initState();
    
    // 脉冲动画（闪烁效果）
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // 根据防御等级决定是否启动脉冲
    if (widget.defenseLevel >= 2) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant DetectionFloatingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 防御等级变化时更新动画
    if (widget.defenseLevel >= 2 && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (widget.defenseLevel < 2 && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _statusColor {
    if (!widget.isMonitoring) return Colors.grey;
    switch (widget.defenseLevel) {
      case 1:
        return Color(0xFF10B981); // 绿色
      case 2:
        return Color(0xFFF59E0B); // 橙色
      case 3:
        return Color(0xFFEF4444); // 红色
      default:
        return Colors.grey;
    }
  }

  String get _statusText {
    if (!widget.isMonitoring) return '未监测';
    switch (widget.defenseLevel) {
      case 1:
        return '安全';
      case 2:
        return '警惕';
      case 3:
        return '危险';
      default:
        return '监测中';
    }
  }

  IconData get _statusIcon {
    if (!widget.isMonitoring) return Icons.radar;
    switch (widget.defenseLevel) {
      case 1:
        return Icons.shield;
      case 2:
        return Icons.warning_amber;
      case 3:
        return Icons.emergency;
      default:
        return Icons.radar;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isMonitoring) return SizedBox.shrink();
    
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Positioned(
          left: _position.dx,
          top: _position.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _position += details.delta;
                // 限制在屏幕内
                _position = Offset(
                  math.max(0, math.min(_position.dx, 
                    MediaQuery.of(context).size.width - (_isExpanded ? 200 : 70))),
                  math.max(50, math.min(_position.dy, 
                    MediaQuery.of(context).size.height - (_isExpanded ? 180 : 70))),
                );
              });
            },
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
              if (_isExpanded) {
                widget.onExpandTap?.call();
              }
            },
            child: AnimatedContainer(
              duration: Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: _isExpanded ? 180 : 64,
              height: _isExpanded ? null : 64,
              padding: EdgeInsets.all(_isExpanded ? 12 : 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_isExpanded ? 16 : 32),
                border: Border.all(
                  color: _statusColor.withOpacity(
                    widget.defenseLevel >= 2 ? _pulseAnimation.value : 0.8
                  ),
                  width: widget.defenseLevel >= 2 ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _statusColor.withOpacity(
                      widget.defenseLevel >= 2 ? 0.4 * _pulseAnimation.value : 0.2
                    ),
                    blurRadius: widget.defenseLevel >= 2 ? 15 : 8,
                    spreadRadius: widget.defenseLevel >= 2 ? 3 : 1,
                  ),
                ],
              ),
              child: _isExpanded ? _buildExpandedContent() : _buildCollapsedContent(),
            ),
          ),
        );
      },
    );
  }

  /// 折叠状态（圆形图标）
  Widget _buildCollapsedContent() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _statusColor.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        _statusIcon,
        color: _statusColor,
        size: 28,
      ),
    );
  }

  /// 展开状态（详细信息 + 一键报警）
  Widget _buildExpandedContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 状态图标和文字
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _statusIcon,
                color: _statusColor,
                size: 24,
              ),
            ),
            SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '实时监测',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  _statusText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _statusColor,
                  ),
                ),
              ],
            ),
          ],
        ),
        
        SizedBox(height: 12),
        
        // 分隔线
        Divider(height: 1, color: Colors.grey.shade200),
        
        SizedBox(height: 12),
        
        // 一键报警按钮
        GestureDetector(
          onTap: widget.onEmergencyTap,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFDC2626),
                  Color(0xFFB91C1C),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFFDC2626).withOpacity(0.3),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.emergency,
                  color: Colors.white,
                  size: 16,
                ),
                SizedBox(width: 4),
                Text(
                  '一键报警',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 检测悬浮窗管理器
class DetectionFloatingManager {
  static final DetectionFloatingManager _instance = DetectionFloatingManager._internal();
  factory DetectionFloatingManager() => _instance;
  DetectionFloatingManager._internal();

  OverlayEntry? _overlayEntry;
  bool _isShowing = false;

  /// 显示检测悬浮窗
  void show(
    BuildContext context, {
    required bool isMonitoring,
    int defenseLevel = 1,
    String? callRecordId,
    VoidCallback? onEmergencyTap,
    VoidCallback? onExpandTap,
  }) {
    // 如果已经在显示，先移除旧的
    if (_isShowing) {
      hide();
    }

    if (!isMonitoring) return;

    _isShowing = true;
    _overlayEntry = OverlayEntry(
      builder: (context) => DetectionFloatingWidget(
        isMonitoring: isMonitoring,
        defenseLevel: defenseLevel,
        callRecordId: callRecordId,
        onEmergencyTap: onEmergencyTap,
        onExpandTap: onExpandTap,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  /// 更新悬浮窗状态
  void update({
    required bool isMonitoring,
    int defenseLevel = 1,
    String? callRecordId,
    VoidCallback? onEmergencyTap,
    VoidCallback? onExpandTap,
  }) {
    if (!_isShowing) return;
    
    // 移除旧的
    _overlayEntry?.remove();
    
    if (!isMonitoring) {
      _isShowing = false;
      _overlayEntry = null;
      return;
    }

    // 插入新的
    _overlayEntry = OverlayEntry(
      builder: (context) => DetectionFloatingWidget(
        isMonitoring: isMonitoring,
        defenseLevel: defenseLevel,
        callRecordId: callRecordId,
        onEmergencyTap: onEmergencyTap,
        onExpandTap: onExpandTap,
      ),
    );

    // 使用 context 获取 Overlay
    // 注意：这里需要在调用时传入有效的 context
  }

  /// 隐藏悬浮窗
  void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isShowing = false;
  }

  /// 是否正在显示
  bool get isShowing => _isShowing;
}
