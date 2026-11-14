
import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/sign_in_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color navy = Color(0xFF142C3B);
  static const Color darkNavy = Color(0xFF001725);
  static const Color teal = Color(0xFF006B5E);
  static const Color mint = Color(0xFF81F7E1);
  static const Color background = Color(0xFFF7F8F6);
  static const Color border = Color(0xFFE5EAE7);
  static const Color secondary = Color(0xFF73787C);

  // Main profile controllers
  final TextEditingController _nameController =
      TextEditingController();

  final TextEditingController _emailController =
      TextEditingController();

  // Draft controllers remain alive until this screen is disposed.
  final TextEditingController _nameDraftController =
      TextEditingController();

  final TextEditingController _emailDraftController =
      TextEditingController();

  String role = 'Admin';

  bool emailAlerts = true;
  bool reviewAlerts = true;
  bool guidelineAlerts = true;
  bool darkMode = false;
  bool isLoading = true;
  bool isSaving = false;

  TextStyle _style({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color color = darkNavy,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _nameDraftController.dispose();
    _emailDraftController.dispose();
    super.dispose();
  }

  // LOAD PROFILE FROM LOCAL STORAGE

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedName =
          prefs.getString('bg_profile_name') ?? 'Elena Jordan';

      final savedEmail = prefs.getString('bg_profile_email') ??
          'elena.jordan@brandguard.demo';

      final savedRole =
          prefs.getString('bg_profile_role') ?? 'Admin';

      final savedEmailAlerts =
          prefs.getBool('bg_profile_email_alerts') ?? true;

      final savedReviewAlerts =
          prefs.getBool('bg_profile_review_alerts') ?? true;

      final savedGuidelineAlerts =
          prefs.getBool('bg_profile_guideline_alerts') ?? true;

      final savedDarkMode =
          prefs.getBool('bg_profile_dark_mode') ?? false;

      if (!mounted) return;

      setState(() {
        _nameController.text = savedName;
        _emailController.text = savedEmail;

        role = savedRole;
        emailAlerts = savedEmailAlerts;
        reviewAlerts = savedReviewAlerts;
        guidelineAlerts = savedGuidelineAlerts;
        darkMode = savedDarkMode;

        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => isLoading = false);
      _message('Unable to load profile settings.');
    }
  }

  // SAVE PROFILE TO LOCAL STORAGE

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'bg_profile_name',
      _nameController.text.trim(),
    );

    await prefs.setString(
      'bg_profile_email',
      _emailController.text.trim(),
    );

    await prefs.setString(
      'bg_profile_role',
      role,
    );

    await prefs.setBool(
      'bg_profile_email_alerts',
      emailAlerts,
    );

    await prefs.setBool(
      'bg_profile_review_alerts',
      reviewAlerts,
    );

    await prefs.setBool(
      'bg_profile_guideline_alerts',
      guidelineAlerts,
    );

    await prefs.setBool(
      'bg_profile_dark_mode',
      darkMode,
    );
  }

  // UPDATE PREFERENCES

  Future<void> _setPreference(
    String key,
    bool value,
  ) async {
    setState(() {
      if (key == 'email') {
        emailAlerts = value;
      }

      if (key == 'review') {
        reviewAlerts = value;
      }

      if (key == 'guideline') {
        guidelineAlerts = value;
      }

      if (key == 'theme') {
        darkMode = value;
      }
    });

    try {
      await _saveProfile();

      if (!mounted) return;

      _message('Preference saved successfully.');
    } catch (e) {
      if (!mounted) return;

      _message('Unable to save preference.');
    }
  }

  // SNACKBAR

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            text,
            style: _style(
              size: 11,
              color: Colors.white,
            ),
          ),
          backgroundColor: navy,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // EDIT PROFILE DIALOG

  Future<void> _editProfile() async {
    if (isSaving || !mounted) return;

    _nameDraftController.text = _nameController.text;
    _emailDraftController.text = _emailController.text;

    final bool? shouldSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Edit profile',
            style: _style(
              size: 16,
              weight: FontWeight.w800,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameDraftController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailDraftController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: navy,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final name =
                    _nameDraftController.text.trim();

                final email =
                    _emailDraftController.text.trim();

                if (name.isEmpty) {
                  _message('Please enter your name.');
                  return;
                }

                if (email.isEmpty || !email.contains('@')) {
                  _message('Please enter a valid email.');
                  return;
                }

                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save changes'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldSave != true) return;

    // Copy draft values only after the dialog has closed.
    setState(() {
      _nameController.text =
          _nameDraftController.text.trim();

      _emailController.text =
          _emailDraftController.text.trim();

      isSaving = true;
    });

    try {
      await _saveProfile();

      if (!mounted) return;

      setState(() => isSaving = false);

      _message('Profile saved successfully!');
    } catch (e) {
      if (!mounted) return;

      setState(() => isSaving = false);

      _message('Profile could not be saved. Please try again.');
    }
  }

  // INFORMATION DIALOG

  void _settingInfo(String title) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            title,
            style: _style(
              size: 16,
              weight: FontWeight.w800,
            ),
          ),
          content: Text(
            '$title will be connected to account services in the integrated build. This frontend demo keeps the interaction local.',
            style: _style(
              size: 12,
              color: secondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: Text(
                'Close',
                style: _style(
                  weight: FontWeight.w800,
                  color: teal,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // SIGN OUT DIALOG

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Sign out?',
            style: _style(
              size: 16,
              weight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Are you sure you want to sign out of BrandGuard?',
            style: _style(
              size: 12,
              color: secondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);

                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const SignInScreen(),
                  ),
                  (route) => false,
                );
              },
              child: Text(
                'Sign Out',
                style: _style(
                  weight: FontWeight.w800,
                  color: const Color(0xFFC96B6B),
                ),
              ),
            ),
          ],
        );
      },
    );
  }


  // MAIN UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,

      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        foregroundColor: darkNavy,
        title: Text(
          'My Profile',
          style: _style(
            size: 17,
            weight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            onPressed: isLoading || isSaving
                ? null
                : _editProfile,
            tooltip: 'Edit profile',
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),

      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                18,
                12,
                18,
                30,
              ),
              children: [
                // PROFILE HEADER

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: navy,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    children: [
                      const CircleAvatar(
                        radius: 37,
                        backgroundColor: Color(0xFF284657),
                        child: Icon(
                          Icons.person_rounded,
                          color: mint,
                          size: 39,
                        ),
                      ),
                      const SizedBox(height: 12),

                      Text(
                        _nameController.text,
                        textAlign: TextAlign.center,
                        style: _style(
                          size: 17,
                          weight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        _emailController.text,
                        textAlign: TextAlign.center,
                        style: _style(
                          size: 10,
                          color: Colors.white70,
                        ),
                      ),

                      const SizedBox(height: 11),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF284657),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$role • BrandGuard Workspace',
                          style: _style(
                            size: 10,
                            weight: FontWeight.w800,
                            color: mint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // ACCOUNT

                Text(
                  'ACCOUNT',
                  style: _style(
                    size: 10,
                    weight: FontWeight.w800,
                    color: teal,
                  ),
                ),

                const SizedBox(height: 9),

                _infoTile(
                  Icons.badge_outlined,
                  'Account role',
                  role,
                  onTap: () => _settingInfo('Account role'),
                ),

                _infoTile(
                  Icons.email_outlined,
                  'Email address',
                  _emailController.text,
                  onTap: _editProfile,
                ),

                _infoTile(
                  Icons.lock_outline_rounded,
                  'Password & security',
                  'Manage sign-in security',
                  onTap: () =>
                      _settingInfo('Password & security'),
                ),

                const SizedBox(height: 20),

                // PREFERENCES

                Text(
                  'PREFERENCES',
                  style: _style(
                    size: 10,
                    weight: FontWeight.w800,
                    color: teal,
                  ),
                ),

                const SizedBox(height: 9),

                _switchTile(
                  'Email notifications',
                  'Receive account updates by email.',
                  emailAlerts,
                  (value) => _setPreference('email', value),
                ),

                _switchTile(
                  'Review notifications',
                  'Get notified about review activity.',
                  reviewAlerts,
                  (value) => _setPreference('review', value),
                ),

                _switchTile(
                  'Guideline updates',
                  'Get notified when rules or sources change.',
                  guidelineAlerts,
                  (value) => _setPreference('guideline', value),
                ),

                _switchTile(
                  'Dark appearance',
                  'Saved demo preference; app-wide theme is not applied.',
                  darkMode,
                  (value) => _setPreference('theme', value),
                ),

                const SizedBox(height: 20),

                // SUPPORT

                Text(
                  'SUPPORT',
                  style: _style(
                    size: 10,
                    weight: FontWeight.w800,
                    color: teal,
                  ),
                ),

                const SizedBox(height: 9),

                _infoTile(
                  Icons.help_outline_rounded,
                  'Help & support',
                  'Get help using BrandGuard',
                  onTap: () => _settingInfo('Help & support'),
                ),

                _infoTile(
                  Icons.info_outline_rounded,
                  'About BrandGuard',
                  'Frontend demo • Version 1.0',
                  onTap: () => _settingInfo('About BrandGuard'),
                ),

                const SizedBox(height: 18),

                // SIGN OUT

                OutlinedButton.icon(
                  onPressed: _showSignOutDialog,
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(
                    'Sign Out',
                    style: _style(
                      size: 12,
                      weight: FontWeight.w800,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFC96B6B),
                    side: const BorderSide(
                      color: Color(0xFFE8D4D2),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ACCOUNT TILE

  Widget _infoTile(
    IconData icon,
    String title,
    String subtitle, {
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: border),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: teal,
          size: 21,
        ),
        title: Text(
          title,
          style: _style(
            size: 12,
            weight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: _style(
            size: 10,
            color: secondary,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: secondary,
        ),
      ),
    );
  }

  // PREFERENCE SWITCH TILE

  Widget _switchTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _style(
                    size: 12,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: _style(
                    size: 10,
                    color: secondary,
                  ),
                ),
              ],
            ),
          ),

          Switch(
            value: value,
            activeThumbColor: teal,
            onChanged: isSaving ? null : onChanged,
          ),
        ],
      ),
    );
  }
}
