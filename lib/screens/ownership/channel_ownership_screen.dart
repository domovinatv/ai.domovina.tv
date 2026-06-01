/// Channel ownership UI — vlasnik preuzima kanal, verificira identitet,
/// registrira wallet i postaje Safe co-signer. Tri ekrana (go_router rute):
///   - `ChannelOwnershipScreen`     (`/c/:channelId/claim`)    — per-kanal flow
///   - `YoutubeClaimCallbackScreen` (`/youtube-claim/callback`) — OAuth povratak
///   - `MyChannelsScreen`           (`/account/channels`)      — lista claimova
/// Vidi docs/channel-ownership-and-safe-payout-plan.md §5–§11.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../main.dart' show log;
import '../../models/channel_claim.dart';
import '../../models/channel_detail.dart';
import '../../models/owner_wallet.dart';
import '../../models/payout_eligibility.dart';
import '../../services/auth_service.dart';
import '../../services/channel_ownership_service.dart';
import '../../services/data_service.dart';
import '../../services/wallet_service.dart';

// ───────────────────────────────────────────────────────────────────────────
// Per-channel claim flow
// ───────────────────────────────────────────────────────────────────────────

class ChannelOwnershipScreen extends StatefulWidget {
  /// Interni channel slug (kao `/c/:id`) — screen iz njega dohvati UC… ID.
  /// Alternativno (npr. iz "Moji kanali") otvori se direktno po [youtubeChannelId]
  /// (UC…), bez učitavanja channel.json — naziv se uzme iz claima.
  final String? channelId;
  final String? youtubeChannelId;
  const ChannelOwnershipScreen({super.key, this.channelId, this.youtubeChannelId})
      : assert(channelId != null || youtubeChannelId != null,
            'Treba channelId (slug) ili youtubeChannelId (UC…)');

  @override
  State<ChannelOwnershipScreen> createState() => _ChannelOwnershipScreenState();
}

class _ChannelOwnershipScreenState extends State<ChannelOwnershipScreen> {
  ChannelDetail? _channel;
  ChannelClaim? _claim;
  String? _ucId;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      ChannelDetail? channel;
      String? ucId = widget.youtubeChannelId;
      if (widget.channelId != null) {
        channel = await ChannelService.loadChannel(widget.channelId!);
        ucId = channel.youtubeChannelId;
      }
      final claim = ucId == null
          ? null
          : await ChannelOwnershipService.instance.myClaimFor(ucId);
      if (!mounted) return;
      setState(() {
        _channel = channel;
        _ucId = ucId;
        _claim = claim;
        _loading = false;
      });
    } catch (e) {
      log('ownership load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Učitavanje kanala nije uspjelo.';
        _loading = false;
      });
    }
  }

  Future<void> _startClaim() async {
    final ucId = _ucId;
    if (ucId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final authUrl = await ChannelOwnershipService.instance.startClaim(ucId);
      final uri = Uri.parse(authUrl);
      // Web: redirect u istom tabu (callback dođe na /youtube-claim/callback).
      // Native: vanjski browser → ai.domovina:// deep link natrag.
      await launchUrl(
        uri,
        mode:
            kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_self' : null,
      );
    } on ChannelOwnershipFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      log('startClaim launch failed: $e');
      if (!mounted) return;
      setState(() => _error = 'Otvaranje autorizacije nije uspjelo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vlasništvo kanala')),
      body: AnimatedBuilder(
        animation: AuthService.instance,
        builder: (context, _) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: _buildBody(context),
          );
        },
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context) {
    final auth = AuthService.instance;
    final ucId = _ucId;
    final title = _channel?.name ?? _claim?.channelTitle ?? ucId;

    if (!auth.isSignedIn) {
      return [
        _infoCard(context, 'Za preuzimanje kanala prvo se prijavi.'),
      ];
    }
    if (ucId == null) {
      return [
        _infoCard(
            context,
            _error ??
                (widget.channelId != null
                    ? 'Ovaj kanal još nema povezan YouTube identifikator pa '
                        'preuzimanje trenutno nije moguće.'
                    : 'Kanal nije pronađen.')),
      ];
    }

    final eligibility = PayoutEligibility.evaluate(
      claim: _claim,
      isKycVerified: auth.currentUser?.isVerified ?? false,
      now: DateTime.now(),
    );

    return [
      Text(title ?? ucId, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(ucId, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 24),
      if (_error != null) ...[
        _errorBanner(context, _error!),
        const SizedBox(height: 16),
      ],
      _stepOwnership(context, eligibility),
      const SizedBox(height: 12),
      _stepKyc(context, eligibility),
      const SizedBox(height: 12),
      _stepWalletAndSafe(context, eligibility),
      if (widget.channelId != null && _claim?.isVerified != true) ...[
        const SizedBox(height: 20),
        _inviteOwnerCard(context, title ?? ucId),
      ],
    ];
  }

  // Poziv vlasniku kanala preko WhatsAppa (za korisnika koji nije vlasnik, ali
  // ga poznaje). wa.me/?text=… otvara WhatsApp s prefilanom porukom i pušta
  // korisnika da odabere primatelja (ne treba broj).
  Widget _inviteOwnerCard(BuildContext context, String channelTitle) {
    final slugDashed = widget.channelId!.replaceAll('_', '-');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nisi ti vlasnik kanala?',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            const Text(
              'Ako poznaješ vlasnika, pošalji mu poruku da preuzme vlasništvo i '
              'verificira se na DOMOVINA.ai.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _inviteOwnerWhatsApp(channelTitle, slugDashed),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Pozovi vlasnika (WhatsApp)'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _inviteOwnerWhatsApp(
      String channelTitle, String slugDashed) async {
    final link = 'https://domovina.ai/c/$slugDashed';
    final msg = 'Pozdrav! Tvoj YouTube kanal "$channelTitle" je na DOMOVINA.ai. '
        'Možeš besplatno preuzeti vlasništvo i upravljati svojim sadržajem te '
        'isplatama — verificiraj se kao vlasnik kanala ovdje: $link';
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    await launchUrl(uri,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication);
  }

  // Step 1 — vlasništvo (YouTube OAuth).
  Widget _stepOwnership(BuildContext context, PayoutEligibility e) {
    final claim = _claim;
    final reverify = e.block == EligibilityBlock.reverifyNeeded;
    final done = claim?.isVerified == true && !reverify;
    return _stepCard(
      context,
      index: 1,
      done: done,
      title: 'Potvrdi vlasništvo',
      subtitle: reverify
          ? 'Vlasništvo je starije od 90 dana — potvrdi ponovo.'
          : claim?.isVerified == true
              ? 'Vlasništvo potvrđeno preko YouTube računa.'
              : 'Prijavi se YouTube računom koji posjeduje ovaj kanal.',
      note: done
          ? null
          : 'Vlasništvo može preuzeti samo Google račun koji je VLASNIK kanala. '
              'Uređivači i menadžeri dodani u YouTube postavkama (Channel permissions) '
              'ne mogu — YouTube ih ne prikazuje kao vlasnike. Ako kanal pripada Brand '
              'računu, prijavi se Google računom koji njime upravlja.',
      action: done
          ? null
          : FilledButton.icon(
              onPressed: _busy ? null : _startClaim,
              icon: const Icon(Icons.smart_display_outlined),
              label: Text(reverify ? 'Ponovi potvrdu' : 'Login with YouTube'),
            ),
    );
  }

  // Step 2 — KYC (Certilia eOsobna).
  Widget _stepKyc(BuildContext context, PayoutEligibility e) {
    final auth = AuthService.instance;
    final locked = _claim?.isVerified != true;
    final done = auth.currentUser?.isVerified ?? false;
    return _stepCard(
      context,
      index: 2,
      done: done,
      locked: locked,
      title: 'Verificiraj identitet',
      subtitle: done
          ? 'Identitet verificiran (eOsobna).'
          : 'Poveži eOsobnu (Certilia) — nužno prije isplate.',
      action: (locked || done)
          ? null
          : OutlinedButton.icon(
              onPressed: _busy ? null : () => _runKyc(context),
              icon: const Icon(Icons.badge_outlined),
              label: const Text('Verificiraj eOsobnom'),
            ),
    );
  }

  // Step 3 — wallet + Safe co-signer.
  Widget _stepWalletAndSafe(BuildContext context, PayoutEligibility e) {
    final locked = !e.isEligible;
    return _stepCard(
      context,
      index: 3,
      done: false,
      locked: locked,
      title: 'Poveži novčanik',
      subtitle: locked
          ? 'Dostupno nakon vlasništva i verifikacije identiteta.'
          : 'Registriraj adresu novčanika za isplatu (Safe co-signer).',
      action: locked
          ? null
          : FilledButton.icon(
              onPressed:
                  _busy ? null : () => context.push('/account/channels'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Upravljaj novčanikom'),
            ),
    );
  }

  Future<void> _runKyc(BuildContext context) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // AuthService spremi anon UUID + pokrene Certilia flow; app_metadata
      // .kyc_verified stigne preko onAuthStateChange.
      await AuthService.instance.signInWithCertilia(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── shared step UI ────────────────────────────────────────────────────────
  Widget _stepCard(
    BuildContext context, {
    required int index,
    required bool done,
    bool locked = false,
    required String title,
    required String subtitle,
    Widget? action,
    String? note,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final Color circleColor = done
        ? Colors.green
        : locked
            ? scheme.outlineVariant
            : scheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: circleColor,
              child: done
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : Text('$index',
                      style: const TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodyMedium),
                  if (note != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            note,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (action != null) ...[
                    const SizedBox(height: 12),
                    action,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(BuildContext context, String text) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(text),
        ),
      );

  Widget _errorBanner(BuildContext context, String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer)),
      );
}

// ───────────────────────────────────────────────────────────────────────────
// OAuth callback — /youtube-claim/callback?code&state
// ───────────────────────────────────────────────────────────────────────────

class YoutubeClaimCallbackScreen extends StatefulWidget {
  final String? code;
  final String? state;
  const YoutubeClaimCallbackScreen({super.key, this.code, this.state});

  @override
  State<YoutubeClaimCallbackScreen> createState() =>
      _YoutubeClaimCallbackScreenState();
}

class _YoutubeClaimCallbackScreenState
    extends State<YoutubeClaimCallbackScreen> {
  String _message = 'Provjeravam vlasništvo…';
  String? _boldTerm;
  bool _done = false;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _complete();
  }

  Future<void> _complete() async {
    final code = widget.code;
    final state = widget.state;
    if (code == null || state == null) {
      setState(() {
        _message = 'Nedostaju podaci autorizacije.';
        _done = true;
      });
      return;
    }
    try {
      final claim = await ChannelOwnershipService.instance
          .completeClaim(code: code, state: state);
      if (!mounted) return;
      setState(() {
        _ok = claim.isVerified;
        _message = claim.isVerified
            ? 'Vlasništvo potvrđeno: '
                '${claim.channelTitle ?? claim.youtubeChannelId}'
            : 'Zahtjev zaprimljen (status: ${claim.status.name}).';
        _done = true;
      });
    } on ChannelOwnershipFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.message;
        _boldTerm = e.boldTerm;
        _done = true;
      });
    }
  }

  // Poruka s opcionalno boldanim pojmom (npr. naziv kanala).
  Widget _messageWidget(BuildContext context) {
    final term = _boldTerm;
    final base = Theme.of(context).textTheme.bodyMedium;
    if (term == null || !_message.contains(term)) {
      return Text(_message, textAlign: TextAlign.center, style: base);
    }
    final i = _message.indexOf(term);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: _message.substring(0, i)),
          TextSpan(
              text: term,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: _message.substring(i + term.length)),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Potvrda vlasništva')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_done)
                const CircularProgressIndicator()
              else
                Icon(_ok ? Icons.verified : Icons.error_outline,
                    size: 48,
                    color: _ok
                        ? Colors.green
                        : Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              _messageWidget(context),
              if (_done) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/account/channels'),
                  child: const Text('Moji kanali'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Moji kanali + novčanik — /account/channels
// ───────────────────────────────────────────────────────────────────────────

class MyChannelsScreen extends StatefulWidget {
  const MyChannelsScreen({super.key});

  @override
  State<MyChannelsScreen> createState() => _MyChannelsScreenState();
}

class _MyChannelsScreenState extends State<MyChannelsScreen> {
  List<ChannelClaim> _claims = const [];
  List<OwnerWallet> _wallets = const [];
  bool _loading = true;
  final _walletCtrl = TextEditingController();
  String? _walletError;
  bool _walletBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _walletCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final claims = await ChannelOwnershipService.instance.myClaims();
    final wallets = await WalletService.instance.myWallets();
    if (!mounted) return;
    setState(() {
      _claims = claims;
      _wallets = wallets;
      _loading = false;
    });
  }

  Future<void> _addWallet() async {
    setState(() {
      _walletBusy = true;
      _walletError = null;
    });
    try {
      await WalletService.instance.register(_walletCtrl.text);
      _walletCtrl.clear();
      await _load();
    } on WalletFailure catch (e) {
      if (!mounted) return;
      setState(() => _walletError = e.message);
    } finally {
      if (mounted) setState(() => _walletBusy = false);
    }
  }

  Future<void> _reverify(ChannelClaim claim) async {
    try {
      await ChannelOwnershipService.instance.reverify(claim.id);
      await _load();
    } on ChannelOwnershipFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _confirmRevoke(ChannelClaim c) async {
    final name = c.channelTitle ?? c.youtubeChannelId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Otkvači vlasništvo?'),
        content: Text(
          'Odričeš se vlasništva nad kanalom "$name". Verifikacija i status '
          'isplate se poništavaju, a kanal postaje dostupan za novo preuzimanje. '
          'Možeš ga ponovno preuzeti bilo kada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Otkvači'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChannelOwnershipService.instance.revokeClaim(c.id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vlasništvo otkvačeno.')),
      );
    } on ChannelOwnershipFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moji kanali')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Preuzeti kanali',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_claims.isEmpty)
                    _emptyClaims(context)
                  else
                    ..._claims.map(_claimTile),
                  const SizedBox(height: 24),
                  Text('Novčanici za isplatu',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._wallets.map(_walletTile),
                  const SizedBox(height: 12),
                  _addWalletForm(context),
                ],
              ),
            ),
    );
  }

  Widget _emptyClaims(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Još nemaš nijedan preuzet kanal. Otvori kanal i klikni '
            '"Preuzmi vlasništvo" za pokretanje verifikacije.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.podcasts),
            label: const Text('Pregledaj kanale'),
          ),
        ],
      );

  Widget _claimTile(ChannelClaim c) {
    final needsReverify = c.needsReverify(DateTime.now());
    return Card(
      child: ListTile(
        leading: Icon(
          c.isVerified ? Icons.verified : Icons.hourglass_empty,
          color: c.isVerified ? Colors.green : null,
        ),
        title: Text(c.channelTitle ?? c.youtubeChannelId),
        subtitle: Text(
          '${c.status.name} · ${c.role.name}'
          '${needsReverify ? ' · treba ponovnu potvrdu' : ''}',
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Opcije',
          onSelected: (v) {
            if (v == 'reverify') _reverify(c);
            if (v == 'revoke') _confirmRevoke(c);
          },
          itemBuilder: (_) => [
            if (needsReverify)
              const PopupMenuItem(
                  value: 'reverify', child: Text('Ponovi potvrdu')),
            const PopupMenuItem(
              value: 'revoke',
              child: Text('Otkvači vlasništvo'),
            ),
          ],
        ),
        // Otvori per-kanal verifikacijski/upravljački ekran (po UC… ID-u).
        onTap: () => context.push('/account/channels/${c.youtubeChannelId}'),
      ),
    );
  }

  Widget _walletTile(OwnerWallet w) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_balance_wallet_outlined),
        title: Text(_shortAddr(w.address)),
        subtitle: Text(w.isVerified ? 'Verificiran' : 'Registriran'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            await WalletService.instance.remove(w.id);
            await _load();
          },
        ),
      ),
    );
  }

  Widget _addWalletForm(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _walletCtrl,
              decoration: InputDecoration(
                labelText: 'Adresa novčanika (0x…)',
                errorText: _walletError,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _walletBusy ? null : _addWallet,
              child: const Text('Dodaj novčanik'),
            ),
          ],
        ),
      ),
    );
  }

  String _shortAddr(String a) =>
      a.length > 12 ? '${a.substring(0, 6)}…${a.substring(a.length - 4)}' : a;
}
