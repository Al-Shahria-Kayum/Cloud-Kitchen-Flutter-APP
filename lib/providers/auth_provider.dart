import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import '../utils/async_guard.dart';

enum AuthStatus { uninitialized, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  User? _user;
  Profile? _profile;
  bool _isLoading = false;
  String? _errorMessage;
  AuthStatus _status = AuthStatus.uninitialized;
  StreamSubscription<List<Map<String, dynamic>>>? _profileSubscription;

  User? get user => _user;
  Profile? get profile => _profile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _user != null;
  AuthStatus get status => _status;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    // Supabase.initialize() has already awaited local session restoration by
    // the time this constructor runs, so currentUser here is reliable.
    _user = _client.auth.currentUser;
    if (_user != null) {
      await fetchProfile();
      _subscribeToProfile();
      _status = AuthStatus.authenticated;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();

    _client.auth.onAuthStateChange.listen((data) {
      final Session? session = data.session;
      _user = session?.user;
      if (_user != null) {
        _status = AuthStatus.authenticated;
        fetchProfile();
        _subscribeToProfile();
      } else {
        _status = AuthStatus.unauthenticated;
        _profile = null;
        _profileSubscription?.cancel();
        _profileSubscription = null;
      }
      notifyListeners();
    });
  }

  Future<void> fetchProfile() async {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return;
    try {
      // Use maybeSingle() so it returns null instead of throwing when 0 rows.
      // Timeout-guarded so a slow network can't hang the app mid-login/restore
      // (null here is a legitimate "no profile row yet" result, not an error,
      // so runGuarded's null-on-failure semantics don't apply — use a plain
      // .timeout() and let the existing catch below handle TimeoutException).
      final data = await _client
          .from('profiles')
          .select()
          .eq('id', currentUser.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (data != null) {
        // Profile exists — load it
        _profile = Profile.fromJson(data);
        _user = currentUser;
        _errorMessage = null;
        notifyListeners();
      } else {
        // Profile row missing (trigger may have failed) — create it now from auth metadata
        final meta = currentUser.userMetadata ?? {};
        final upsertData = {
          'id': currentUser.id,
          'email': currentUser.email ?? '',
          'full_name': meta['full_name'] ?? 'User',
          'role': meta['role'] ?? 'customer',
        };
        await _client.from('profiles').upsert(upsertData);

        // Fetch again after creating
        final created = await _client
            .from('profiles')
            .select()
            .eq('id', currentUser.id)
            .maybeSingle();
        if (created != null) {
          _profile = Profile.fromJson(created);
          _user = currentUser;
          _errorMessage = null;
        } else {
          _errorMessage = 'Failed to create profile. Check database permissions.';
        }
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  void _subscribeToProfile() {
    final currentUser = _client.auth.currentUser;
    if (currentUser == null) return;
    _profileSubscription?.cancel();
    _profileSubscription = _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', currentUser.id)
        .listen((List<Map<String, dynamic>> data) {
          if (data.isNotEmpty) {
            _profile = Profile.fromJson(data.first);
            notifyListeners();
          }
        });
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role, // 'customer', 'kitchen_owner', 'rider'
    String? phone,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'role': role,
        },
      );
      if (response.user != null) {
        // Update the phone if provided
        if (phone != null && phone.isNotEmpty) {
          await _client.from('profiles').update({'phone': phone}).eq('id', response.user!.id);
        }
        _setLoading(false);
        return true;
      }
      _errorMessage = "Signup failed.";
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _setLoading(false);
      return false;
    }
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final response = await _client.auth
          .signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 15));
      if (response.user != null) {
        _user = response.user;
        _status = AuthStatus.authenticated;
        await fetchProfile();
        _setLoading(false);
        return true;
      }
      _errorMessage = "Login failed.";
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      _setLoading(false);
      return false;
    }
  }

  Future<void> logout() async {
    await _client.auth.signOut();
  }

  /// Uploads a new profile picture to the (already-owner-scoped) `avatars`
  /// storage bucket and saves the resulting URL on the user's profile row.
  /// Uses a unique, timestamp-based path per upload so replacing a photo
  /// always produces a fresh URL — otherwise CachedNetworkImage would keep
  /// serving the old cached bytes under the same URL key after a replace.
  ///
  /// On Flutter Web, `uploadBinary()`'s Future can fail to resolve even
  /// though the request completed successfully server-side. Rather than
  /// blindly retry (which just creates duplicate objects while the caller
  /// still never gets an answer), a timeout falls through to checking
  /// whether the object actually landed in storage before reporting failure.
  Future<bool> uploadAndSetAvatar(Uint8List imageBytes, String fileName) async {
    if (_user == null) return false;
    final ext = fileName.contains('.') ? fileName.split('.').last : 'jpg';
    final unique = DateTime.now().microsecondsSinceEpoch;
    final String objectName = '$unique.$ext';
    final String path = '${_user!.id}/$objectName';

    String? publicUrl;
    try {
      await _client.storage
          .from('avatars')
          .uploadBinary(path, imageBytes, fileOptions: const FileOptions(cacheControl: '3600', upsert: true))
          .timeout(const Duration(seconds: 10));
      publicUrl = _client.storage.from('avatars').getPublicUrl(path);
    } on TimeoutException {
      final files = await _client.storage.from('avatars').list(path: _user!.id);
      if (files.any((f) => f.name == objectName)) {
        publicUrl = _client.storage.from('avatars').getPublicUrl(path);
      } else {
        _errorMessage = 'Image upload timed out. Please try again.';
      }
    } catch (e) {
      _errorMessage = e.toString();
    }
    if (publicUrl == null) {
      notifyListeners();
      return false;
    }

    final updated = await runGuarded(
      () => _client.from('profiles').update({'avatar_url': publicUrl}).eq('id', _user!.id),
      onError: (e) => _errorMessage = e.toString(),
    );
    if (updated == null) {
      notifyListeners();
      return false;
    }

    // The live profiles stream (_subscribeToProfile) will also pick this up,
    // but update the local copy immediately so the UI reflects it without
    // waiting on the realtime round-trip.
    if (_profile != null) {
      _profile = _profile!.copyWith(avatarUrl: publicUrl);
    }
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  /// Saves the current user's own personal bKash number — used by all three
  /// roles: customers send payment to the kitchen owner's number, kitchen
  /// owners send rider payouts to the rider's number, and this is the one
  /// place each of them sets/updates the number stored on their profile.
  Future<bool> updateBkashNumber(String? bkashNumber) async {
    if (_user == null) return false;
    final normalized = (bkashNumber == null || bkashNumber.trim().isEmpty) ? null : bkashNumber.trim();
    try {
      await _client.from('profiles').update({'bkash_number': normalized}).eq('id', _user!.id);
      // copyWith can't express "set to null" (its ?? pattern keeps the old
      // value), so rebuild directly rather than risk showing a stale number
      // in the moment before the live profile stream corrects it.
      if (_profile != null) {
        final p = _profile!;
        _profile = Profile(
          id: p.id,
          email: p.email,
          fullName: p.fullName,
          role: p.role,
          phone: p.phone,
          bkashNumber: normalized,
          avatarUrl: p.avatarUrl,
          latitude: p.latitude,
          longitude: p.longitude,
          createdAt: p.createdAt,
        );
      }
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProfileLocation(double lat, double lng) async {
    if (_user == null) return false;
    try {
      await _client.from('profiles').update({
        'latitude': lat,
        'longitude': lng,
      }).eq('id', _user!.id);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }
}
