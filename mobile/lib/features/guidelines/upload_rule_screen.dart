import 'package:material_ui/material_ui.dart';

import 'library_screen.dart';

class UploadRuleScreen extends StatelessWidget {
  const UploadRuleScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const LibraryScreen(kind: 'rules', title: 'Enforceable Rules');
}
