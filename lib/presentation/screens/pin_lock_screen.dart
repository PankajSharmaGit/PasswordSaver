import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/navigation/vault_routes.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';
import 'recovery_screen.dart';

/// App PIN gate — required every launch (requirement 9).
class PinLockScreen extends StatefulWidget {
  const PinLockScreen({
    super.key,
    this.forceCreate = false,
    this.returnAfterCreate = false,
  });

  final bool forceCreate;

  /// When true, pops back after PIN is created instead of going to MainShell.
  final bool returnAfterCreate;

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen>
    with SingleTickerProviderStateMixin {
  String _entered = '';
  /// Create-PIN flow: false = enter new PIN, true = confirm PIN.
  bool _confirmingCreate = false;
  String _pendingCreatePin = '';
  bool _busy = false;
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _onDigit(String digit) async {
    if (_busy || _entered.length >= AppConstants.appPinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _entered += digit);
    if (_entered.length == AppConstants.appPinLength) {
      if (widget.forceCreate) {
        await _onCreatePinComplete();
      } else {
        await _unlock();
      }
    }
  }

  void _backspace() {
    if (_busy || _entered.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _onCreatePinComplete() async {
    if (!_confirmingCreate) {
      setState(() {
        _pendingCreatePin = _entered;
        _entered = '';
        _confirmingCreate = true;
      });
      return;
    }

    if (_entered != _pendingCreatePin) {
      HapticFeedback.heavyImpact();
      await _shakeCtrl.forward(from: 0);
      if (!mounted) return;
      setState(() {
        _entered = '';
        _pendingCreatePin = '';
        _confirmingCreate = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PINs do not match. Try again.')),
      );
      return;
    }

    setState(() => _busy = true);
    final state = context.read<VaultAppState>();
    final ok = await state.createAppPin(_entered);
    if (!mounted) return;
    if (ok) {
      if (widget.returnAfterCreate) {
        Navigator.of(context).pop(true);
      } else {
        _goHome();
      }
      return;
    }
    setState(() {
      _busy = false;
      _entered = '';
      _pendingCreatePin = '';
      _confirmingCreate = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(state.errorMessage ?? 'Could not create PIN')),
    );
  }

  Future<void> _unlock() async {
    setState(() => _busy = true);
    final state = context.read<VaultAppState>();
    final ok = await state.unlockWithPin(_entered);
    if (!mounted) return;
    if (ok) {
      _goHome();
      return;
    }
    HapticFeedback.heavyImpact();
    await _shakeCtrl.forward(from: 0);
    setState(() {
      _entered = '';
      _busy = false;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(state.errorMessage ?? 'Wrong PIN')),
    );
  }

  Future<void> _biometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await context.read<VaultAppState>().unlockWithBiometric();
    if (!mounted) return;
    if (ok) {
      _goHome();
      return;
    }
    setState(() => _busy = false);
  }

  void _goHome() => openVaultHome(context);

  @override
  Widget build(BuildContext context) {
    if (widget.forceCreate) {
      return _buildCreatePin();
    }
    return _buildUnlock();
  }

  Widget _buildCreatePin() {
    final loading = context.watch<VaultAppState>().isLoading;
    final stepTitle =
        _confirmingCreate ? 'Confirm app PIN' : 'Create app PIN';
    final stepSubtitle = _confirmingCreate
        ? 'Enter the same ${AppConstants.appPinLength} digits again'
        : 'Choose a ${AppConstants.appPinLength}-digit PIN to protect your vault';

    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final short = constraints.maxHeight < 640;
              final keySize = short ? 64.0 : 72.0;
              final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

              return Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  short ? 12 : 28,
                  24,
                  12 + bottomInset,
                ),
                child: Column(
                  children: [
                    if (widget.returnAfterCreate)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: _busy || loading
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          VaultLogo(size: short ? 56 : 68),
                          SizedBox(height: short ? 14 : 22),
                          Text(
                            stepTitle,
                            style: Theme.of(context).textTheme.displayMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            stepSubtitle,
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: short ? 10 : 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _StepDot(active: !_confirmingCreate, label: '1'),
                              Container(
                                width: 28,
                                height: 2,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                color: AppColors.mist,
                              ),
                              _StepDot(active: _confirmingCreate, label: '2'),
                            ],
                          ),
                          SizedBox(height: short ? 20 : 28),
                          AnimatedBuilder(
                            animation: _shakeAnim,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(_shakeAnim.value, 0),
                                child: child,
                              );
                            },
                            child: _PinDots(
                              length: AppConstants.appPinLength,
                              filled: _entered.length,
                              error: _shakeCtrl.isAnimating,
                            ),
                          ),
                          SizedBox(height: short ? 20 : 32),
                          if (loading || _busy)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 16),
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          else
                            _Keypad(
                              keySize: keySize,
                              enabled: !_busy && !loading,
                              onDigit: _onDigit,
                              onBackspace: _backspace,
                            ),
                        ],
                      ),
                    ),
                    if (_confirmingCreate && !_busy && !loading)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _confirmingCreate = false;
                            _pendingCreatePin = '';
                            _entered = '';
                          });
                        },
                        child: Text(
                          'Start over',
                          style: TextStyle(color: AppColors.teal),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildUnlock() {
    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final short = constraints.maxHeight < 640;
              final keySize = short ? 64.0 : 72.0;

              return Padding(
                padding: EdgeInsets.fromLTRB(24, short ? 12 : 28, 24, 12),
                child: Column(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          VaultLogo(size: short ? 64 : 72),
                          SizedBox(height: short ? 18 : 28),
                          Text(
                            'Enter app PIN',
                            style: Theme.of(context).textTheme.displayMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Required every time you open the vault',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: short ? 22 : 32),
                          AnimatedBuilder(
                            animation: _shakeAnim,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(_shakeAnim.value, 0),
                                child: child,
                              );
                            },
                            child: _PinDots(
                              length: AppConstants.appPinLength,
                              filled: _entered.length,
                              error: _shakeCtrl.isAnimating,
                            ),
                          ),
                          SizedBox(height: short ? 22 : 36),
                          if (_busy)
                            const Column(
                              children: [
                                SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                ),
                                SizedBox(height: 14),
                                Text('Unlocking…'),
                              ],
                            )
                          else
                            _Keypad(
                              keySize: keySize,
                              enabled: true,
                              onDigit: _onDigit,
                              onBackspace: _backspace,
                            ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _biometric,
                      icon: Icon(Icons.fingerprint, color: AppColors.teal),
                      label: Text(
                        'Use fingerprint / device lock',
                        style: TextStyle(
                          color: AppColors.teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RecoveryScreen(),
                                ),
                              );
                            },
                      child: Text(
                        'Forgot PIN? Recover access',
                        style: TextStyle(color: AppColors.teal),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.active, required this.label});

  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.teal : Colors.transparent,
        border: Border.all(
          color: active ? AppColors.teal : AppColors.mist,
          width: 1.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: active ? Colors.white : AppColors.slate,
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.length,
    required this.filled,
    required this.error,
  });

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final isFilled = i < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: isFilled ? 16 : 14,
          height: isFilled ? 16 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: error
                ? AppColors.coral
                : isFilled
                    ? AppColors.teal
                    : AppColors.mist.withValues(alpha: 0.45),
            boxShadow: isFilled && !error
                ? [
                    BoxShadow(
                      color: AppColors.teal.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    required this.keySize,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final double keySize;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((k) {
              if (k.isEmpty) {
                return SizedBox(width: keySize, height: keySize);
              }
              final isBackspace = k == '⌫';
              return _KeypadButton(
                label: k,
                size: keySize,
                isBackspace: isBackspace,
                enabled: enabled,
                onTap: () {
                  if (isBackspace) {
                    onBackspace();
                  } else {
                    onDigit(k);
                  }
                },
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    required this.label,
    required this.size,
    required this.onTap,
    required this.isBackspace,
    required this.enabled,
  });

  final String label;
  final double size;
  final VoidCallback onTap;
  final bool isBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.88),
            border: Border.all(
              color: AppColors.mist.withValues(alpha: isDark ? 0.25 : 0.4),
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: AppColors.teal.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Center(
            child: isBackspace
                ? Icon(
                    Icons.backspace_outlined,
                    size: size * 0.34,
                    color: AppColors.ink.withValues(alpha: 0.75),
                  )
                : Text(
                    label,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                  ),
          ),
        ),
      ),
    );
  }
}
