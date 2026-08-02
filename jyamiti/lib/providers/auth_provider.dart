import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _profile;
  bool _isLoading = false;

  bool get isAuthenticated => _token != null;
  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get profile => _profile;
  bool get isLoading => _isLoading;

  String? get userRole => _user != null ? _user!['role'] : null;
  String? get userId => _user != null ? (_user!['id'] ?? _user!['_id']) : null;
  String? get userName => _user != null ? _user!['name'] : null;
  String? get userEmail => _user != null ? _user!['email'] : null;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('auth_token') || !prefs.containsKey('auth_user')) {
      return false;
    }
    _token = prefs.getString('auth_token');
    _user = jsonDecode(prefs.getString('auth_user')!);
    notifyListeners();
    // Fetch fresh profile in background
    fetchProfile();
    return true;
  }

  Future<String?> login(String email, String password) async {
    _setLoading(true);
    try {
      final response = await ApiService.post('/auth/login', {
        'email': email,
        'password': password,
      });

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final user = data['user'];
        if (user != null && (user['isActive'] == false || user['status'] == 'INACTIVE' || user['status'] == 'SUSPENDED')) {
          return 'Your account is deactivated or suspended. Please contact admin.';
        }

        _token = data['token'];
        _user = user;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        await prefs.setString('auth_user', jsonEncode(_user));

        notifyListeners();
        await fetchProfile();
        return null; // success
      } else {
        return data['message'] ?? 'Login failed';
      }
    } catch (e) {
      return 'Network error: please check connection';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchProfile() async {
    if (!isAuthenticated) return;
    try {
      final response = await ApiService.get('/auth/profile');
      if (response.statusCode == 200) {
        final profile = jsonDecode(response.body);
        if (profile != null && (profile['isActive'] == false || profile['status'] == 'INACTIVE' || profile['status'] == 'SUSPENDED')) {
          await logout();
        } else {
          _profile = profile;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    }
  }

  Future<String?> forgotPassword(String email) async {
    _setLoading(true);
    try {
      final response = await ApiService.post('/auth/forgot-password', {'email': email});
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return null; // success
      } else {
        return data['message'] ?? 'Failed to send reset token';
      }
    } catch (e) {
      return 'Network error';
    } finally {
      _setLoading(false);
    }
  }

  Future<String?> resetPassword(String email, String token, String newPassword) async {
    _setLoading(true);
    try {
      final response = await ApiService.post('/auth/reset-password', {
        'email': email,
        'token': token,
        'newPassword': newPassword,
      });
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return null; // success
      } else {
        return data['message'] ?? 'Failed to reset password';
      }
    } catch (e) {
      return 'Network error';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    _profile = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_user');
    notifyListeners();
  }
}
