/// Premium sign-in bottom sheet. Brandiran (logo + trikolora + editorial
/// typography); nudi Passkey (preporučeno) + Google/Apple/e-mail magic link,
/// te "Već imaš passkey? Prijavi se".
///
/// E-mail flow je in-sheet (korak e-mail → korak kod) s resend countdownom,
/// autofill hintovima i inline greškama — bez modalnih dialoga.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../main.dart' show rootScaffoldMessengerKey;
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/local_prefs.dart';
import 'auth_ui.dart';

enum AuthSheetOrigin { account, moment2, moment3, handoff }

/// Koji je korak trenutno prikazan u sheetu.
enum _SheetView { providers, emailEntry, otpEntry }

Future<void> showAuthSheet(
  BuildContext context, {
  AuthSheetOrigin origin = AuthSheetOrigin.account,
  String? headlineOverride,
  String? subtitleOverride,
}) {
  final content = _AuthSheetContent(
    origin: origin,
    headlineOverride: headlineOverride,
    subtitleOverride: subtitleOverride,
  );
  // Desktop/wide: centrirani dialog (bottom sheet je mobile pattern).
  if (MediaQuery.of(context).size.width >= 700) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: Theme.of(ctx)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.5),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: content,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => content,
  );
}

class _AuthSheetContent extends StatefulWidget {
  final AuthSheetOrigin origin;
  final String? headlineOverride;
  final String? subtitleOverride;

  const _AuthSheetContent({
    required this.origin,
    this.headlineOverride,
    this.subtitleOverride,
  });

  @override
  State<_AuthSheetContent> createState() => _AuthSheetContentState();
}

class _AuthSheetContentState extends State<_AuthSheetContent> {
  static const _resendCooldown = 60;

  _SheetView _view = _SheetView.providers;

  /// Provider čija operacija upravo traje (spinner na njegovom tile-u);
  /// svi ostali su disabled dok se ne završi.
  AuthProvider? _pending;

  /// "Već imaš passkey? Prijavi se" — odvojen od [_pending] jer ne pripada
  /// nijednom tile-u.
  bool _passkeyLoginPending = false;

  /// E-mail koraci: slanje koda / verifikacija u tijeku.
  bool _emailBusy = false;

  /// Zadnja greška — prikazuje se inline u sheetu (ne snackbar).
  String? _error;

  /// Neutralna obavijest (npr. "novi kod poslan").
  String? _notice;

  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String _otpEmail = '';
  Timer? _resendTimer;
  int _resendSeconds = 0;

  /// Zadnja uspješno korištena metoda (localStorage) — "ZADNJI PUT" hint
  /// smanjuje rizik da returning user otvori drugi račun drugom metodom.
  AuthProvider? _lastUsed;

  bool get _busy => _pending != null || _passkeyLoginPending || _emailBusy;

  AuthSheetOrigin get origin => widget.origin;

  @override
  void initState() {
    super.initState();
    final raw = getLocalStorageString(lastProviderKey);
    _lastUsed =
        AuthProvider.values.where((p) => p.name == raw).firstOrNull;
  }

  String? _lastUsedBadge(AuthProvider p) =>
      _lastUsed == p ? 'ZADNJI PUT' : null;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 4,
            bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthBrandHeader(
                  title: _title(),
                  subtitle: _subtitle(),
                ),
                const SizedBox(height: 24),
                ...switch (_view) {
                  _SheetView.providers => _providerChildren(cs),
                  _SheetView.emailEntry => _emailEntryChildren(cs),
                  _SheetView.otpEntry => _otpEntryChildren(theme, cs),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── providers view ─────────────────────────────────────────────────────

  List<Widget> _providerChildren(ColorScheme cs) => [
        // Passkey LOGIN — primarna metoda (najmanji friction za returning
        // usere). Kreiranje passkeyja namjerno NIJE u sheetu: novi korisnik
        // bi si nakreirao više passkeyja (i računa) u Apple/Google manageru.
        // Passkey se dodaje kao provider u Moj račun NAKON prijave →
        // 1 osoba = 1 račun s N providera (GoTrue merga po emailu).
        AuthProviderTile(
          primary: true,
          badge: 'PREPORUČENO',
          iconBg: Colors.white.withValues(alpha: 0.16),
          iconChild:
              const Icon(Icons.fingerprint, color: Colors.white, size: 22),
          label: 'Prijavi se passkeyom',
          subtitle: 'Najbrže — Face ID / otisak, bez lozinke',
          enabled: !_busy,
          loading: _passkeyLoginPending,
          onTap: _signInWithExistingPasskey,
        ),
        const SizedBox(height: 12),
        const LabeledDivider(),
        const SizedBox(height: 16),
        AuthProviderTile(
          iconBg: AppTheme.croRed.withValues(alpha: 0.10),
          iconChild: const Icon(Icons.badge_outlined,
              color: AppTheme.croRed, size: 22),
          label: 'Prijava eOsobnom',
          subtitle: 'Hrvatska e-osobna (Certilia / NIAS)',
          badge: _lastUsedBadge(AuthProvider.certilia),
          badgeColor: AppTheme.croBlue,
          enabled: !_busy,
          loading: _pending == AuthProvider.certilia,
          onTap: () => _doLink(AuthProvider.certilia),
        ),
        const SizedBox(height: 10),
        // Službeni Google "G" asset (brand guidelines) na bijeloj podlozi.
        AuthProviderTile(
          iconBg: Colors.white,
          iconChild: Image.asset(
            'assets/icons/google_g_logo.png',
            width: 22,
            height: 22,
            filterQuality: FilterQuality.high,
          ),
          label: 'Nastavi s Googleom',
          badge: _lastUsedBadge(AuthProvider.google),
          badgeColor: AppTheme.croBlue,
          enabled: !_busy,
          loading: _pending == AuthProvider.google,
          onTap: () => _doLink(AuthProvider.google),
        ),
        const SizedBox(height: 10),
        AuthProviderTile(
          iconBg: const Color(0xFF111111),
          iconChild: const Icon(Icons.apple, color: Colors.white, size: 24),
          label: 'Nastavi s računom Apple',
          badge: _lastUsedBadge(AuthProvider.apple),
          badgeColor: AppTheme.croBlue,
          enabled: !_busy,
          loading: _pending == AuthProvider.apple,
          onTap: () => _doLink(AuthProvider.apple),
        ),
        const SizedBox(height: 10),
        AuthProviderTile(
          iconBg: AppTheme.croBlue.withValues(alpha: 0.10),
          iconChild: const Icon(Icons.alternate_email,
              color: AppTheme.croBlue, size: 21),
          label: 'E-mail magic link',
          subtitle: 'Pošaljemo ti link i kod za prijavu',
          badge: _lastUsedBadge(AuthProvider.email),
          badgeColor: AppTheme.croBlue,
          enabled: !_busy,
          onTap: _openEmailEntry,
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          _ErrorNote(message: _error!),
        ],
        if (_notice != null) ...[
          const SizedBox(height: 14),
          _NoticeNote(message: _notice!),
        ],
        const SizedBox(height: 18),
        _ReassuranceNote(origin: origin),
        const SizedBox(height: 10),
        const _LegalLine(),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            origin == AuthSheetOrigin.moment2 ? 'Možda kasnije' : 'Zatvori',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      ];

  // ── e-mail entry view ──────────────────────────────────────────────────

  List<Widget> _emailEntryChildren(ColorScheme cs) => [
        AutofillGroup(
          child: TextField(
            controller: _emailCtrl,
            autofocus: true,
            enabled: !_emailBusy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendEmailCode(),
            decoration: const InputDecoration(
              hintText: 'ime@primjer.com',
              prefixIcon: Icon(Icons.alternate_email, size: 20),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorNote(message: _error!),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _emailBusy ? null : _sendEmailCode,
          child: _emailBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Pošalji kod'),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _emailBusy ? null : _backToProviders,
          child: Text(
            'Natrag',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      ];

  // ── OTP entry view ─────────────────────────────────────────────────────

  List<Widget> _otpEntryChildren(ThemeData theme, ColorScheme cs) => [
        TextField(
          controller: _otpCtrl,
          autofocus: true,
          enabled: !_emailBusy,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          textAlign: TextAlign.center,
          maxLength: 6,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontSize: 26, letterSpacing: 10),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          // Auto-verifikacija čim je svih 6 znamenki upisano (i kod paste-a).
          onChanged: (v) {
            if (v.length == 6 && !_emailBusy) _verifyEmailCode();
          },
          onSubmitted: (_) => _verifyEmailCode(),
          decoration: const InputDecoration(
            hintText: '••••••',
            counterText: '',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorNote(message: _error!),
        ],
        if (_notice != null) ...[
          const SizedBox(height: 12),
          _NoticeNote(message: _notice!),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _emailBusy ? null : _verifyEmailCode,
          child: _emailBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Potvrdi'),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: (_resendSeconds > 0 || _emailBusy)
                  ? null
                  : _resendEmailCode,
              child: Text(
                _resendSeconds > 0
                    ? 'Pošalji novi kod (${_resendSeconds}s)'
                    : 'Pošalji novi kod',
              ),
            ),
            TextButton(
              onPressed: _emailBusy ? null : _backToEmailEntry,
              child: Text(
                'Promijeni e-mail',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ];

  // ── copy ───────────────────────────────────────────────────────────────

  String _title() => switch (_view) {
        _SheetView.providers =>
          widget.headlineOverride ?? _defaultHeadline(),
        _SheetView.emailEntry => 'Prijava e-mailom',
        _SheetView.otpEntry => 'Provjeri e-mail',
      };

  String _subtitle() => switch (_view) {
        _SheetView.providers =>
          widget.subtitleOverride ?? _defaultSubtitle(),
        _SheetView.emailEntry =>
          'Pošaljemo ti link i 6-znamenkasti kod za prijavu — bez lozinke.',
        _SheetView.otpEntry =>
          'Poslali smo link i kod na $_otpEmail. Upiši kod — ili klikni link u e-mailu.',
      };

  String _defaultHeadline() => switch (origin) {
        AuthSheetOrigin.account => 'Prijavi se na DOMOVINA.ai',
        AuthSheetOrigin.moment2 => 'Spremi napredak na sve uređaje',
        AuthSheetOrigin.moment3 => 'Spremi favorite u svoj račun',
        AuthSheetOrigin.handoff => 'Završi prijavu na ovom uređaju',
      };

  String _defaultSubtitle() => switch (origin) {
        AuthSheetOrigin.account =>
          'Bez lozinke. Passkey ili tvoj postojeći Google / Apple račun.',
        AuthSheetOrigin.moment2 =>
          'Trenutno tvoja pozicija reprodukcije ostaje samo na ovom uređaju.',
        AuthSheetOrigin.moment3 =>
          'Da favoriti ostanu dostupni na svim tvojim uređajima.',
        AuthSheetOrigin.handoff =>
          'Kod je verificiran — odaberi kako želiš nastaviti.',
      };

  // ── actions ────────────────────────────────────────────────────────────

  Future<void> _doLink(AuthProvider p) async {
    if (_busy) return;
    setState(() {
      _pending = p;
      _error = null;
      _notice = null;
    });
    // NE popati sheet prije async rada — context bi se unmountao pa bi
    // linkIdentity rano izašao na `context.mounted` guardu. Sheet ostaje
    // otvoren tijekom operacije (dialozi/WebAuthn idu preko njega), pop poslije.
    final result = await AuthService.instance.linkIdentity(context, p);
    if (!mounted) return;
    setState(() => _pending = null);
    if (result.status == AuthFlowStatus.success ||
        result.status == AuthFlowStatus.redirect) {
      // Eksplicitno (poslije _setUser zapisa) jer passkey user u GoTrue
      // izgleda kao 'email' identitet.
      setLocalStorageString(lastProviderKey, p.name);
    }
    _handleResult(result);
  }

  Future<void> _signInWithExistingPasskey() async {
    if (_busy) return;
    setState(() {
      _passkeyLoginPending = true;
      _error = null;
      _notice = null;
    });
    final result = await AuthService.instance.signInWithPasskey(context);
    if (!mounted) return;
    setState(() => _passkeyLoginPending = false);
    if (result.status == AuthFlowStatus.success) {
      setLocalStorageString(lastProviderKey, AuthProvider.passkey.name);
    }
    if (result.passkeyMissing) {
      // Nema passkeyja na uređaju → uputi na druge metode. Kreiranje NIJE
      // ovdje (anti multiple-passkeys/accounts) — dodaje se u Moj račun
      // nakon prijave, vezano uz postojeći račun.
      setState(() => _notice =
          'Na ovom uređaju još nema passkeyja za DOMOVINA.ai. Prijavi se '
          'drugom metodom — passkey zatim dodaš u Moj račun.');
      return;
    }
    _handleResult(result);
  }

  void _openEmailEntry() {
    setState(() {
      _view = _SheetView.emailEntry;
      _error = null;
      _notice = null;
    });
  }

  void _backToProviders() {
    setState(() {
      _view = _SheetView.providers;
      _error = null;
      _notice = null;
    });
  }

  void _backToEmailEntry() {
    setState(() {
      _view = _SheetView.emailEntry;
      _error = null;
      _notice = null;
      _otpCtrl.clear();
    });
  }

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  Future<void> _sendEmailCode() async {
    final email = _emailCtrl.text.trim();
    if (!_emailRe.hasMatch(email)) {
      setState(() => _error = 'Unesi ispravnu e-mail adresu.');
      return;
    }
    setState(() {
      _emailBusy = true;
      _error = null;
      _notice = null;
    });
    final result = await AuthService.instance.sendEmailOtp(email);
    if (!mounted) return;
    setState(() => _emailBusy = false);
    if (result.status == AuthFlowStatus.emailSent) {
      setState(() {
        _otpEmail = email;
        _otpCtrl.clear();
        _view = _SheetView.otpEntry;
      });
      _startResendCountdown();
    } else {
      setState(() => _error = result.message ?? 'Slanje nije uspjelo.');
    }
  }

  Future<void> _resendEmailCode() async {
    setState(() {
      _emailBusy = true;
      _error = null;
      _notice = null;
      _otpCtrl.clear();
    });
    final result = await AuthService.instance.sendEmailOtp(_otpEmail);
    if (!mounted) return;
    setState(() {
      _emailBusy = false;
      if (result.status == AuthFlowStatus.emailSent) {
        _notice = 'Novi kod poslan na $_otpEmail.';
      } else {
        _error = result.message ?? 'Slanje nije uspjelo.';
      }
    });
    if (result.status == AuthFlowStatus.emailSent) _startResendCountdown();
  }

  Future<void> _verifyEmailCode() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Kod ima 6 znamenki.');
      return;
    }
    setState(() {
      _emailBusy = true;
      _error = null;
      _notice = null;
    });
    final result = await AuthService.instance.verifyEmailOtp(_otpEmail, code);
    if (!mounted) return;
    setState(() => _emailBusy = false);
    if (result.status == AuthFlowStatus.success) {
      _handleResult(result);
    } else {
      setState(() {
        _error = result.message ?? 'Kod nije ispravan.';
        _otpCtrl.clear();
      });
    }
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = _resendCooldown);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) t.cancel();
      });
    });
  }

  void _handleResult(AuthFlowResult result) {
    switch (result.status) {
      case AuthFlowStatus.success:
      case AuthFlowStatus.redirect:
        // Web OAuth: full-page redirect ionako slijedi; pop je no-op u praksi.
        Navigator.of(context).pop();
        if (result.status == AuthFlowStatus.success &&
            result.message != null) {
          rootScaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(content: Text(result.message!)),
          );
        }
      case AuthFlowStatus.emailSent:
        Navigator.of(context).pop();
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
                'Link i kod poslani na ${result.message ?? 'tvoj e-mail'} — '
                'provjeri sandučić.'),
            duration: const Duration(seconds: 5),
          ),
        );
      case AuthFlowStatus.cancelled:
        // Korisnik odustao — sheet ostaje otvoren, bez greške.
        break;
      case AuthFlowStatus.failure:
        setState(() => _error = result.message ?? 'Prijava nije uspjela.');
    }
  }
}

/// Pravna linija s linkovima na uvjete/privatnost — industry standard ispod
/// providera (i App Store review ju očekuje uz kreiranje računa).
class _LegalLine extends StatelessWidget {
  const _LegalLine();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final base = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontSize: 11.5,
      height: 1.4,
    );
    final link = base?.copyWith(
      color: cs.primary,
      decoration: TextDecoration.underline,
      decorationColor: cs.primary.withValues(alpha: 0.5),
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'Nastavkom prihvaćaš '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => context.push('/terms'),
              child: Text('Uvjete korištenja', style: link),
            ),
          ),
          const TextSpan(text: ' i '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () => context.push('/privacy'),
              child: Text('Pravila privatnosti', style: link),
            ),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Inline greška u sheetu — ostaje vidljiva uz provider tile-ove pa korisnik
/// može odmah pokušati ponovo (umjesto snackbara koji nestane).
class _ErrorNote extends StatelessWidget {
  final String message;
  const _ErrorNote({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onErrorContainer,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Neutralna inline obavijest (npr. "novi kod poslan").
class _NoticeNote extends StatelessWidget {
  final String message;
  const _NoticeNote({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.mark_email_read_outlined, size: 17, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Suptilna "papirnata" napomena o privatnosti / čuvanju napretka.
class _ReassuranceNote extends StatelessWidget {
  final AuthSheetOrigin origin;
  const _ReassuranceNote({required this.origin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 17, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tvoj trenutni napredak ostaje sačuvan i sigurno se povezuje s računom.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
