import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart' show log;
import '../../models/channel_index.dart';
import '../../services/channel_cache.dart';
import '../../utils/text_search.dart';
import '../home/channel_card.dart';
import '../home/sort_mode.dart';

/// Standalone "Svi kanali" ekran — odvojen od home-a (scroll-perf).
///
/// Zasto odvojeno: home je prije renderirao SVE kanale (44+) eager u jednom
/// `SliverToBoxAdapter` → `Wrap`. Na web (skwasm) buildu to znaci da svaka
/// kartica zivi u stablu i sudjeluje u rasterizaciji svakog scroll frame-a →
/// vidljiv jank. Ovdje listu renderiramo **lazy** (`SliverList` po redovima,
/// recycle off-screen) + dodajemo filter, pa home ostaje lagan.
///
/// Surface je self-contained: sam ucita index iz [channelCache], drzi vlastiti
/// sort + filter state i persista sort (dijeli `channel_sort_v1` /
/// `channel_order` kljuceve s home-om). Otvara se kao full-page `/channels`
/// ruta ([AllChannelsScreen]) i na desktopu i na mobitelu — deep-linkable,
/// native back button.

/// Full-page varijanta — meta `/channels` rute.
class AllChannelsScreen extends StatelessWidget {
  const AllChannelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(l.channelAllChannels),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l.commonBack,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: const SafeArea(top: false, child: AllChannelsView()),
    );
  }
}

/// Sadrzaj surface-a: search bar + sort red + lazy lista kanala.
///
/// Self-contained — ucita index + sort sam.
class AllChannelsView extends StatefulWidget {
  const AllChannelsView({super.key});

  @override
  State<AllChannelsView> createState() => _AllChannelsViewState();
}

class _AllChannelsViewState extends State<AllChannelsView> {
  static const double _maxCardWidth = 360;

  final _searchCtrl = TextEditingController();
  String _query = '';

  ChannelSortMode _sortMode = ChannelSortMode.newest;
  List<ChannelSummary> _channels = const [];
  List<String>? _customOrder;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (_searchCtrl.text != _query) {
        setState(() => _query = _searchCtrl.text);
      }
    });
    _init();
  }

  Future<void> _init() async {
    try {
      final index = channelCache.index ?? await channelCache.loadIndex();
      final mode = await loadSortMode() ?? ChannelSortMode.newest;
      final order = await loadCustomOrder();
      if (!mounted) return;
      setState(() {
        _channels = index.channels;
        _sortMode = mode;
        _customOrder = order;
        _ready = true;
      });
    } catch (e) {
      log('AllChannelsView._init ERROR: $e');
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ChannelSummary> get _ordered =>
      applySortMode(_channels, _sortMode, customOrder: _customOrder);

  /// Vidljiva lista nakon filtera. Prazan upit → puni (sortirani) popis;
  /// inace dijakritik-neosjetljiv match na imenu, najbolji rezultat prvi.
  List<ChannelSummary> get _visible {
    final ordered = _ordered;
    final q = _query.trim();
    if (q.isEmpty) return ordered;
    final scored = <(double, ChannelSummary)>[];
    for (final c in ordered) {
      final s = localMatchScore(q, c.name);
      if (s > 0) scored.add((s, c));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return scored.map((e) => e.$2).toList();
  }

  Future<void> _onSortChanged(ChannelSortMode mode) async {
    await saveSortMode(mode);
    if (mounted) setState(() => _sortMode = mode);
  }

  Future<void> _onShuffle() async {
    final shuffled = List<ChannelSummary>.from(_channels)..shuffle(Random());
    final ids = shuffled.map((c) => c.id).toList();
    await saveCustomOrder(ids);
    await saveSortMode(ChannelSortMode.custom);
    if (mounted) {
      setState(() {
        _customOrder = ids;
        _sortMode = ChannelSortMode.custom;
      });
    }
  }

  void _openChannel(ChannelSummary channel) {
    final slug = channel.id.replaceAll('_', '-');
    context.go('/c/$slug');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchBar(theme),
        _toolbar(theme),
        Expanded(
          child: !_ready
              ? const Center(child: CircularProgressIndicator())
              : _list(),
        ),
      ],
    );
  }

  Widget _searchBar(ThemeData theme) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: l.channelSearchChannelsHint,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: l.channelClear,
                  onPressed: () => _searchCtrl.clear(),
                )
              : null,
          isDense: true,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _toolbar(ThemeData theme) {
    final l = AppLocalizations.of(context);
    final count = _visible.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          Text(
            _query.trim().isEmpty
                ? l.channelChannelsCount(count)
                : l.channelResultsCount(count),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // Sort je besmislen dok je aktivan filter (rezultati su po relevanciji).
          if (_query.trim().isEmpty)
            ChannelSortDropdown(
              mode: _sortMode,
              onChanged: _onSortChanged,
              onShuffle: _onShuffle,
            ),
        ],
      ),
    );
  }

  Widget _list() {
    final l = AppLocalizations.of(context);
    final items = _visible;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _query.trim().isEmpty
                ? l.channelNoChannels
                : l.channelNoChannelsForQuery(_query.trim()),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final available = width - 32; // horizontalni padding 16+16
        // Mobile (< 600): 1 stupac. Sire: clamp na ~360px max sirinu kartice.
        final columns = width < 600
            ? 1
            : (available / _maxCardWidth).floor().clamp(2, 99);
        final cardWidth = columns == 1
            ? available
            : (available - (columns - 1) * 16) / columns;
        final rowCount = (items.length / columns).ceil();

        // SliverList po REDOVIMA (ne SliverGrid): kanal kartice imaju
        // varijabilnu visinu (banner vs square layout, 1-2 linije naziva), a
        // SliverGrid forsira uniformnu visinu celije → clipanje. Red drzi
        // prirodne visine (top-aligned), a SliverList recycle-a off-screen
        // redove → lazy paint kakav nam je i bio cilj.
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList.builder(
                itemCount: rowCount,
                itemBuilder: (context, row) {
                  final start = row * columns;
                  final end = min(start + columns, items.length);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (int i = start; i < end; i++) ...[
                          if (i > start) const SizedBox(width: 16),
                          SizedBox(
                            width: cardWidth,
                            child: ChannelCard(
                              channel: items[i],
                              onTap: () => _openChannel(items[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

}

/// Sort selektor za kanale — PopupMenuButton sa svim sort opcijama + shuffle.
///
/// Premjesteno iz home-a (bivsi `_SortDropdown`) da ga dijeli `AllChannelsView`.
class ChannelSortDropdown extends StatelessWidget {
  final ChannelSortMode mode;
  final Future<void> Function(ChannelSortMode) onChanged;
  final VoidCallback onShuffle;

  const ChannelSortDropdown({
    super.key,
    required this.mode,
    required this.onChanged,
    required this.onShuffle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      tooltip: l.channelSortChannels,
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (value) {
        if (value == '__shuffle__') {
          onShuffle();
        } else {
          final m = ChannelSortMode.values.firstWhere((e) => e.name == value);
          onChanged(m);
        }
      },
      itemBuilder: (context) => [
        for (final m in ChannelSortMode.values)
          PopupMenuItem<String>(
            value: m.name,
            child: Row(
              children: [
                Icon(
                  m == mode ? Icons.check : Icons.circle_outlined,
                  size: 14,
                  color: m == mode
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.3),
                ),
                const SizedBox(width: 10),
                Text(m.label(l), style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '__shuffle__',
          child: Row(
            children: [
              Icon(Icons.shuffle,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(l.channelShuffle, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              mode.label(l),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
