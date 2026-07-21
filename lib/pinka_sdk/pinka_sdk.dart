/// # Pinka Flutter SDK (embedded)
///
/// Samostalna, reusable reimplementacija pinka.io "Zida podrške" — crowdfunding
/// / donacijske kampanje s **SEPA** (EPC QR, bez naknade) i **on-chain** (EURe
/// na Gnosisu preko MPT protokola) uplatama, plus živi zid javnih doprinosa.
///
/// Backend je dijeljeni `domovina-api` Supabase (schema `pinka_finance`) +
/// rail `pay.domovina.ai` — identičan onome koji koristi pinka.io. Sve ovisnosti
/// idu kroz [PinkaClient] / [PinkaConfig], pa se ovaj folder može jednog dana
/// podići u zaseban package bez izmjena. Vidi `lib/pinka_sdk/README.md`.
///
/// ## Brzi start (kanal)
/// ```dart
/// // Kompaktna kartica (sakrije se ako kanal nema aktivnu kampanju):
/// PinkaSupportCard.channel(
///   channelId: channelId,
///   youtubeChannelId: detail.youtubeChannelId, // opcionalno, drugi kandidat
///   onOpen: (_) => context.push('/c/$slug/support'),
/// );
///
/// // Pun ekran (ruta /c/:slug/support):
/// PinkaCampaignScreen.channel(
///   channelId: channelId,
///   youtubeChannelId: youtubeChannelId,
///   channelName: name,
/// );
/// ```
///
/// Vizija (dugoročno): isti widgeti rade i po epizodi — `*.episode(youtubeId:)`.
library;

export 'src/pinka_config.dart';
export 'src/pinka_client.dart';
export 'src/pinka_admin_client.dart';
export 'src/models/pinka_campaign.dart';
export 'src/models/pinka_owner_campaign.dart';
export 'src/models/pinka_payout.dart';
export 'src/models/pinka_yield_position.dart';
export 'src/models/pinka_contribution_intent.dart';
export 'src/models/pinka_public_contribution.dart';
export 'src/models/pinka_link_preview.dart';
export 'src/models/pinka_onchain_confirm.dart';
export 'src/models/pinka_slot.dart';
export 'src/widgets/pinka_common.dart' show pinkaLaunch, PinkaCopyRow, PinkaLinkify;
export 'src/widgets/pinka_support_card.dart';
export 'src/widgets/pinka_support_bar.dart';
export 'src/widgets/pinka_contribute_panel.dart';
export 'src/widgets/pinka_wall_list.dart';
export 'src/screens/pinka_campaign_screen.dart';
