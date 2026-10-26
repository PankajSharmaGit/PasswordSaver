import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';
import 'pin_lock_screen.dart';

/// Two-factor recovery for lost email/device or forgotten PIN (requirement 11).
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _emailCtrl = TextEditingController();
  final _primaryCtrl = TextEditingController();
  final _secondaryCtrl = TextEditingController();
  final _oldPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _primaryCtrl.dispose();
    _secondaryCtrl.dispose();
    _oldPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_newPinCtrl.text.length != AppConstants.appPinLength ||
        _confirmCtrl.text.length != AppConstants.appPinLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'App PIN must be ${AppConstants.appPinLength} digits',
          ),
        ),
      );
      return;
    }
    if (_newPinCtrl.text != _confirmCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New PINs do not match')),
      );
      return;
    }
    final state = context.read<VaultAppState>();
    final ok = await state.recoverAndResetPin(
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      primaryMobile:
          _primaryCtrl.text.trim().isEmpty ? null : _primaryCtrl.text.trim(),
      secondaryMobile: _secondaryCtrl.text.trim().isEmpty
          ? null
          : _secondaryCtrl.text.trim(),
      rememberedPin:
          _oldPinCtrl.text.trim().isEmpty ? null : _oldPinCtrl.text.trim(),
      newPin: _newPinCtrl.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN reset successfully')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PinLockScreen()),
        (_) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.errorMessage ?? 'Recovery failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<VaultAppState>().isLoading;

    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Text(
                  'Two-way recovery',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Provide any two: login email, recovery mobile, recovery email, or remembered app PIN. Then set a new PIN.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Login email (if remembered)',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _primaryCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Recovery mobile number',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _secondaryCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Recovery email id',
                    prefixIcon: Icon(Icons.mark_email_read_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _oldPinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(AppConstants.appPinLength),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'App PIN (if remembered)',
                    prefixIcon: Icon(Icons.pin_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'New app PIN',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _newPinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(AppConstants.appPinLength),
                  ],
                  decoration: InputDecoration(
                    labelText:
                        'New PIN (${AppConstants.appPinLength} digits)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(AppConstants.appPinLength),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Confirm new PIN',
                  ),
                ),
                const SizedBox(height: 28),
                VaultButton(
                  label: 'Verify & reset PIN',
                  loading: loading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
