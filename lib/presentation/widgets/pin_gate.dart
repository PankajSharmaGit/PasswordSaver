import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../screens/pin_lock_screen.dart';

/// Ensures an app PIN exists; if missing, opens create-PIN screen.
///
/// Returns `true` when a PIN is available after this call.
Future<bool> ensureAppPinExists(BuildContext context) async {
  final state = context.read<VaultAppState>();
  final hasPin = await state.ensurePinBeforeAdd();
  if (hasPin) return true;
  if (!context.mounted) return false;

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          const PinLockScreen(forceCreate: true, returnAfterCreate: true),
    ),
  );

  if (!context.mounted) return false;
  return context.read<VaultAppState>().ensurePinBeforeAdd();
}

/// Asks for app PIN. If PIN is not created yet, routes to create PIN first.
///
/// Returns the entered PIN when verified, otherwise `null`.
Future<String?> requirePinToContinue(
  BuildContext context, {
  String title = 'Enter app PIN',
  String subtitle = 'Required to view or change password',
}) async {
  final ready = await ensureAppPinExists(context);
  if (!ready || !context.mounted) return null;

  final pin = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PinKeypadDialog(title: title, subtitle: subtitle),
  );

  if (pin == null || pin.isEmpty || !context.mounted) return null;

  if (pin.length != AppConstants.appPinLength) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'App PIN must be ${AppConstants.appPinLength} digits',
        ),
      ),
    );
    return null;
  }

  final ok = await context.read<VaultAppState>().confirmSensitiveAction(pin);
  if (!ok) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect app PIN')),
      );
    }
    return null;
  }
  return pin;
}

/// On-screen PIN pad. No text field, so the keyboard overlay is not created.
class _PinKeypadDialog extends StatefulWidget {
  const _PinKeypadDialog({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  State<_PinKeypadDialog> createState() => _PinKeypadDialogState();
}

class _PinKeypadDialogState extends State<_PinKeypadDialog> {
  String _entered = '';

  void _digit(String digit) {
    if (_entered.length >= AppConstants.appPinLength) return;
    HapticFeedback.selectionClick();
    final next = _entered + digit;
    if (next.length == AppConstants.appPinLength) {
      Navigator.pop(context, next);
      return;
    }
    setState(() => _entered = next);
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.subtitle, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(AppConstants.appPinLength, (i) {
              final filled = i < _entered.length;
              return Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? AppColors.teal : Colors.transparent,
                  border: Border.all(color: AppColors.teal),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final d in row)
                  _Key(
                    label: d,
                    onTap: () => _digit(d),
                  ),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 64, height: 52),
              _Key(label: '0', onTap: () => _digit('0')),
              SizedBox(
                width: 64,
                height: 52,
                child: IconButton(
                  onPressed: _backspace,
                  icon: const Icon(Icons.backspace_outlined),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 52,
      child: TextButton(
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
