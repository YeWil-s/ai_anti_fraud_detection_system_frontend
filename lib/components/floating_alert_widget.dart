import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 悬浮预警组件
/// 
/// 当家庭成员遭遇高风险诈骗时，在屏幕上显示悬浮警告
/// 特点：
/// - 可以拖动位置
/// - 显示红色闪烁边框
/// - 点击展开详细信息
/// - 一键拨打电话
class FloatingAlertWidget extends StatefulWidget {
  final String victimName;
  final String? victimPhone;
  final String message;
  final String riskLevel;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onCall;

  const FloatingAlertWidget({
    Key? key,
    required this.victimName,
    this.victimPhone,
    required this.message,
    this.riskLevel = 'high',
    this.onTap,
    this.onDismiss,
    this.onCall,
  }) : super(key: key);

  @override
  State<FloatingAlertWidget> createState() => _FloatingAlertWidgetState();
}

class _FloatingAlertWidgetState extends State<FloatingAlertWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  
  bool _isExpanded = false;
  Offset _position = Offset(20, 100); // 初始位置

  @override
  void initState() {
    super.initState();
    
    // 脉冲动画（闪烁效果）
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // 滑入动画
    _slideController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    
    // 延迟一点后滑入
    Future.delayed(Duration(milliseconds: 100), () {
      if (mounted) _slideController.forward();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Color get _riskColor {
    switch (widget.riskLevel) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.orange;
      default:
        return Colors.yellow.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slideController,
      builder: (context, child) {
        return Positioned(
          left: _position.dx,
          top: _position.dy + (1 - _slideController.value) * -100,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _position += details.delta;
                // 限制在屏幕内
                _position = Offset(
                  math.max(0, math.min(_position.dx, 
                    MediaQuery.of(context).size.width - (_isExpanded ? 300 : 180))),
                  math.max(50, math.min(_position.dy, 
                    MediaQuery.of(context).size.height - (_isExpanded ? 200 : 80))),
                );
              });
            },
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
              widget.onTap?.call();
            },
            child: AnimatedContainer(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: _isExpanded ? 300 : 180,
              padding: EdgeInsets.all(_isExpanded ? 16 : 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _riskColor.withOpacity(_pulseAnimation.value),
                  width: _isExpanded ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _riskColor.withOpacity(0.3 * _pulseAnimation.value),
                    blurRadius: 20,
                    spreadRadius: 5,
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

  /// 折叠状态（小图标）
  Widget _buildCollapsedContent() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _riskColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.warning_rounded,
            color: _riskColor,
            size: 24,
          ),
        ),
        SizedBox(width: 8),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '家人预警',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _riskColor,
                ),
              ),
              Text(
                widget.victimName,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 展开状态（详细信息）
  Widget _buildExpandedContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _riskColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_rounded,
                color: _riskColor,
                size: 24,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '家人安全预警',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _riskColor,
                    ),
                  ),
                  Text(
                    '风险等级: ${widget.riskLevel.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            // 关闭按钮
            GestureDetector(
              onTap: widget.onDismiss,
              child: Icon(
                Icons.close,
                color: Colors.grey.shade400,
                size: 20,
              ),
            ),
          ],
        ),
        
        SizedBox(height: 12),
        
        // 受害者信息
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey.shade600),
                  SizedBox(width: 4),
                  Text(
                    '受害者: ${widget.victimName}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (widget.victimPhone != null) ...[
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.phone, size: 16, color: Colors.grey.shade600),
                    SizedBox(width: 4),
                    Text(
                      widget.victimPhone!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        
        SizedBox(height: 12),
        
        // 消息内容
        Text(
          widget.message,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
            height: 1.4,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        
        SizedBox(height: 12),
        
        // 操作按钮
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.onCall,
                icon: Icon(Icons.phone, size: 16),
                label: Text('立即联系'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _riskColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 悬浮预警管理器
/// 
/// 用于在应用全局显示悬浮预警
class FloatingAlertManager {
  static final FloatingAlertManager _instance = FloatingAlertManager._internal();
  factory FloatingAlertManager() => _instance;
  FloatingAlertManager._internal();

  OverlayEntry? _overlayEntry;
  bool _isShowing = false;

  /// 显示悬浮预警
  void show(BuildContext context, {
    required String victimName,
    String? victimPhone,
    required String message,
    String riskLevel = 'high',
    VoidCallback? onTap,
    VoidCallback? onDismiss,
    VoidCallback? onCall,
  }) {
    if (_isShowing) {
      hide();
    }

    _isShowing = true;
    _overlayEntry = OverlayEntry(
      builder: (context) => FloatingAlertWidget(
        victimName: victimName,
        victimPhone: victimPhone,
        message: message,
        riskLevel: riskLevel,
        onTap: onTap,
        onDismiss: () {
          hide();
          onDismiss?.call();
        },
        onCall: onCall,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  /// 隐藏悬浮预警
  void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isShowing = false;
  }

  /// 是否正在显示
  bool get isShowing => _isShowing;
}
