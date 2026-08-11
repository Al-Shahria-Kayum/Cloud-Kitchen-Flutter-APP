import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_mapper.dart';
import '../../widgets/app_page_route.dart';
import 'auth_widgets.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedRole = 'customer';
  bool _obscurePassword = true;

  late final AnimationController _entryController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(vsync: this, duration: AppMotion.slow);
    final curved = CurvedAnimation(parent: _entryController, curve: AppMotion.curve);
    _fade = curved;
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved);
    _entryController.forward();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.signUp(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
      fullName: _fullNameController.text.trim(),
      role: _selectedRole,
      phone: _phoneController.text.trim(),
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Signup successful! Check email for confirmation if required, or log in.',
          ),
          backgroundColor: context.appColors.success,
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        appPageRoute(const LoginScreen()),
        (route) => false,
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(authProvider.errorMessage, fallback: 'Signup failed. Please try again.')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthProvider>().isLoading;
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;
    final text = Theme.of(context).textTheme;

    final roleOptions = [
      RoleOption(
        value: 'customer',
        label: 'Customer',
        description: 'Order meals from local kitchens near you.',
        icon: Icons.person_outline,
        color: appColors.mapCustomer,
      ),
      RoleOption(
        value: 'kitchen_owner',
        label: 'Kitchen Owner',
        description: 'List your kitchen and start selling dishes.',
        icon: Icons.storefront_outlined,
        color: appColors.mapKitchen,
      ),
      RoleOption(
        value: 'rider',
        label: 'Rider',
        description: 'Deliver orders nearby and earn on your schedule.',
        icon: Icons.two_wheeler_outlined,
        color: appColors.mapRider,
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          const AuthBackdrop(),
          SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AuthHero(
                        title: 'Join the kitchen',
                        subtitle: 'Create an account to order, cook, or deliver.',
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _fullNameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Full name',
                                    prefixIcon: Icon(Icons.badge_outlined),
                                  ),
                                  validator: (value) => value == null || value.isEmpty
                                      ? 'Enter your name'
                                      : null,
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Phone number',
                                    hintText: '01XXXXXXXXX',
                                    prefixIcon: Icon(Icons.phone_outlined),
                                  ),
                                  validator: (value) {
                                    if (value == null || !RegExp(r'^01[3-9]\d{8}$').hasMatch(value.trim())) {
                                      return 'Enter the right phone number';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Email address',
                                    prefixIcon: Icon(Icons.mail_outline),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Enter email';
                                    }
                                    if (!RegExp(
                                      r'^[^@]+@[^@]+\.[^@]+',
                                    ).hasMatch(value)) {
                                      return 'Enter valid email';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                      tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                      onPressed: () {
                                        setState(() => _obscurePassword = !_obscurePassword);
                                      },
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Enter password';
                                    }
                                    if (value.length < 6) {
                                      return 'At least 6 characters';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: AppSpacing.xl),
                                RoleSelector(
                                  options: roleOptions,
                                  value: _selectedRole,
                                  onChanged: (value) => setState(() => _selectedRole = value),
                                ),
                                const SizedBox(height: AppSpacing.lg),
                                PressableScale(
                                  child: ElevatedButton(
                                    onPressed: isLoading ? null : _handleSignup,
                                    child: isLoading
                                        ? SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: scheme.onPrimary,
                                            ),
                                          )
                                        : const Text('Register'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Already have an account? ', style: text.bodyMedium),
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).pushReplacement(
                                appPageRoute(const LoginScreen()),
                              );
                            },
                            child: Text(
                              'Log in',
                              style: text.bodyMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
          ),
        ],
      ),
    );
  }
}
