import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

/// Validates a Bangladeshi mobile number in the shape bKash expects:
/// 11 digits starting with 01 (e.g. 01812345678), optionally written with a
/// +880/880 country code, which this normalizes away before saving.
String? _normalizeBdNumber(String raw) {
  final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
  String candidate = digitsOnly;
  if (candidate.startsWith('880')) candidate = candidate.substring(3);
  if (candidate.length == 11 && candidate.startsWith('01')) return candidate;
  return null;
}

/// Bottom sheet for viewing/editing the current user's own personal bKash
/// number — the one place all three roles (customer, kitchen owner, rider)
/// manage it. Shared across their dashboards so the editing UX is identical.
Future<void> showBkashNumberSheet(BuildContext context) {
  final authProvider = Provider.of<AuthProvider>(context, listen: false);
  final controller = TextEditingController(text: authProvider.profile?.bkashNumber ?? '');

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: _BkashNumberForm(controller: controller),
      );
    },
  );
}

class _BkashNumberForm extends StatefulWidget {
  final TextEditingController controller;
  const _BkashNumberForm({required this.controller});

  @override
  State<_BkashNumberForm> createState() => _BkashNumberFormState();
}

class _BkashNumberFormState extends State<_BkashNumberForm> {
  bool _isSaving = false;
  String? _errorText;

  Future<void> _save() async {
    final raw = widget.controller.text.trim();

    if (raw.isEmpty) {
      // Explicitly clearing the number is allowed.
      setState(() => _isSaving = true);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.updateBkashNumber(null);
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (success) {
        Navigator.pop(context);
      } else {
        setState(() => _errorText = 'Could not save. Please try again.');
      }
      return;
    }

    final normalized = _normalizeBdNumber(raw);
    if (normalized == null) {
      setState(() => _errorText = 'Enter a valid 11-digit bKash number, e.g. 01812345678.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.updateBkashNumber(normalized);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() => _errorText = 'Could not save. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(color: scheme.outline, borderRadius: AppRadius.pillBr),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                  child: Icon(Icons.smartphone_rounded, color: scheme.onPrimaryContainer, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text('Your bKash number', style: text.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This is kept private and is only shown to the other side of a '
              'transaction when it becomes relevant (e.g. a customer sees '
              'your number once their order is ready to pay for).',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: widget.controller,
              keyboardType: TextInputType.phone,
              maxLength: 14,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
              decoration: InputDecoration(
                labelText: 'bKash number',
                hintText: '01812345678',
                prefixIcon: const Icon(Icons.payments_outlined),
                errorText: _errorText,
              ),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
