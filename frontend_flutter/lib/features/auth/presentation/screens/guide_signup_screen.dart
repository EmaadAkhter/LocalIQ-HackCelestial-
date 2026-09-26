import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/data_providers.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/role/user_role.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/auth_service.dart';
import '../widgets/auth_layout.dart';

/// Guide onboarding / signup screen.
///
/// Collects guide-specific information on top of standard account creation.
class GuideSignupScreen extends ConsumerStatefulWidget {
  const GuideSignupScreen({super.key});

  @override
  ConsumerState<GuideSignupScreen> createState() => _GuideSignupScreenState();
}

class _GuideSignupScreenState extends ConsumerState<GuideSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _city = TextEditingController();
  bool _obscure = true;
  bool _termsAccepted = false;
  bool _busy = false;
  String? _error;

  final _specialties = <String>['Heritage Walks', 'Food Trails', 'Art & Culture',
    'Photography', 'Adventure', 'Spiritual'];
  final _selectedSpecialties = <String>{};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_termsAccepted) {
      setState(() => _error = 'Please accept the guide agreement to continue.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signUp(SignUpRequest(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        termsAccepted: _termsAccepted,
      ));
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Become a Guide',
      subtitle: 'Share your local expertise and earn from experiences you create.',
      footer: const AuthBackLink(),
      children: [
        if (_error != null) ...[
          AuthError(message: _error!),
          const SizedBox(height: 14),
        ],
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline_rounded, size: 19),
                ),
                validator: (v) => (v ?? '').trim().length < 2
                    ? 'Enter your full name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded, size: 19),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Email required';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _city,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Your city / area',
                  prefixIcon: Icon(Icons.location_city_outlined, size: 19),
                ),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your city' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: passwordRequirementHint,
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
                validator: (v) => passwordProblem(v),
              ),
              const SizedBox(height: 16),

              // Specialty selection
              const Text(
                'Specialties (select all that apply)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _specialties.map((s) {
                  final selected = _selectedSpecialties.contains(s);
                  return FilterChip(
                    label: Text(s),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selectedSpecialties.add(s);
                      } else {
                        _selectedSpecialties.remove(s);
                      }
                    }),
                    selectedColor: AppColors.violet.withValues(alpha: 0.15),
                    checkmarkColor: AppColors.violet,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.violet : AppColors.textSecondary,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Terms
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _termsAccepted,
                      onChanged: (v) => setState(() => _termsAccepted = v ?? false),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'I agree to the Guide Agreement and platform policies',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              FilledButton(
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
                        'Create Guide Account',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
