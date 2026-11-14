
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FactSourcesScreen extends StatefulWidget {
  const FactSourcesScreen({super.key});

  @override
  State<FactSourcesScreen> createState() => _FactSourcesScreenState();
}

class _FactSourcesScreenState extends State<FactSourcesScreen> {
  static const Color navy = Color(0xFF142C3B);
  static const Color darkNavy = Color(0xFF001725);
  static const Color teal = Color(0xFF006B5E);
  static const Color mint = Color(0xFF81F7E1);
  static const Color background = Color(0xFFF7F8F6);
  static const Color border = Color(0xFFE5EAE7);
  static const Color secondary = Color(0xFF73787C);
  static const Color green = Color(0xFF4B9475);
  static const Color amber = Color(0xFFB98742);
  static const Color red = Color(0xFFC96B6B);

  static const String storageKey = 'brandguard_fact_sources_v1';

  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<Map<String, dynamic>> sources = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);

    if (saved != null) {
      try {
        final decoded = jsonDecode(saved) as List;
        sources = decoded
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      } catch (_) {
        sources = [];
      }
    }

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _saveSources() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(sources));
  }

  Future<void> _addSource() async {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();

    if (name.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Source name and URL are required.'),
        ),
      );
      return;
    }

    final parsedUri = Uri.tryParse(url);
    if (parsedUri == null ||
        !parsedUri.hasScheme ||
        (parsedUri.scheme != 'http' && parsedUri.scheme != 'https') ||
        parsedUri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid http or https URL.'),
        ),
      );
      return;
    }

    final source = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': name,
      'url': url,
      'description': _descriptionController.text.trim(),
      'verified': false,
      'createdAt': DateTime.now().toIso8601String(),
    };

    setState(() => sources.insert(0, source));
    await _saveSources();

    _nameController.clear();
    _urlController.clear();
    _descriptionController.clear();

    if (!mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fact source added successfully.')),
    );
  }

  Future<void> _toggleVerification(int index, bool value) async {
    setState(() => sources[index]['verified'] = value);
    await _saveSources();
  }

  Future<void> _deleteSource(int index) async {
    setState(() => sources.removeAt(index));
    await _saveSources();
  }

  void _showAddSourceSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(sheetContext).viewInsets.bottom + 22,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: border,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Add Fact Source',
                  style: _style(
                    size: 19,
                    weight: FontWeight.w800,
                    color: darkNavy,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Add a source that can support factual claims.',
                  style: _style(size: 11, color: secondary),
                ),
                const SizedBox(height: 18),
                _label('SOURCE NAME'),
                _input(
                  _nameController,
                  'e.g. Official Product Documentation',
                ),
                const SizedBox(height: 14),
                _label('SOURCE URL'),
                _input(_urlController, 'https://example.com'),
                const SizedBox(height: 14),
                _label('DESCRIPTION (OPTIONAL)'),
                _input(
                  _descriptionController,
                  'What facts can this source verify?',
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _addSource,
                    icon: const Icon(Icons.add_link_rounded, size: 18),
                    label: Text(
                      'Save Fact Source',
                      style: _style(
                        size: 12,
                        weight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _label(String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        value,
        style: _style(
          size: 9,
          weight: FontWeight.w800,
          color: secondary,
          letterSpacing: 0.7,
        ),
      ),
    );
  }

  Widget _input(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: _style(size: 12),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: _style(
          size: 11,
          color: secondary.withValues(alpha: 0.7),
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAF9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: teal, width: 1.3),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final verifiedCount =
        sources.where((source) => source['verified'] == true).length;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        foregroundColor: darkNavy,
        title: Text(
          'Fact Sources',
          style: _style(size: 17, weight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSourceSheet,
        backgroundColor: navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Add Source',
          style: _style(
            size: 12,
            weight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: navy,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.fact_check_rounded,
                        size: 35,
                        color: mint,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Evidence Source Library',
                              style: _style(
                                size: 15,
                                weight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$verifiedCount verified • ${sources.length} total sources',
                              style: _style(size: 10, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Available Sources',
                  style: _style(size: 16, weight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (sources.isEmpty)
                  _emptyState()
                else
                  ...sources.asMap().entries.map((entry) {
                    final index = entry.key;
                    final source = entry.value;
                    final verified = source['verified'] == true;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 11),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 37,
                                height: 37,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F6FF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.language_rounded,
                                  color: navy,
                                  size: 19,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  source['name']?.toString() ?? '',
                                  style: _style(
                                    size: 12,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => _deleteSource(index),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: red,
                                  size: 19,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            source['url']?.toString() ?? '',
                            style: _style(size: 10, color: teal),
                          ),
                          if ((source['description'] ?? '')
                              .toString()
                              .isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              source['description'].toString(),
                              style: _style(
                                size: 11,
                                color: secondary,
                                height: 1.5,
                              ),
                            ),
                          ],
                          const Divider(height: 20),
                          Row(
                            children: [
                              Icon(
                                verified
                                    ? Icons.verified_rounded
                                    : Icons.pending_outlined,
                                size: 15,
                                color: verified ? green : amber,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                verified ? 'Verified source' : 'Not verified',
                                style: _style(
                                  size: 10,
                                  weight: FontWeight.w700,
                                  color: verified ? green : amber,
                                ),
                              ),
                              const Spacer(),
                              Switch(
                                value: verified,
                                activeThumbColor: teal,
                                onChanged: (value) =>
                                    _toggleVerification(index, value),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.storage_rounded,
            size: 34,
            color: secondary,
          ),
          const SizedBox(height: 10),
          Text(
            'No fact sources added',
            style: _style(size: 13, weight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            'Add official websites or documentation to build your evidence library.',
            textAlign: TextAlign.center,
            style: _style(size: 10, color: secondary),
          ),
        ],
      ),
    );
  }

  TextStyle _style({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = const Color(0xFF26363C),
    double? height,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}
