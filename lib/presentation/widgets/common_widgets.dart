import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../providers/app_state.dart';

export 'vault_ads.dart';

/// Soft vault gradient background used across advanced UI screens.
class VaultBackground extends StatelessWidget {
  const VaultBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Watch theme so gradient rebuilds when appearance changes
    context.watch<VaultAppState>();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.gradientTop,
            AppColors.gradientMid,
            AppColors.gradientBottom,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _Blob(
              size: 220,
              color: AppColors.mint.withValues(alpha: 0.18),
            ),
          ),
          Positioned(
            bottom: 40,
            left: -50,
            child: _Blob(
              size: 180,
              color: AppColors.amber.withValues(alpha: 0.12),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

/// Primary full-width CTA button.
class VaultButton extends StatelessWidget {
  const VaultButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.isOutlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool isOutlined;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          );

    if (isOutlined) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: loading ? null : onPressed,
          child: child,
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        child: child,
      ),
    );
  }
}

/// Brand mark for splash / auth heroes.
class VaultLogo extends StatelessWidget {
  const VaultLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.forest, AppColors.mint],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.teal.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(Icons.shield_outlined, color: Colors.white, size: size * 0.48),
    );
  }
}

/// Maps platform category to a Material icon.
IconData platformIcon(String iconName) {
  switch (iconName) {
    case 'email':
      return Icons.email_outlined;
    case 'outlook':
      return Icons.mail_outline;
    case 'google':
      return Icons.g_mobiledata_rounded;
    case 'microsoft':
      return Icons.window_outlined;
    case 'chat':
      return Icons.chat_bubble_outline;
    case 'facebook':
      return Icons.facebook;
    case 'camera':
      return Icons.camera_alt_outlined;
    case 'tag':
      return Icons.tag;
    case 'work':
      return Icons.work_outline;
    case 'apple':
      return Icons.apple;
    case 'store':
      return Icons.shop_outlined;
    case 'account_balance':
      return Icons.account_balance_outlined;
    case 'account_balance_gov':
      return Icons.account_balance;
    case 'computer':
      return Icons.computer_outlined;
    case 'phone':
      return Icons.phone_android_outlined;
    case 'tv':
      return Icons.tv_outlined;
    case 'shopping':
      return Icons.shopping_bag_outlined;
    case 'code':
      return Icons.code;
    default:
      return Icons.lock_outline;
  }
}
