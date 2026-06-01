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
  /// Interni channel slug (kao `/c/:id`). Screen iz njega dohvati UC… ID.
  final String channelId;
  const ChannelOwnershipScreen({super.key, required this.channelId});

  @override
  State<ChannelOwnershipScreen> createState() => _ChannelOwnershipScreenState();
}

class _ChannelOwnershipScreenState extends State<ChannelOwnershipScreen> {
  ChannelDetail? _channel;
  ChannelClaim? _claim;
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
      final channel = await ChannelService.loadChannel(widget.channelId);
      final ucId = channel.youtubeChannelId;
      final claim = ucId == null
          ? null
          : await ChannelOwnershipService.instance.myClaimFor(ucId);
      if (!mounted) return;
      setState(() {
        _channel = channel;
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
    final ucId = _channel?.youtubeChannelId;
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
    final channel = _channel;

    if (!auth.isSignedIn) {
      return [
        _infoCard(context, 'Za preuzimanje kanala prvo se prijavi.'),
      ];
    }
    if (channel == null) {
      return [_infoCard(context, _error ?? 'Kanal nije pronađen.')];
    }
    if (channel.youtubeChannelId == null) {
      return [
        _infoCard(
            context,
            'Ovaj kanal još nema povezan YouTube identifikator pa preuzimanje '
            'trenutno nije moguće.'),
      ];
    }

    final eligibility = PayoutEligibility.evaluate(
      claim: _claim,
      isKycVerified: auth.currentUser?.isVerified ?? false,
      now: DateTime.now(),
    );

    return [
      Text(channel.name, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(channel.youtubeChannelId!,
          style: Theme.of(context).textTheme.bodySmall),
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
    ];
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
        _done = true;
      });
    }
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
              Text(_message, textAlign: TextAlign.center),
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
                    const Text('Još nemaš nijedan preuzet kanal.')
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
        trailing: needsReverify
            ? TextButton(
                onPressed: () => _reverify(c),
                child: const Text('Ponovi'),
              )
            : null,
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
