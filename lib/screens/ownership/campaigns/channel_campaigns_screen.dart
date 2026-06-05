import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../models/channel_claim.dart';
import '../../../pinka_sdk/pinka_sdk.dart';
import '../../../services/auth_service.dart';
import '../../../services/channel_ownership_service.dart';

/// Lista Pinka kampanja ankeriranih na verificirani kanal (UC… id). Ulaz iz
/// "Moji kanali". Faza A: pregled + ulaz u upravljanje (bez in-app kreiranja).
class ChannelCampaignsScreen extends StatefulWidget {
  final String youtubeChannelId; // UC…

  const ChannelCampaignsScreen({super.key, required this.youtubeChannelId});

  @override
  State<ChannelCampaignsScreen> createState() => _ChannelCampaignsScreenState();
}

class _ChannelCampaignsScreenState extends State<ChannelCampaignsScreen> {
  bool _loading = true;
  ChannelClaim? _claim;
  List<PinkaOwnerCampaign> _campaigns = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final claim =
        await ChannelOwnershipService.instance.myClaimFor(widget.youtubeChannelId);
    final campaigns = (claim?.isVerified ?? false)
        ? await PinkaAdminClient.instance
            .listCampaignsForChannel(widget.youtubeChannelId)
        : const <PinkaOwnerCampaign>[];
    if (!mounted) return;
    setState(() {
      _claim = claim;
      _campaigns = campaigns;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_claim?.channelTitle ?? 'Kampanje'),
      ),
      body: AnimatedBuilder(
        animation: AuthService.instance,
        builder: (context, _) {
          if (!AuthService.instance.isSignedIn) {
            return _info(theme, 'Za upravljanje kampanjama prvo se prijavi.');
          }
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!(_claim?.isVerified ?? false)) {
            return _info(
                theme, 'Nisi verificirani vlasnik ovog kanala.');
          }
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_campaigns.isEmpty)
                  _empty(theme)
                else
                  ..._campaigns.map((c) => _campaignTile(theme, c)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _campaignTile(ThemeData theme, PinkaOwnerCampaign c) {
    final raised = (c.totalRaisedCents / 100);
    final raisedStr = raised == raised.truncateToDouble()
        ? raised.toStringAsFixed(0)
        : raised.toStringAsFixed(2);
    return Card(
      child: ListTile(
        leading: Icon(
          c.state == 'active'
              ? Icons.campaign
              : c.state == 'draft'
                  ? Icons.edit_note
                  : Icons.flag,
          color: c.state == 'active' ? theme.colorScheme.tertiary : null,
        ),
        title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${_stateLabel(c.state)} · ${_visLabel(c.visibility)} · '
          '$raisedStr € · ${c.episodeRefs.length} epizoda',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(
          '/account/channels/${widget.youtubeChannelId}/campaigns/${c.id}',
        ),
      ),
    );
  }

  Widget _empty(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Još nema kampanja za ovaj kanal.',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              'Kampanje se kreiraju na pinka.io (gdje se generira i Safe za '
              'isplatu). Nakon kreiranja, poveži kampanju s kanalom da je možeš '
              'ovdje administrirati i dodijeliti epizodama.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(ThemeData theme, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(msg,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
    );
  }

  static String _stateLabel(String s) => switch (s) {
        'draft' => 'Skica',
        'active' => 'Aktivna',
        'funded' => 'Financirana',
        'closed' => 'Zatvorena',
        'cancelled' => 'Otkazana',
        _ => s,
      };

  static String _visLabel(String v) => switch (v) {
        'public' => 'Javna',
        'unlisted' => 'Neuvrštena',
        'private' => 'Privatna',
        _ => v,
      };
}
