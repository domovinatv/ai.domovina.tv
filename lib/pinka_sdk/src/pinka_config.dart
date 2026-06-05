library;

/// Konfiguracija Pinka SDK-a — chain konstante, edge-fn imena, schema.
///
/// Defaulti zrcale **produkcijski pinka.io** stack: Monerium EURe V2 na Gnosis
/// lancu, edge funkcije iz `domovina-api` (`pinka-contribute`,
/// `pinka-onchain-confirm`) i guest-pollable `contribution_status` RPC.
///
/// SDK je dizajniran kao samostalan feature (budući "Pinka Flutter SDK"): sve
/// vanjske ovisnosti idu kroz [PinkaConfig] + [PinkaClient] da se folder
/// `lib/pinka_sdk/` može jednog dana podići u zaseban package bez izmjena.
class PinkaConfig {
  const PinkaConfig({
    this.schema = 'pinka_finance',
    this.contributeFn = 'pinka-contribute',
    this.onchainConfirmFn = 'pinka-onchain-confirm',
    this.contributionStatusRpc = 'contribution_status',
    this.activeCampaignForSubjectRpc = 'active_campaign_for_subject',
    this.setCampaignEpisodesRpc = 'set_campaign_episodes',
    this.attachSubjectRpc = 'attach_campaign_subject',
    this.detachSubjectRpc = 'detach_campaign_subject',
    this.requestPayoutRpc = 'request_payout',
    this.setCampaignYieldRpc = 'set_campaign_yield',
    this.eureAddress = '0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430',
    this.gnosisChainId = 100,
    this.explorerBase = 'https://gnosisscan.io',
    this.walletSdkUrl = 'https://wallet.domovina.ai/sdk.js',
  });

  /// Postgres schema u domovina-api backendu (dijeljen s pinka.io).
  final String schema;

  /// Edge fn koja kreira pending doprinos + payment intent (SEPA rail / MPT).
  final String contributeFn;

  /// Edge fn koja verificira + kreditira on-chain (EURe) tx po hashu.
  final String onchainConfirmFn;

  /// SECURITY DEFINER RPC za guest polling stanja doprinosa (anon ne može
  /// čitati `contributions` red kroz RLS — vidi domovina-api migracije).
  final String contributionStatusRpc;

  /// SECURITY DEFINER read RPC: aktivna kampanja za subjekt iz legacy stupaca
  /// ILI `campaign_subjects` join tablice (multi-episode). Razrješava dual-source.
  final String activeCampaignForSubjectRpc;

  /// Admin RPC-evi (vlasnik kanala): zamjena seta epizoda + attach/detach subjekta.
  final String setCampaignEpisodesRpc;
  final String attachSubjectRpc;
  final String detachSubjectRpc;

  /// Payout request RPC (vlasnik ∧ KYC zatraži isplatu kampanje).
  final String requestPayoutRpc;

  /// Yield opt-in RPC (vlasnik uključi/isključi oplodnju sredstava kampanje).
  final String setCampaignYieldRpc;

  /// Monerium EURe V2 proxy na Gnosisu — emitira Transfer evente na campaign
  /// Safe i koristi se za on-chain verifikaciju (NE implementation adresa).
  final String eureAddress;

  /// Gnosis chain ID (EIP-155).
  final int gnosisChainId;

  /// Block explorer baza (Gnosisscan) za "Provjeri na lancu" linkove.
  final String explorerBase;

  /// DOMOVINA wallet iframe SDK (`wallet.domovina.ai/sdk.js`) — in-app EURe
  /// send preko WebAuthn passkeya. Web-only (vidi `wallet/pinka_wallet.dart`).
  final String walletSdkUrl;

  static const PinkaConfig defaults = PinkaConfig();

  /// EIP-681 ERC-20 `transfer` URI za EURe donaciju na campaign Safe.
  /// EURe ima 18 decimala; cents → wei = cents × 1e16.
  String eip681(String destination, int amountCents) {
    final wei =
        (BigInt.from(amountCents) * BigInt.from(10).pow(16)).toString();
    return 'ethereum:$eureAddress@$gnosisChainId/transfer'
        '?address=$destination&uint256=$wei';
  }

  /// EURe saldo campaign Safe-a na Gnosisscanu (svatko može provjeriti).
  String tokenBalanceUrl(String address) =>
      '$explorerBase/token/$eureAddress?a=$address';

  /// Povijest priljeva (token transferi) na campaign Safe.
  String tokenTxnsUrl(String address) =>
      '$explorerBase/address/$address#tokentxns';

  /// Saldo proizvoljnog tokena (npr. aGnoEURe) za dani Safe — za prikaz Aave
  /// (yield) pozicije kad su sredstva parkirana izvan EURe.
  String tokenForAddressUrl(String token, String address) =>
      '$explorerBase/token/$token?a=$address';
}

/// Kanonske `subject_type` vrijednosti za pinka kampanje.
///
/// Kampanja je vezana uz "subjekt" preko (`subject_type`, `subject_ref`).
/// Za kanal: ref = YouTube UC… id ILI domovina interni channel id (oboje se
/// pretražuje — vidi [PinkaClient.campaignForSubject]). Za epizodu: ref =
/// YouTube video id.
class PinkaSubject {
  PinkaSubject._();
  static const String channel = 'podcast_channel';
  static const String episode = 'podcast_episode';
}
