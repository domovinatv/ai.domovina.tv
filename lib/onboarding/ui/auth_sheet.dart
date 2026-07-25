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
import '../../l10n/app_localizations.dart';
import '../../main.dart' show rootScaffoldMessengerKey;
import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/local_prefs.dart';
import 'auth_ui.dart';

enum AuthSheetOrigin { account, guest, moment3, handoff }

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
  // useSafeArea: BEZ njega sheet (isScrollControlled + dug sadržaj) izraste
  // ispod statusne trake pa drag handle završi pod iOS Dynamic Islandom —
  // korisnik ga ne može uhvatiti ni zatvoriti sheet gestom.
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.92,
    ),
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

  /// Nakon pogrešnog koda polje se prazni — bez vraćanja fokusa korisnik na
  /// mobitelu mora ponovo tapnuti polje da mu se digne tipkovnica.
  final _otpFocus = FocusNode();
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

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  bool get _isSubView => _view != _SheetView.providers;

  /// Korak unatrag (OTP → e-mail → providers). Vraća false ako smo na prvom
  /// koraku — tada sistemski back smije zatvoriti sheet.
  bool _stepBack() {
    switch (_view) {
      case _SheetView.otpEntry:
        _backToEmailEntry();
        return true;
      case _SheetView.emailEntry:
        _backToProviders();
        return true;
      case _SheetView.providers:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Sistemski back (Android) / swipe na pod-koraku vraća korak unatrag
    // umjesto da ubije cijeli flow — inače korisnik s OTP koraka izgubi
    // poslani kôd jednim promašenim gestom.
    return PopScope(
      canPop: !_isSubView,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        _stepBack();
      },
      child: Semantics(
        identifier: 'auth-sheet',
        explicitChildNodes: true,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.only(
                left: 22,
                right: 22,
                top: 0,
                bottom: 18 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _topBar(cs),
                    AuthBrandHeader(
                      title: _title(),
                      subtitle: _subtitle(),
                      // Pod-koraci: bez logo bloka. S otvorenom tipkovnicom
                      // brand header pojede pola sheeta pa CTA ode van ekrana.
                      compact: _isSubView,
                    ),
                    const SizedBox(height: 20),
                    // Greška/obavijest IZNAD akcija: passkey tile je na vrhu
                    // pa bi poruka ispod zadnjeg providera često bila izvan
                    // vidljivog dijela sheeta.
                    if (_error != null) ...[
                      _ErrorNote(message: _error!),
                      const SizedBox(height: 14),
                    ],
                    if (_notice != null) ...[
                      _NoticeNote(message: _notice!),
                      const SizedBox(height: 14),
                    ],
                    ...switch (_view) {
                      _SheetView.providers => _providerChildren(),
                      _SheetView.emailEntry => _emailEntryChildren(),
                      _SheetView.otpEntry => _otpEntryChildren(theme, cs),
                    },
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Natrag (samo na pod-koracima) + uvijek dostupan ✕. Na iOS-u je gesta
  /// zatvaranja jedina alternativa, a ona zna kolidirati s drag handleom.
  Widget _topBar(ColorScheme cs) {
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          if (_isSubView)
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              tooltip: l.commonBack,
              visualDensity: VisualDensity.compact,
              color: cs.onSurfaceVariant,
              onPressed: _busy ? null : _stepBack,
            ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: l.commonClose,
            visualDensity: VisualDensity.compact,
            color: cs.onSurfaceVariant,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ── providers view ─────────────────────────────────────────────────────

  /// Redoslijed metoda kad korisnik nema povijest prijave.
  static const _defaultOrder = [
    AuthProvider.passkey,
    AuthProvider.certilia,
    AuthProvider.google,
    AuthProvider.apple,
    AuthProvider.email,
  ];

  List<Widget> _providerChildren() {
    // Returning user: metoda kojom se zadnji put prijavio ide na vrh kao
    // istaknuti tile. Bez toga bi mu passkey (koji možda nema) bio primarni
    // CTA, a njegova stvarna metoda peta u nizu — glavni uzrok "slučajno sam
    // otvorio drugi račun".
    final lead = _lastUsed ?? AuthProvider.passkey;
    final rest = _defaultOrder.where((p) => p != lead);
    return [
      _providerTile(lead, primary: true),
      const SizedBox(height: 12),
      LabeledDivider(label: AppLocalizations.of(context).authOr),
      const SizedBox(height: 16),
      for (final p in rest) ...[
        _providerTile(p, primary: false),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 8),
      _ReassuranceNote(origin: origin),
      const SizedBox(height: 10),
      const _LegalLine(),
    ];
  }

  /// Jedan provider tile. [primary] = istaknuti (navy) na vrhu liste.
  ///
  /// Passkey ovdje radi samo LOGIN — kreiranje namjerno nije u sheetu: novi
  /// korisnik bi si nakreirao više passkeyja (i računa) u Apple/Google
  /// manageru. Ključ se dodaje u Moj račun NAKON prijave → 1 osoba = 1 račun
  /// s N providera (GoTrue merga po e-mailu).
  Widget _providerTile(AuthProvider p, {required bool primary}) {
    final l = AppLocalizations.of(context);
    final badge = _lastUsed == p
        ? l.authBadgeLastUsed
        : (primary ? l.authBadgeRecommended : null);
    final badgeColor = _lastUsed == p ? AppTheme.croBlue : AppTheme.croRed;

    final (Widget icon, Color iconBg, String label, String? sub) = switch (p) {
      AuthProvider.passkey => (
          Icon(Icons.fingerprint,
              color: primary ? Colors.white : AppTheme.croBlue, size: 22),
          primary
              ? Colors.white.withValues(alpha: 0.16)
              : AppTheme.croBlue.withValues(alpha: 0.10),
          l.authSignInWithPasskey,
          l.authPasskeyTileSub,
        ),
      AuthProvider.certilia => (
          Icon(Icons.badge_outlined,
              color: primary ? Colors.white : AppTheme.croRed, size: 22),
          primary
              ? Colors.white.withValues(alpha: 0.16)
              : AppTheme.croRed.withValues(alpha: 0.10),
          l.authSignInWithEid,
          l.authProviderCertilia,
        ),
      // Službeni Google "G" asset (brand guidelines) na bijeloj podlozi.
      AuthProvider.google => (
          Image.asset(
            'assets/icons/google_g_logo.png',
            width: 22,
            height: 22,
            filterQuality: FilterQuality.high,
          ),
          Colors.white,
          l.authContinueWithGoogle,
          null,
        ),
      AuthProvider.apple => (
          const Icon(Icons.apple, color: Colors.white, size: 24),
          const Color(0xFF111111),
          l.authContinueWithApple,
          null,
        ),
      AuthProvider.email => (
          Icon(Icons.alternate_email,
              color: primary ? Colors.white : AppTheme.croBlue, size: 21),
          primary
              ? Colors.white.withValues(alpha: 0.16)
              : AppTheme.croBlue.withValues(alpha: 0.10),
          l.authEmailMagicLink,
          l.authEmailTileSub,
        ),
    };

    return AuthProviderTile(
      identifier: 'auth-provider-${p.name}',
      primary: primary,
      iconChild: icon,
      iconBg: iconBg,
      label: label,
      subtitle: sub,
      badge: badge,
      badgeColor: badgeColor,
      enabled: !_busy,
      loading: switch (p) {
        AuthProvider.passkey => _passkeyLoginPending,
        AuthProvider.email => false,
        _ => _pending == p,
      },
      onTap: switch (p) {
        AuthProvider.passkey => _signInWithExistingPasskey,
        AuthProvider.email => _openEmailEntry,
        _ => () => _doLink(p),
      },
    );
  }

  // ── e-mail entry view ──────────────────────────────────────────────────

  List<Widget> _emailEntryChildren() {
    final l = AppLocalizations.of(context);
    return [
      AutofillGroup(
        child: TextField(
          controller: _emailCtrl,
          autofocus: true,
          enabled: !_emailBusy,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _sendEmailCode(),
          decoration: InputDecoration(
            hintText: l.authEmailHint,
            prefixIcon: const Icon(Icons.alternate_email, size: 20),
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _emailBusy ? null : _sendEmailCode,
        child: _emailBusy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(l.authSendCode),
      ),
      const SizedBox(height: 12),
      const _LegalLine(),
    ];
  }

  // ── OTP entry view ─────────────────────────────────────────────────────

  List<Widget> _otpEntryChildren(ThemeData theme, ColorScheme cs) {
    final l = AppLocalizations.of(context);
    return [
        TextField(
          controller: _otpCtrl,
          focusNode: _otpFocus,
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
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _emailBusy ? null : _verifyEmailCode,
          child: _emailBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.commonConfirm),
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
                    ? l.authResendCodeIn(_resendSeconds)
                    : l.authResendCode,
              ),
            ),
            TextButton(
              onPressed: _emailBusy ? null : _backToEmailEntry,
              child: Text(
                l.authChangeEmail,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ];
  }

  // ── copy ───────────────────────────────────────────────────────────────

  String _title() {
    final l = AppLocalizations.of(context);
    return switch (_view) {
      _SheetView.providers => widget.headlineOverride ?? _defaultHeadline(),
      _SheetView.emailEntry => l.authEmailTitle,
      _SheetView.otpEntry => l.authCheckEmail,
    };
  }

  String _subtitle() {
    final l = AppLocalizations.of(context);
    return switch (_view) {
      _SheetView.providers => widget.subtitleOverride ?? _defaultSubtitle(),
      _SheetView.emailEntry => l.authEmailEntrySub,
      _SheetView.otpEntry => l.authOtpSentTo(_otpEmail),
    };
  }

  String _defaultHeadline() {
    final l = AppLocalizations.of(context);
    return switch (origin) {
      AuthSheetOrigin.account => l.authHeadlineAccount,
      AuthSheetOrigin.guest => l.authHeadlineGuest,
      AuthSheetOrigin.moment3 => l.authHeadlineMoment3,
      AuthSheetOrigin.handoff => l.authHeadlineHandoff,
    };
  }

  String _defaultSubtitle() {
    final l = AppLocalizations.of(context);
    return switch (origin) {
      AuthSheetOrigin.account => l.authSubAccount,
      AuthSheetOrigin.guest => l.authSubGuest,
      AuthSheetOrigin.moment3 => l.authSubMoment3,
      AuthSheetOrigin.handoff => l.authSubHandoff,
    };
  }

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
          AppLocalizations.of(context).authPasskeyMissingNotice);
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
      setState(() => _error = AppLocalizations.of(context).authInvalidEmail);
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
      setState(() => _error =
          result.message ?? AppLocalizations.of(context).authSendFailed);
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
    final l = AppLocalizations.of(context);
    setState(() {
      _emailBusy = false;
      if (result.status == AuthFlowStatus.emailSent) {
        _notice = l.authNewCodeSentTo(_otpEmail);
      } else {
        _error = result.message ?? l.authSendFailed;
      }
    });
    if (result.status == AuthFlowStatus.emailSent) _startResendCountdown();
  }

  Future<void> _verifyEmailCode() async {
    final code = _otpCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = AppLocalizations.of(context).authCode6Digits);
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
        _error =
            result.message ?? AppLocalizations.of(context).authCodeInvalid;
        _otpCtrl.clear();
      });
      _otpFocus.requestFocus();
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
        final l = AppLocalizations.of(context);
        Navigator.of(context).pop();
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
                l.authLinkCodeSent(result.message ?? l.authYourEmail)),
            duration: const Duration(seconds: 5),
          ),
        );
      case AuthFlowStatus.cancelled:
        // Korisnik odustao — sheet ostaje otvoren, bez greške.
        break;
      case AuthFlowStatus.failure:
        setState(() => _error =
            result.message ?? AppLocalizations.of(context).authSignInFailed);
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
    final l = AppLocalizations.of(context);
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
    // MouseRegion + vertikalni padding: goli GestureDetector u WidgetSpanu
    // nema pointer kursor na webu i daje tap target visine teksta (~14 px).
    WidgetSpan legalLink(String text, String route) => WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => context.push(route),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(text, style: link),
              ),
            ),
          ),
        );

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: l.authLegalPrefix),
          legalLink(l.authLegalTerms, '/terms'),
          TextSpan(text: l.authLegalAnd),
          legalLink(l.authLegalPrivacy, '/privacy'),
          TextSpan(text: l.authLegalSuffix),
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
              AppLocalizations.of(context).authReassurance,
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
