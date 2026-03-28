import 'package:flutter/material.dart';
import 'episode_screen.dart';

/// Početni ekran — korisnik unosi YouTube ID epizode.
/// Nema hardkodiranih podataka; sve se učitava s CDN-a po unesenom ID-u.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  void _open() {
    if (!_formKey.currentState!.validate()) return;
    final id = _controller.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EpisodeScreen(youtubeId: id),
        settings: RouteSettings(name: '/v/$id'),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Domovina.ai',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Unesi YouTube ID epizode',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: 'YouTube ID',
                      hintText: 'npr. H-p2Hl6x7I0',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.ondemand_video_outlined),
                    ),
                    textInputAction: TextInputAction.go,
                    onFieldSubmitted: (_) => _open(),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Unesi YouTube ID';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _open,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Otvori epizodu'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
