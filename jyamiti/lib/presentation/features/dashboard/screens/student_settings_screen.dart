import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/theme_provider.dart';

class StudentSettingsScreen extends StatefulWidget {
  final bool isInline;
  const StudentSettingsScreen({super.key, this.isInline = false});

  @override
  State<StudentSettingsScreen> createState() => _StudentSettingsScreenState();
}

class _StudentSettingsScreenState extends State<StudentSettingsScreen> {
  bool _notificationsEnabled = true;
  bool _biometricAuthEnabled = false;
  double _fontSize = 1.0;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: widget.isInline
          ? null
          : AppBar(
              title: Text(
                'Settings',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ).animate().fade().slideY(begin: -0.2, end: 0),
              centerTitle: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: context.textColor),
              actions: [
                IconButton(
                  icon: Icon(Icons.settings_backup_restore, color: context.textColor),
                  onPressed: _resetToDefaults,
                  tooltip: 'Reset to defaults',
                ),
              ],
            ),
      body: Stack(
        children: [
          if (!widget.isInline)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: context.isDark 
                      ? [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF0F172A)]
                      : [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFF1F5F9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProfileHeader().animate().fade(duration: 400.ms).slideY(begin: 0.1, end: 0),
                  SizedBox(height: 32),
                  
                  _buildSectionHeader('App Preferences').animate().fade(delay: 100.ms),
                  _buildSettingCard(
                    icon: Icons.notifications_active_rounded,
                    title: 'Notifications',
                    trailing: Switch(
                      value: _notificationsEnabled,
                      onChanged: (value) => setState(() => _notificationsEnabled = value),
                      activeColor: const Color(0xFF6366F1),
                    ),
                  ).animate().fade(delay: 150.ms),
                  _buildSettingCard(
                    icon: Icons.dark_mode_rounded,
                    title: 'Dark Mode',
                    trailing: Switch(
                      value: themeProvider.isDarkMode,
                      onChanged: (value) {
                        themeProvider.toggleTheme(value);
                      },
                      activeColor: const Color(0xFF6366F1),
                    ),
                  ).animate().fade(delay: 200.ms),
                  _buildSettingCard(
                    icon: Icons.text_fields_rounded,
                    title: 'Font Size',
                    trailing: SizedBox(
                      width: 120,
                      child: Slider(
                        value: _fontSize,
                        min: 0.8,
                        max: 1.5,
                        divisions: 7,
                        label: _fontSize.toStringAsFixed(1),
                        onChanged: (value) => setState(() => _fontSize = value),
                        activeColor: const Color(0xFF6366F1),
                      ),
                    ),
                  ).animate().fade(delay: 250.ms),
                  
                  SizedBox(height: 32),
                  
                  _buildSectionHeader('Security').animate().fade(delay: 300.ms),
                  _buildSettingCard(
                    icon: Icons.fingerprint_rounded,
                    title: 'Biometric Authentication',
                    trailing: Switch(
                      value: _biometricAuthEnabled,
                      onChanged: (value) => setState(() => _biometricAuthEnabled = value),
                      activeColor: const Color(0xFF10B981),
                    ),
                  ).animate().fade(delay: 350.ms),
                  _buildSettingCard(
                    icon: Icons.lock_reset_rounded,
                    title: 'Change Password',
                    trailing: Icon(Icons.chevron_right_rounded, color: context.textColor54),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Change Password coming soon!')),
                      );
                    },
                  ).animate().fade(delay: 400.ms),
                  
                  SizedBox(height: 32),
                  
                  _buildSectionHeader('Support').animate().fade(delay: 450.ms),
                  _buildSettingCard(
                    icon: Icons.help_outline_rounded,
                    title: 'Help Center',
                    trailing: Icon(Icons.chevron_right_rounded, color: context.textColor54),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Help Center coming soon!')),
                      );
                    },
                  ).animate().fade(delay: 500.ms),
                  _buildSettingCard(
                    icon: Icons.feedback_rounded,
                    title: 'Send Feedback',
                    trailing: Icon(Icons.chevron_right_rounded, color: context.textColor54),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Feedback form coming soon!')),
                      );
                    },
                  ).animate().fade(delay: 550.ms),
                  _buildSettingCard(
                    icon: Icons.star_rate_rounded,
                    title: 'Rate the App',
                    trailing: Icon(Icons.chevron_right_rounded, color: context.textColor54),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Redirecting to app store...')),
                      );
                    },
                  ).animate().fade(delay: 600.ms),

                  SizedBox(height: 32),
                  
                  _buildSectionHeader('Legal').animate().fade(delay: 650.ms),
                  _buildSettingCard(
                    icon: Icons.privacy_tip_rounded,
                    title: 'Privacy Policy',
                    trailing: Icon(Icons.chevron_right_rounded, color: context.textColor54),
                    onTap: () => _showLegalDialog('Privacy Policy'),
                  ).animate().fade(delay: 700.ms),
                  _buildSettingCard(
                    icon: Icons.description_rounded,
                    title: 'Terms of Service',
                    trailing: Icon(Icons.chevron_right_rounded, color: context.textColor54),
                    onTap: () => _showLegalDialog('Terms of Service'),
                  ).animate().fade(delay: 750.ms),
                  
                  SizedBox(height: 32),
                  
                  _buildSectionHeader('Account').animate().fade(delay: 800.ms),
                  _buildActionCard(
                    icon: Icons.logout_rounded,
                    title: 'Sign Out',
                    color: Colors.redAccent,
                    onTap: () async {
                      final bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                          title: Text('Confirm Logout', style: TextStyle(color: context.textColor)),
                          content: Text('Are you sure you want to sign out?', style: TextStyle(color: context.textColor70)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: Text('Cancel', style: TextStyle(color: context.textColor60)),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Logout', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && context.mounted) {
                        Provider.of<AuthProvider>(context, listen: false).logout();
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    },
                  ).animate().fade(delay: 850.ms),
                  _buildActionCard(
                    icon: Icons.delete_forever_rounded,
                    title: 'Delete Account',
                    color: Colors.red.shade700,
                    onTap: _confirmAccountDeletion,
                  ).animate().fade(delay: 900.ms),
                  
                  SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: context.textColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final auth = Provider.of<AuthProvider>(context);
    final String name = auth.userName ?? 'Student';
    final String email = auth.userEmail ?? 'student@jyamitimath.com';
    // Dummy stats for the UI display, in real scenario fetch from profile
    final String studentId = auth.profile?['id']?.toString().substring(0, 5) ?? '88291';
    
    return Container(
      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.isDark ? const Color(0xFF6366F1).withOpacity(0.3) : Colors.white.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: context.isDark ? Colors.black.withOpacity(0.2) : const Color(0xFF6366F1).withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.5)),
                      ),
                      child: Icon(
                        Icons.person_rounded,
                        size: 32,
                        color: Color(0xFF818CF8),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: context.textColor,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'ID: $studentId | $email',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.textColor70,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Edit Profile coming soon!')));
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF818CF8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 24),
                Container(height: 1, color: context.glassBorder),
                SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem(value: '92%', label: 'Attendance', icon: Icons.calendar_today_rounded, color: const Color(0xFF10B981)),
                    Container(width: 1, height: 40, color: context.glassBorder),
                    _buildStatItem(value: '85%', label: 'Avg. Score', icon: Icons.bar_chart_rounded, color: const Color(0xFF3B82F6)),
                    Container(width: 1, height: 40, color: context.glassBorder),
                    _buildStatItem(value: '#12', label: 'Rank', icon: Icons.leaderboard_rounded, color: const Color(0xFFF59E0B)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({required String value, required String label, required IconData icon, required Color color}) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textColor,
              ),
            ),
          ],
        ),
        SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: context.textColor60)),
      ],
    );
  }

  Widget _buildSettingCard({required IconData icon, required String title, Widget? trailing, VoidCallback? onTap}) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.isDark ? context.glassBg : Colors.white.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.isDark ? context.glassBorder : Colors.white.withOpacity(0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(context.isDark ? 0.15 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: ListTile(
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.glassBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: context.textColor70, size: 22),
            ),
            title: Text(title, style: TextStyle(color: context.textColor, fontSize: 15)),
            trailing: trailing,
            onTap: onTap,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard({required IconData icon, required String title, required Color color, required VoidCallback onTap}) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.isDark ? color.withOpacity(0.05) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.isDark ? color.withOpacity(0.2) : color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(context.isDark ? 0.05 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: ListTile(
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            title: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
            onTap: onTap,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset Settings', style: TextStyle(color: context.textColor)),
        content: Text('Reset all settings to default values?', style: TextStyle(color: context.textColor70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1)),
            onPressed: () {
              setState(() {
                _notificationsEnabled = true;
                _biometricAuthEnabled = false;
                _fontSize = 1.0;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings reset to defaults'), backgroundColor: Color(0xFF6366F1)),
              );
            },
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showLegalDialog(String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: TextStyle(color: context.textColor)),
        content: SingleChildScrollView(
          child: Text(
            title == 'Privacy Policy' ? _privacyPolicyText : _termsOfServiceText,
            style: TextStyle(height: 1.5, color: context.textColor70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: context.textColor60)),
          ),
        ],
      ),
    );
  }

  void _confirmAccountDeletion() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Account', style: TextStyle(color: Colors.redAccent)),
        content: Text(
          'Are you sure you want to permanently delete your account? This action cannot be undone.',
          style: TextStyle(color: context.textColor70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: context.textColor60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Account deletion request sent to Admin'), backgroundColor: Colors.orange),
              );
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Legal Texts
  static const String _privacyPolicyText = '''
At Jyamiti Learn, we are committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our application.

Information We Collect:
- Personal identification information (Name, email address)
- Academic performance data
- Device information for analytics

How We Use Your Information:
- To provide and maintain our service
- To notify you about changes to our service
- To provide customer support
- To gather analysis for improvements

Data Security:
We implement appropriate technical and organizational measures to maintain the safety of your personal data.
''';

  static const String _termsOfServiceText = '''
By accessing or using the Jyamiti Learn application, you agree to be bound by these Terms of Service.

User Responsibilities:
- You must provide accurate information
- You are responsible for maintaining the confidentiality of your account
- You agree not to distribute exam content or solutions

Intellectual Property:
All content, features, and functionality are and will remain the exclusive property of Jyamiti Learn and its licensors.

Termination:
We may terminate or suspend your account immediately for any violation of these Terms.
''';
}
