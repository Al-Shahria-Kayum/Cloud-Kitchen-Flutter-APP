import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'providers/auth_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/kitchen_provider.dart';
import 'providers/rider_provider.dart';
import 'providers/chat_provider.dart';
import 'screens/auth/auth_gate.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();

  // If the user has configured Supabase, initialize it
  final bool isConfigured =
      SupabaseConfig.url != 'https://your-project.supabase.co' &&
      SupabaseConfig.anonKey !=
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.your-anon-key' &&
      SupabaseConfig.url.isNotEmpty &&
      SupabaseConfig.anonKey.isNotEmpty;

  if (isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );
    } catch (e) {
      // Catch initialization errors gracefully
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => KitchenProvider()),
        ChangeNotifierProvider(create: (_) => RiderProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: MyApp(isConfigured: isConfigured),
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool isConfigured;
  const MyApp({super.key, required this.isConfigured});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cloud Kitchen',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: isConfigured
          ? const AuthGate()
          : const ConfigurationRequiredScreen(),
    );
  }
}

class ConfigurationRequiredScreen extends StatelessWidget {
  const ConfigurationRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 32.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.settings_suggest_outlined,
                  size: 80,
                  color: Color(0xFFFF8C00),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Configuration Required',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Welcome to the Cloud Kitchen MVP! To run the application, please set up your Supabase project using these steps:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.8),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: ListView(
                    children: [
                      _buildStepCard(
                        '1',
                        'Create a Supabase Project',
                        'Sign up at supabase.com and create a new free-tier database project.',
                      ),
                      _buildStepCard(
                        '2',
                        'Execute Database Schema',
                        'Open the SQL Editor in Supabase, copy the contents of the generated "supabase_schema.sql" file from this workspace, and click Run.',
                      ),
                      _buildStepCard(
                        '3',
                        'Storage Buckets (automatic)',
                        'The "menu-images" and "avatars" public buckets are created automatically by supabase_schema.sql — no manual dashboard step needed.',
                      ),
                      _buildStepCard(
                        '4',
                        'Add Keys to Flutter Code',
                        'Open "lib/config/supabase_config.dart" and replace the URL and Anon Key placeholders with your project API credentials.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    // Try to hot-restart after updating keys
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please update the credentials in lib/config/supabase_config.dart and save to refresh.',
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'I have updated the keys',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard(String number, String title, String body) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white.withValues(alpha: 0.08),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFFF8C00),
              foregroundColor: Colors.white,
              radius: 14,
              child: Text(
                number,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
