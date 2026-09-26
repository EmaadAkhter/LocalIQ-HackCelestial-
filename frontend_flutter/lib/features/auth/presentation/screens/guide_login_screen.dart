import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data_providers.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/role/user_role.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/auth_service.dart';
import '../widgets/auth_layout.dart';

/// Guide-specific login screen.
///
/// Separate from Explorer login to keep roles clearly partitioned.
/// On success → Guide Dashboard.
class GuideLoginScreen extends ConsumerStatefulWidget {
  const GuideLoginScreen({super.key});

  @override
  ConsumerState<GuideLoginScreen> createState() => _GuideLoginScreenState();
}

class _GuideLoginScreenState extends ConsumerState<GuideLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AuthSession> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      // Ensure guide role is set, then route to dashboard.
      ref.read(userRoleProvider.notifier).setRole(UserRole.guide);
      context.go('/guide/dashboard');
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = toAppException(e).message;
        _busy = false;
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _run(
      () => ref.read(authServiceProvider).signInWithPassword(
            AuthCredentials(
              email: _email.text.trim(),
              password: _password.text,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Guide Sign In',
      subtitle: 'Access your guide dashboard, bookings and availability.',
      footer: Column(
        children: [
          const AuthBackLink(),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () {
              ref.read(userRoleProvider.notifier).setRole(UserRole.explorer);
              context.go('/login');
            },
            icon: const Icon(Icons.switch_account_rounded, size: 15),
            label: const Text('Switch to Explorer login'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textMuted,
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      children: [
        // Guide-specific info banner
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.violet.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.violet.withValues(alpha: 0.20)),
          ),
          child: const Row(
            children: [
              Icon(Icons.person_pin_circle_rounded,
                  size: 18, color: AppColors.violet),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Guide login. You\'ll be taken to your dashboard with bookings, availability and earnings.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.violet,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (_error != null) ...[
          AuthError(message: _error!),
          const SizedBox(height: 14),
        ],

        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Guide Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded, size: 19),
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return 'Email is required';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 19),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 19,
                    ),
                  ),
                ),
                validator: (value) => (value ?? '').length < 4
                    ? 'Use at least 4 characters'
                    : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                    backgroundColor: AppColors.violet,
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Sign in as Guide',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const AuthDivider(label: 'OR'),
        const SizedBox(height: 18),
        GoogleSignInButton(
          label: 'Continue Guide with Google',
          onPressed: _busy
              ? () {}
              : () => _run(
                    () => ref.read(authServiceProvider).signInWithGoogle(),
                  ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Flexible(
              child: Text(
                'New guide?',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.push('/guide-signup'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Apply to be a Guide'),
            ),
          ],
        ),
      ],
    );
  }
}
