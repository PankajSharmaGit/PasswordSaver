import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/profile/recovery_otp_functions.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/string_formatters.dart';
import '../../domain/entities/entities.dart';
import '../providers/app_state.dart';
import '../widgets/common_widgets.dart';

/// Edit name + recovery mobile / recovery email, then OTP-verify if needed.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _mobileCtrl;
  late final TextEditingController _emailCtrl;
  bool _saving = false;

  String _countryLabel(AppUser? user) {
    final name = user?.countryName?.trim();
    final code = user?.countryCode?.trim().toUpperCase();
    if (name != null && name.isNotEmpty) {
      if (code != null && code.isNotEmpty) return '$name ($code)';
      return name;
    }
    if (code != null && code.isNotEmpty) return code;
    return 'Not selected';
  }

  @override
  void initState() {
    super.initState();
    final user = context.read<VaultAppState>().user;
    _nameCtrl = TextEditingController(text: user?.displayName ?? '');
    _mobileCtrl = TextEditingController(text: user?.primaryMobile ?? '');
    _emailCtrl = TextEditingController(text: user?.recoveryEmail ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<VaultAppState>();
    final user = state.user;
    if (user == null) return;

    final name = StringFormatters.toTitleCase(_nameCtrl.text.trim());
    final mobile = _mobileCtrl.text.trim();
    final recoveryEmail = _emailCtrl.text.trim();

    setState(() => _saving = true);
    try {
      final ok = await state.updateUserProfile(
        displayName: name,
        recoveryMobile: mobile.isEmpty ? null : mobile,
        recoveryEmail: recoveryEmail.isEmpty ? null : recoveryEmail,
      );
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.errorMessage ?? 'Update failed')),
        );
        return;
      }

      final updated = state.user!;
      final needMobile = (updated.primaryMobile ?? '').isNotEmpty &&
          !updated.primaryMobileVerified;
      final needEmail = (updated.recoveryEmail ?? '').isNotEmpty &&
          !updated.recoveryEmailVerified;

      if (needMobile) {
        final verified = await _verifyChannel(
          channel: 'mobile',
          target: updated.primaryMobile!,
          title: 'Verify recovery mobile',
        );
        if (!mounted) return;
        if (!verified) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile saved. Recovery mobile not verified yet.'),
            ),
          );
        }
      }

      if (needEmail) {
        final verified = await _verifyChannel(
          channel: 'email',
          target: updated.recoveryEmail!,
          title: 'Verify recovery email',
        );
        if (!mounted) return;
        if (!verified) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile saved. Recovery email not verified yet.'),
            ),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _verifyChannel({
    required String channel,
    required String target,
    required String title,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OtpVerifySheet(
        channel: channel,
        target: target,
        title: title,
      ),
    );
    if (result == true && mounted) {
      await context.read<VaultAppState>().refreshUserProfile();
    }
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<VaultAppState>().user;

    return Scaffold(
      body: VaultBackground(
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Edit profile',
                        style: Theme.of(context).textTheme.displayMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().length < 2) ? 'Enter name' : null,
                ),
                const SizedBox(height: 14),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Country',
                    prefixIcon: Icon(Icons.public_outlined),
                    helperText: 'Set once at login — contact support to change',
                  ),
                  child: Text(
                    _countryLabel(user),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _mobileCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Recovery mobile number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    suffixIcon: user?.isRecoveryMobileVerified == true
                        ? Icon(Icons.verified, color: AppColors.teal)
                        : null,
                    helperText: user?.isRecoveryMobileVerified == true
                        ? 'Verified'
                        : 'Will verify via OTP on Done',
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null;
                    if (t.replaceAll(RegExp(r'\D'), '').length < 10) {
                      return 'Enter a valid mobile number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Recovery email id',
                    prefixIcon: const Icon(Icons.mark_email_read_outlined),
                    suffixIcon: user?.isRecoveryEmailVerified == true
                        ? Icon(Icons.verified, color: AppColors.teal)
                        : null,
                    helperText: user?.isRecoveryEmailVerified == true
                        ? 'Verified'
                        : 'Will verify via OTP on Done',
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return null;
                    if (!t.contains('@') || !t.contains('.')) {
                      return 'Enter a valid recovery email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                VaultButton(
                  label: 'Done',
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OtpVerifySheet extends StatefulWidget {
  const _OtpVerifySheet({
    required this.channel,
    required this.target,
    required this.title,
  });

  final String channel;
  final String target;
  final String title;

  @override
  State<_OtpVerifySheet> createState() => _OtpVerifySheetState();
}

class _OtpVerifySheetState extends State<_OtpVerifySheet> {
  final _otpCtrl = TextEditingController();
  final _otpApi = RecoveryOtpFunctions();
  bool _sending = false;
  bool _verifying = false;
  String? _debugOtp;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await _otpApi.sendOtp(
        channel: widget.channel,
        target: widget.target,
      );
      if (!mounted) return;
      setState(() {
        _debugOtp = result.debugOtp;
        if (result.debugOtp != null && result.debugOtp!.isNotEmpty) {
          _otpCtrl.text = result.debugOtp!;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'Enter the 6-digit OTP');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await _otpApi.verifyOtp(
        channel: widget.channel,
        target: widget.target,
        otp: otp,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final dest = widget.channel == 'mobile' ? 'mobile' : 'email';

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'OTP sent to $dest: ${widget.target}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (_debugOtp != null) ...[
              const SizedBox(height: 8),
              Text(
                'Test OTP: $_debugOtp',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: '6-digit OTP',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: AppColors.coral, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 16),
            VaultButton(
              label: 'Verify OTP',
              loading: _verifying || _sending,
              onPressed: (_verifying || _sending) ? null : _verify,
            ),
            TextButton(
              onPressed: (_sending || _verifying) ? null : _send,
              child: Text(_sending ? 'Sending…' : 'Resend OTP'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}
