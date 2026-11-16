import 'package:material_ui/material_ui.dart';

import 'library_screen.dart';

class FactSourcesScreen extends StatelessWidget {
  const FactSourcesScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const LibraryScreen(kind: 'facts', title: 'Fact Sources');
}
