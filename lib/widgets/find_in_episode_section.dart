import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show log;
import '../services/transcript_search.dart';
import 'em_highlight_text.dart';

/// „Pronađi u epizodi": polje za riječ, ime ili frazu → SVI trenuci u kojima
/// je izgovorena, kronološki. Tap na redak skoči u playeru na tu sekundu.
///
/// Doslovni pogoci idu prvi; oni koji su stigli samo preko tolerancije
/// tipfelera („Matija" → „Marija") stoje ispod, prigušeni.
class FindInEpisodeSection extends StatefulWidget {
  final String youtubeId;

  /// Null dok player nije spreman — redovi se tada prikazuju, ali ne skaču.
  final ValueChanged<int>? onJump;

  final double horizontalPadding;

  const FindInEpisodeSection({
    super.key,
    required this.youtubeId,
    required this.onJump,
    this.horizontalPadding = 20,
  });

  @override
  State<FindInEpisodeSection> createState() => _FindInEpisodeSectionState();
}

class _FindInEpisodeSectionState extends State<FindInEpisodeSection> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;
  bool _loading = false;
  bool _failed = false;
  TranscriptSearchResult? _result;

  @override
  void didUpdateWidget(FindInEpisodeSection old) {
    super.didUpdateWidget(old);
    if (old.youtubeId != widget.youtubeId) _clear();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _debounce?.cancel();
    _requestId++;
    _controller.clear();
    setState(() {
      _loading = false;
      _failed = false;
      _result = null;
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      _requestId++;
      setState(() {
        _loading = false;
        _failed = false;
        _result = null;
      });
      return;
    }
    setState(() {}); // gumb za brisanje i status prate tekst odmah
    _debounce = Timer(const Duration(milliseconds: 250), () => _run(q));
  }

  Future<void> _run(String q) async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final r = await TranscriptSearch.search(widget.youtubeId, q);
      if (!mounted || id != _requestId) return;
      log('FindInEpisode: "$q" → ${r.totalHits} pogodaka');
      setState(() {
        _result = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      log('FindInEpisode: "$q" fail: $e');
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final hp = widget.horizontalPadding;
    final result = _result;
    final hasQuery = _controller.text.trim().length >= 2;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hp),
            child: Text(
              l.findInEpisodeTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hp),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.findInEpisodeHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l.findInEpisodeClear,
                        icon: const Icon(Icons.close),
                        onPressed: _clear,
                      ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          if (hasQuery) ...[
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hp),
              child: _status(theme, l, result),
            ),
          ],
          if (hasQuery && result != null && !_failed) ...[
            for (final h in result.exact) _HitRow(hit: h, hp: hp, onJump: widget.onJump),
            if (result.approximate.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(hp, 14, hp, 4),
                child: Text(
                  l.findInEpisodeApproximate,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final h in result.approximate)
                _HitRow(hit: h, hp: hp, onJump: widget.onJump, dimmed: true),
            ],
          ],
        ],
      ),
    );
  }

  Widget _status(
    ThemeData theme,
    AppLocalizations l,
    TranscriptSearchResult? result,
  ) {
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (_loading && result == null) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_failed) return Text(l.findInEpisodeError, style: style);
    if (result == null) return const SizedBox.shrink();
    if (result.totalHits == 0) return Text(l.findInEpisodeNoHits, style: style);
    final shown = result.hits.length;
    return Text(
      shown < result.totalHits
          ? l.findInEpisodeCountPartial(shown, result.totalHits)
          : l.findInEpisodeCount(result.totalHits),
      style: style,
    );
  }
}

class _HitRow extends StatelessWidget {
  final TranscriptHit hit;
  final double hp;
  final ValueChanged<int>? onJump;
  final bool dimmed;

  const _HitRow({
    required this.hit,
    required this.hp,
    required this.onJump,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: dimmed ? muted : null,
    );
    final jump = onJump;
    return InkWell(
      onTap: jump == null ? null : () => jump(hit.second),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hp, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text(
                formatTranscriptTimestamp(hit.second),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: dimmed ? muted : theme.colorScheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ime dolazi iz dijarizacije i zna biti krivo — oznaka uz
                  // isječak, ne tvrdnja „X je rekao".
                  if (hit.speaker != null)
                    Text(
                      hit.speaker!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                  EmHighlightText(
                    hit.formatted,
                    style: textStyle,
                    highlightStyle: dimmed
                        ? textStyle?.copyWith(fontWeight: FontWeight.w700)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
