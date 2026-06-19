import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/cal_booking_service.dart';
import '../services/open_url.dart';
import '../theme/app_theme.dart';

/// Floating "bubble" koji otvara native booking sheet za 15-min razgovor s
/// osnivačem (Cal.com event "15 min DOMOVINA.ai"). Postavi ga kao
/// `floatingActionButton:` na bilo koji Scaffold.
class FounderBookingBubble extends StatelessWidget {
  const FounderBookingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'founder-booking',
      onPressed: () => showFounderBookingSheet(context),
      backgroundColor: AppTheme.croBlue,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: AppTheme.brandRim(Theme.of(context).brightness),
      ),
      tooltip: '15 min s osnivačem',
      child: const Icon(Icons.event_available_rounded),
    );
  }
}

/// Otvara booking flow u modalnom bottom sheetu (i web i native).
Future<void> showFounderBookingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => const _FounderBookingSheet(),
  );
}

enum _Step { pickTime, details, success }

class _FounderBookingSheet extends StatefulWidget {
  const _FounderBookingSheet();

  @override
  State<_FounderBookingSheet> createState() => _FounderBookingSheetState();
}

class _FounderBookingSheetState extends State<_FounderBookingSheet> {
  final _service = CalBookingService();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _notes;

  late Future<List<CalSlot>> _slotsFuture;

  _Step _step = _Step.pickTime;
  String? _selectedDay;
  CalSlot? _selectedSlot;
  bool _submitting = false;
  String? _error;
  CalBooking? _booking;

  @override
  void initState() {
    super.initState();
    final user = AuthService.instance.currentUser;
    _name = TextEditingController(text: user?.displayName ?? '');
    _email = TextEditingController(text: user?.email ?? '');
    _notes = TextEditingController();
    _slotsFuture = _loadSlots();
  }

  Future<List<CalSlot>> _loadSlots() {
    final now = DateTime.now();
    return _service.fetchSlots(
      from: now,
      to: now.add(const Duration(days: 21)),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Header(),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: switch (_step) {
                  _Step.pickTime => _buildPickTime(context),
                  _Step.details => _buildDetails(context),
                  _Step.success => _buildSuccess(context),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Step 1: pick a time ------------------------------------------------

  Widget _buildPickTime(BuildContext context) {
    return FutureBuilder<List<CalSlot>>(
      key: const ValueKey('pickTime'),
      future: _slotsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError || snap.data == null) {
          return _ErrorRetry(
            message: snap.error is CalException
                ? '${snap.error}'
                : 'Ne mogu dohvatiti termine.',
            onRetry: () => setState(() => _slotsFuture = _loadSlots()),
          );
        }
        final slots = snap.data!;
        if (slots.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'Trenutno nema slobodnih termina u sljedeća tri tjedna.',
              textAlign: TextAlign.center,
            ),
          );
        }
        final byDay = <String, List<CalSlot>>{};
        for (final s in slots) {
          (byDay[s.dayKey] ??= []).add(s);
        }
        final days = byDay.keys.toList()..sort();
        final activeDay = (_selectedDay != null && byDay.containsKey(_selectedDay))
            ? _selectedDay!
            : days.first;
        final daySlots = byDay[activeDay]!;

        return Column(
          key: const ValueKey('pickTimeBody'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _SectionLabel('Odaberi dan'),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: days.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _DayChip(
                  dayKey: days[i],
                  count: byDay[days[i]]!.length,
                  selected: days[i] == activeDay,
                  onTap: () => setState(() {
                    _selectedDay = days[i];
                    _selectedSlot = null;
                  }),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _SectionLabel('Slobodni termini'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in daySlots)
                  _TimeChip(
                    label: s.label,
                    selected: identical(s, _selectedSlot),
                    onTap: () => setState(() => _selectedSlot = s),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _selectedSlot == null
                  ? null
                  : () => setState(() => _step = _Step.details),
              child: const Text('Nastavi'),
            ),
          ],
        );
      },
    );
  }

  // ---- Step 2: details ----------------------------------------------------

  Widget _buildDetails(BuildContext context) {
    final theme = Theme.of(context);
    final slot = _selectedSlot!;
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('details'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SelectedSlotBanner(
            slot: slot,
            onChange: () => setState(() => _step = _Step.pickTime),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Ime i prezime'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Upiši svoje ime' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-mail'),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return 'Upiši e-mail';
              if (!t.contains('@') || !t.contains('.')) return 'Neispravan e-mail';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Tema razgovora (opcionalno)',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Potvrdi termin'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final booking = await _service.createBooking(
        startIso: _selectedSlot!.iso,
        name: _name.text.trim(),
        email: _email.text.trim(),
        notes: _notes.text,
      );
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _step = _Step.success;
        _submitting = false;
      });
    } on CalException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Greška u mreži. Pokušaj ponovno.';
        _submitting = false;
      });
    }
  }

  // ---- Step 3: success ----------------------------------------------------

  Widget _buildSuccess(BuildContext context) {
    final theme = Theme.of(context);
    final slot = _selectedSlot!;
    final meetUrl = _booking?.meetingUrl;
    return Column(
      key: const ValueKey('success'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Icon(Icons.check_circle_rounded, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text(
          'Termin potvrđen!',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          '${_fullDayLabel(slot.dayKey)} u ${slot.label}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Pozivnicu i Google Meet link poslali smo na ${_email.text.trim()}.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (meetUrl != null && meetUrl.startsWith('http'))
          FilledButton.icon(
            onPressed: () => openUrl(meetUrl),
            icon: const Icon(Icons.videocam_rounded, color: Colors.white),
            label: const Text('Otvori Google Meet'),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Gotovo'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.croBlue,
            shape: BoxShape.circle,
            border: Border.fromBorderSide(AppTheme.brandRim(theme.brightness)),
          ),
          child: const Icon(Icons.waving_hand_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('15 minuta s osnivačem', style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                'Matija Stepanić · Google Meet',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final String dayKey;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _DayChip({
    required this.dayKey,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = DateTime.parse(dayKey);
    final bg = selected ? AppTheme.croBlue : theme.colorScheme.surfaceContainerLow;
    final fg = selected ? Colors.white : theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _hrWeekdayShort[d.weekday - 1],
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${d.day}.${d.month}.',
              style: theme.textTheme.titleSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TimeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.croBlue : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: selected ? Colors.white : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SelectedSlotBanner extends StatelessWidget {
  final CalSlot slot;
  final VoidCallback onChange;

  const _SelectedSlotBanner({required this.slot, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_fullDayLabel(slot.dayKey)} u ${slot.label}',
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: onChange, child: const Text('Promijeni')),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Pokušaj ponovno')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Croatian date helpers
// ---------------------------------------------------------------------------

const _hrWeekdayShort = ['pon', 'uto', 'sri', 'čet', 'pet', 'sub', 'ned'];
const _hrWeekdayLong = [
  'ponedjeljak', 'utorak', 'srijeda', 'četvrtak', 'petak', 'subota', 'nedjelja',
];
const _hrMonthsGen = [
  'siječnja', 'veljače', 'ožujka', 'travnja', 'svibnja', 'lipnja',
  'srpnja', 'kolovoza', 'rujna', 'listopada', 'studenoga', 'prosinca',
];

String _fullDayLabel(String dayKey) {
  final d = DateTime.parse(dayKey);
  return '${_hrWeekdayLong[d.weekday - 1]}, ${d.day}. ${_hrMonthsGen[d.month - 1]}';
}
