import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';

/// Full-screen gate that asks for system device lock (PIN/pattern/fingerprint).
class DeviceLockGateScreen extends StatefulWidget {
  const DeviceLockGateScreen({
    super.key,
    required this.onUnlocked,
    this.title = 'Device lock required',
    this.subtitle =
        'Use your phone PIN, pattern, fingerprint, or face to continue',
  });

  final VoidCallback onUnlocked;
  final String title;
  final String subtitle;

  @override
  State<DeviceLockGateScreen> createState() => _DeviceLockGateScreenState();
}

class _DeviceLockGateScreenState extends State<DeviceLockGateScreen> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await context.read<VaultAppState>().verifyDeviceLock();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _error = 'Verification failed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                const VaultLogo(size: 72),
                const SizedBox(height: 24),
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.coral),
                    textAlign: TextAlign.center,
                  ),
                ],
                const Spacer(),
                VaultButton(
                  label: _busy ? 'Verifying…' : 'Unlock with device',
                  icon: Icons.fingerprint,
                  loading: _busy,
                  onPressed: _busy ? null : _unlock,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
