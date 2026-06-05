import 'package:flutter/material.dart';

import '../../../models/channel_detail.dart';

/// Multi-select epizoda kanala za dodjelu kampanji. Pre-checked iz trenutnog
/// seta; "Spremi" zove [onSave] (koja smije baciti — npr. epizoda već u drugoj
/// kampanji) i poruka greške se prikaže ispod.
class EpisodePicker extends StatefulWidget {
  final List<ChannelVideo> videos;
  final Set<String> initialSelected;

  /// Sprema novi set youtube id-eva. Baca na grešci (mapiranu u poruku).
  final Future<void> Function(Set<String> selected) onSave;

  const EpisodePicker({
    super.key,
    required this.videos,
    required this.initialSelected,
    required this.onSave,
  });

  @override
  State<EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<EpisodePicker> {
  late final Set<String> _selected = {...widget.initialSelected};
  bool _saving = false;
  String? _error;
  bool _dirty = false;

  void _toggle(String id, bool? on) {
    setState(() {
      if (on ?? false) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_selected);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Epizode spremljene')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().contains('episode_taken')
            ? 'Jedna od epizoda je već u drugoj kampanji.'
            : 'Spremanje nije uspjelo. Pokušaj ponovno.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.videos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Nema dostupnih epizoda za ovaj kanal.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Odabrano: ${_selected.length} epizoda',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              FilledButton.icon(
                onPressed: (_saving || !_dirty) ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save, size: 18),
                label: const Text('Spremi'),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(_error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: widget.videos.length,
            itemBuilder: (context, i) {
              final v = widget.videos[i];
              return CheckboxListTile(
                dense: true,
                value: _selected.contains(v.id),
                onChanged: (on) => _toggle(v.id, on),
                title: Text(v.displayTitle,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: v.date != null ? Text(v.date!) : null,
                secondary: v.thumbnail != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          v.thumbnail!,
                          width: 64,
                          height: 36,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(
                              width: 64, height: 36),
                        ),
                      )
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}
