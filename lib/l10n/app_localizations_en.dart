// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'DOMOVINA.ai';

  @override
  String get updateAvailable => 'A new version is available';

  @override
  String get updateRefresh => 'Refresh';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get commonBack => 'Back';

  @override
  String get commonSave => 'Save';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonDone => 'Done';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonRetry => 'Try again';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonShare => 'Share';

  @override
  String get commonCopyLink => 'Copy link';

  @override
  String get commonLinkCopied => 'Link copied';

  @override
  String get commonOk => 'OK';

  @override
  String get commonSignIn => 'Sign in';

  @override
  String get commonSignOut => 'Sign out';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonGoHome => 'Back to home';

  @override
  String get commonOpenSource => 'Open source';

  @override
  String get commonThanksForSupport => 'Thank you for your support';

  @override
  String commonErrorWithDetails(String details) {
    return 'Error: $details';
  }

  @override
  String get authAccountTitle => 'My account';

  @override
  String get authAnonTitle => 'You\'re not signed in yet';

  @override
  String get authAnonSubtitle =>
      'Sign in to manage your account, passkeys, and data.';

  @override
  String get authLearnAboutPlus => 'Discover DOMOVINA Plus';

  @override
  String get authSectionSubscription => 'Subscription';

  @override
  String get authSectionSignInMethods => 'Sign-in methods';

  @override
  String get authSectionPasskeys => 'Passkeys';

  @override
  String get authSectionDevices => 'Devices';

  @override
  String get authSectionDangerZone => 'Danger zone';

  @override
  String get authPlusThanks => 'Thank you for supporting the Croatian archive.';

  @override
  String get authDetails => 'Details';

  @override
  String get authBecomePlus => 'Get DOMOVINA Plus';

  @override
  String get authPlusBenefits =>
      'Sync, export, unlimited search, and support for the archive.';

  @override
  String get authUserFallback => 'User';

  @override
  String get authVerifiedIdentity => 'Verified identity (eID)';

  @override
  String get authNoLinkedMethods => 'No linked sign-in methods yet.';

  @override
  String get authProviderGoogle => 'Google account';

  @override
  String get authProviderApple => 'Apple account';

  @override
  String get authProviderEmail => 'Sign-in link or code by email';

  @override
  String get authProviderPasskey => 'Passkey';

  @override
  String get authProviderCertilia => 'Croatian eID (Certilia / NIAS)';

  @override
  String get authPasskeysSoon =>
      'Viewing and removing passkeys is coming soon. You can already add a new one.';

  @override
  String get authNoPasskeys =>
      'You have no passkeys yet. A passkey is the safest and fastest way to sign in — no password, just Face ID or your fingerprint.';

  @override
  String get authPasskeyFetchFailed => 'We couldn\'t load your passkeys.';

  @override
  String get authRemovePasskey => 'Remove passkey';

  @override
  String get authAddPasskeyHere => 'Add a passkey on this device';

  @override
  String get authWherePasskeyStored => 'Where is your passkey stored?';

  @override
  String authPasskeyHintBody(String steps) {
    return 'We recommend Apple Passwords or Google Password Manager — that way your passkey is tied to Face ID or your fingerprint and synced across all your devices. If you use an extension like LastPass or 1Password, turn it off for domovina.ai (or remove it as the default key manager), as it intercepts the passkey prompt and breaks sign-in.\n\n$steps';
  }

  @override
  String get authPasskeyStepsApple =>
      'Settings → Apps → Passwords → Password Options → \"AutoFill\" — choose Passwords (iCloud).';

  @override
  String get authPasskeyStepsAndroid =>
      'Settings → Passwords & accounts → Default passkey service → choose Google Password Manager.';

  @override
  String get authPasskeyStepsGeneric =>
      'In your OS settings, choose the system passkey manager (Apple Passwords or Google Password Manager).';

  @override
  String authPasskeyAdded(String date) {
    return 'added $date';
  }

  @override
  String authPasskeyLastUsed(String date) {
    return 'last used $date';
  }

  @override
  String get authPasskeyAddedToast => 'Passkey added.';

  @override
  String get authPasskeyAddFailed => 'Couldn\'t add passkey.';

  @override
  String get authRemovePasskeyTitle => 'Remove passkey?';

  @override
  String authRemovePasskeyBody(String name) {
    return '\"$name\" will no longer be able to sign in to this account. This action is permanent.';
  }

  @override
  String get authRemove => 'Remove';

  @override
  String get authPasskeyRemoved => 'Passkey removed.';

  @override
  String get authSwitchDevice => 'Switch to another device';

  @override
  String get authDevicesSubtitle =>
      'Generate a code and sign in on your TV or phone';

  @override
  String get authSignOutSubtitle =>
      'Continue as a guest — your data stays on your account';

  @override
  String get authDeleteAccount => 'Delete account';

  @override
  String get authDeleteAccountSubtitle =>
      'Permanently deletes your account, favorites, progress, and all related data.';

  @override
  String get authAccountDeleted => 'Your account has been deleted.';

  @override
  String get authDeleteFailed => 'Deletion failed.';

  @override
  String get authSignOutTitle => 'Sign out?';

  @override
  String get authSignOutBody =>
      'Your progress and favorites stay saved on your account — they\'ll return when you sign back in.';

  @override
  String get authDeleteConfirmTitle => 'Permanently delete account?';

  @override
  String get authDeleteConfirmWord => 'DELETE';

  @override
  String authDeleteConfirmBody(String word) {
    return 'This deletes your account, favorites, watch progress, passkeys, and all related settings. This action cannot be undone.\n\nType $word to confirm:';
  }

  @override
  String get authDeletePermanently => 'Delete permanently';

  @override
  String get authErrLinkExpired =>
      'Your sign-in link has expired — request a new one.';

  @override
  String get authErrUserBanned => 'This account is temporarily blocked.';

  @override
  String get authErrSignupDisabled =>
      'New account sign-ups are currently unavailable.';

  @override
  String get authErrAccessDenied => 'Sign-in was denied or cancelled.';

  @override
  String get authErrServerError =>
      'Server error — please try again in a minute.';

  @override
  String get authErrGeneric => 'Sign-in failed. Please try again.';

  @override
  String get authErrTimeout =>
      'Sign-in is taking too long or was interrupted. Please try again.';

  @override
  String authSignedInAs(String name) {
    return 'You\'re signed in as $name.';
  }

  @override
  String get authSigningIn => 'Signing you in…';

  @override
  String get authInviteTitle => 'Accept invitation';

  @override
  String get authInviteProcessing => 'Processing your invitation…';

  @override
  String get authInviteError =>
      'Something went wrong, or the link has expired.';

  @override
  String get authM3Toast =>
      'Saved on this device. Sync your favorites across all devices?';

  @override
  String get authSync => 'Sync';

  @override
  String get authTabSend => 'Send';

  @override
  String get authTabReceive => 'Receive';

  @override
  String get authHandoffSignInFirst => 'Sign in first';

  @override
  String get authHandoffSignInFirstBody =>
      'To move all your progress to another device, sign in here first — then the other device can access the same account.';

  @override
  String get authHandoffSendTitle => 'Send your sign-in to another device';

  @override
  String get authHandoffSendSheetSub =>
      'To send a sign-in to another device, sign in here first.';

  @override
  String get authHandoffSendBody =>
      'Open DOMOVINA.ai/handoff on the other device and enter the code below. The code is valid for 5 minutes.';

  @override
  String get authGenerateCode => 'Generate code';

  @override
  String get authNewCode => 'New code';

  @override
  String get authValid5Min => 'Valid for 5 minutes';

  @override
  String get authCodeCopied => 'Code copied';

  @override
  String get authHandoffReceiveTitle => 'Have a code from another device?';

  @override
  String get authHandoffReceiveBody =>
      'Enter the six-digit code from the other device to bring its account here.';

  @override
  String get authReceiveSignIn => 'Bring sign-in here';

  @override
  String get authCode6Digits => 'The code must be 6 digits.';

  @override
  String get authOpeningSignIn => 'Opening sign-in…';

  @override
  String get authOpeningSignInBody =>
      'If a browser opens, confirm the sign-in, then return to the app.';

  @override
  String get authSuccess => 'Success!';

  @override
  String get authSignInWithPasskey => 'Continue with a passkey';

  @override
  String get authPasskeyTileSub =>
      'Face ID or fingerprint — if you already added a key';

  @override
  String get authBadgeRecommended => 'Recommended';

  @override
  String get authBadgeLastUsed => 'Last used';

  @override
  String get authSignInWithEid => 'Continue with eID';

  @override
  String get authContinueWithGoogle => 'Continue with Google';

  @override
  String get authContinueWithApple => 'Continue with Apple';

  @override
  String get authEmailMagicLink => 'Continue with email';

  @override
  String get authEmailTileSub => 'We\'ll send you a link and a code to sign in';

  @override
  String get authEmailHint => 'name@example.com';

  @override
  String get authSendCode => 'Send code';

  @override
  String get authResendCode => 'Send a new code';

  @override
  String authResendCodeIn(int seconds) {
    return 'Send a new code (${seconds}s)';
  }

  @override
  String get authChangeEmail => 'Change email';

  @override
  String get authEmailTitle => 'Sign in with email';

  @override
  String get authCheckEmail => 'Check your email';

  @override
  String get authEmailEntrySub =>
      'We\'ll send you a link and a six-digit code to sign in — no password.';

  @override
  String authOtpSentTo(String email) {
    return 'We sent a link and a code to $email. Enter the code — or open the link in your email.';
  }

  @override
  String get authHeadlineAccount => 'Sign in to DOMOVINA.ai';

  @override
  String get authHeadlineMoment3 => 'Save favorites to your account';

  @override
  String get authHeadlineHandoff => 'Finish signing in on this device';

  @override
  String get authSubAccount =>
      'No password. Signing in for the first time creates your account.';

  @override
  String get authHeadlineGuest => 'Save your progress and favourites';

  @override
  String get authSubGuest =>
      'You\'re listening as a guest — progress and favourites stay only on this device.';

  @override
  String get authGuestBarTitle => 'You\'re listening as a guest';

  @override
  String get authGuestBarBody =>
      'Progress, favourites and settings stay on this device only';

  @override
  String get authSubMoment3 =>
      'So your favorites stay available on all your devices.';

  @override
  String get authSubHandoff =>
      'Your code is verified — choose how you\'d like to continue.';

  @override
  String get authPasskeyMissingNotice =>
      'There\'s no passkey for DOMOVINA.ai on this device yet. Sign in another way — then add a passkey in My account.';

  @override
  String get authInvalidEmail => 'Enter a valid email address.';

  @override
  String get authSendFailed => 'We couldn\'t send it.';

  @override
  String authNewCodeSentTo(String email) {
    return 'A new code was sent to $email.';
  }

  @override
  String get authCodeInvalid => 'That code isn\'t valid.';

  @override
  String get authSignInFailed => 'Sign-in failed.';

  @override
  String get authYourEmail => 'your email';

  @override
  String authLinkCodeSent(String email) {
    return 'A link and a code were sent to $email — check your inbox.';
  }

  @override
  String get authLegalPrefix => 'By continuing, you agree to ';

  @override
  String get authLegalTerms => 'the Terms of Use';

  @override
  String get authLegalAnd => ' and ';

  @override
  String get authLegalPrivacy => 'the Privacy Policy';

  @override
  String get authLegalSuffix => '.';

  @override
  String get authReassurance =>
      'Your current progress is kept safe and securely linked to your account.';

  @override
  String get authOr => 'or';

  @override
  String get channelClaimOwnership => 'Claim ownership';

  @override
  String get channelAudioOnly => 'Audio only';

  @override
  String get channelInProcessing => 'Processing';

  @override
  String get channelAllChannels => 'All channels';

  @override
  String get channelSearchChannelsHint => 'Search channels…';

  @override
  String get channelClear => 'Clear';

  @override
  String channelChannelsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count channels',
      one: '$count channel',
    );
    return '$_temp0';
  }

  @override
  String channelResultsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '$count result',
    );
    return '$_temp0';
  }

  @override
  String get channelNoChannels => 'No channels.';

  @override
  String channelNoChannelsForQuery(String query) {
    return 'No channels for “$query”.';
  }

  @override
  String get channelSortChannels => 'Sort channels';

  @override
  String get channelShuffle => 'Shuffle';

  @override
  String get channelKeywordSearch => 'Keyword search';

  @override
  String get channelKeywordSearchHint => 'Search by keyword (typo-tolerant)…';

  @override
  String channelSearchUnavailable(String url) {
    return 'Meilisearch is unavailable at $url. Start the Docker container and populate the index (domovina-rag repository).';
  }

  @override
  String get channelSearching => 'Searching…';

  @override
  String channelResultsInMs(int count, int ms) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results in $ms ms · typo-tolerant',
      one: '$count result in $ms ms · typo-tolerant',
    );
    return '$_temp0';
  }

  @override
  String get channelSearchPrompt => 'Type a term for instant episode search.';

  @override
  String get channelAll => 'All';

  @override
  String get channelSearchStart => 'Keyword search — start typing.';

  @override
  String channelNoResultsForQuery(String query) {
    return 'No results for “$query”.';
  }

  @override
  String get channelTriggerGenericHeadline => 'Go DOMOVINA Plus';

  @override
  String get channelTriggerGenericSubtitle =>
      'Support the Croatian archive and unlock every benefit.';

  @override
  String get channelTriggerSyncHeadline => 'Sync across all your devices';

  @override
  String get channelTriggerSyncSubtitle =>
      'Your favourites and your place follow you from phone to web and back.';

  @override
  String get channelTriggerOfflineHeadline => 'Listen offline too';

  @override
  String get channelTriggerOfflineSubtitle =>
      'Download episodes and listen on a plane, in the car or on the go.';

  @override
  String get channelTriggerExportHeadline => 'Export transcripts and summaries';

  @override
  String get channelTriggerExportSubtitle =>
      'Save a transcript, summary or article as PDF, Markdown or DOCX.';

  @override
  String get channelTriggerSearchHeadline => 'Search without limits';

  @override
  String get channelTriggerSearchSubtitle =>
      'Unlimited semantic search and more results.';

  @override
  String get channelTriggerEnFirstHeadline => 'English always first';

  @override
  String get channelTriggerEnFirstSubtitle =>
      'English translations appear right away, before general release.';

  @override
  String get channelTriggerMagisteriumHeadline =>
      'Full Magisterium AI analysis';

  @override
  String get channelTriggerMagisteriumSubtitle =>
      'A detailed Magisterium AI review with sources and prompts revealed.';

  @override
  String get channelTriggerBadgeHeadline => 'Become an archive supporter';

  @override
  String get channelTriggerBadgeSubtitle =>
      'A supporter badge and your name on the wall of thanks.';

  @override
  String get channelPlanAnnual => 'Annual';

  @override
  String get channelPlanPerYear => '/ yr';

  @override
  String get channelPlanSaveBadge => '~33% cheaper';

  @override
  String get channelPlanMonthly => 'Monthly';

  @override
  String get channelPlanPerMonth => '/ mo';

  @override
  String get channelPlanLifetime => 'Lifetime';

  @override
  String get channelPlanOneTime => 'one-time';

  @override
  String get channelPlanFounderBadge => 'Founder';

  @override
  String get channelBenefitSync =>
      'Favourites and progress synced across all your devices';

  @override
  String get channelBenefitOffline => 'Download episodes to listen offline';

  @override
  String get channelBenefitExport =>
      'Export transcripts and summaries (PDF, Markdown, DOCX)';

  @override
  String get channelBenefitSearch => 'Unlimited semantic search';

  @override
  String get channelBenefitEnglishFirst => 'English translations shown first';

  @override
  String get channelBenefitMagisterium =>
      'Full Magisterium AI analysis with sources';

  @override
  String get channelBenefitBadge =>
      'Supporter badge and your name on the wall of thanks';

  @override
  String get channelSignInToContinue => 'Sign in to continue';

  @override
  String get channelSubscriptionTiedToAccount =>
      'Your subscription is tied to your account so it works on every device.';

  @override
  String get channelWelcomeToPlus =>
      'Welcome to DOMOVINA Plus! Thank you for your support.';

  @override
  String get channelPurchaseUnavailableDevice =>
      'Purchases aren’t available on this device.';

  @override
  String get channelPurchaseFailed =>
      'The purchase didn’t go through. Please try again.';

  @override
  String get channelSubscriptionRestored =>
      'Your subscription has been restored.';

  @override
  String get channelNoPurchaseToRestore =>
      'We couldn’t find a purchase to restore.';

  @override
  String get channelWebBillingSoon =>
      'Web billing is coming soon. For now, subscribe in the mobile app.';

  @override
  String get channelSignInFirst => 'Sign in first';

  @override
  String get channelRestorePurchases => 'Restore purchases';

  @override
  String get channelManageSubscription => 'Manage subscription';

  @override
  String get channelCheckoutNote =>
      'Checkout is handled by secure RevenueCat / Stripe. The final price is shown on the checkout page.';

  @override
  String get channelPricesIndicative =>
      'Prices are indicative; the final price is shown in the store.';

  @override
  String get channelAlreadyPlus => 'You already have DOMOVINA Plus';

  @override
  String get channelThanksSupportingArchive =>
      'Thank you for supporting the Croatian archive.';

  @override
  String get channelLegalAutoRenew =>
      'Your subscription renews automatically until you cancel. You can cancel any time in your store settings. The lifetime plan is a one-time purchase.';

  @override
  String get channelTalkToFounder => 'Talk to the founder';

  @override
  String get channelCannotFetchSlots => 'We couldn’t load the available times.';

  @override
  String get channelNoSlotsThreeWeeks =>
      'There are no open slots in the next three weeks.';

  @override
  String get channelPickDay => 'Pick a day';

  @override
  String get channelAvailableSlots => 'Available times';

  @override
  String get channelFullName => 'Full name';

  @override
  String get channelEnterName => 'Enter your name';

  @override
  String get channelEmail => 'Email';

  @override
  String get channelEnterEmail => 'Enter your email';

  @override
  String get channelInvalidEmail => 'Invalid email';

  @override
  String get channelTopicOptional => 'What you’d like to discuss (optional)';

  @override
  String get channelConfirmSlot => 'Confirm time';

  @override
  String get channelNetworkError => 'Network error. Please try again.';

  @override
  String get channelSlotConfirmed => 'You’re booked!';

  @override
  String channelDayAtTime(String day, String time) {
    return '$day at $time';
  }

  @override
  String channelInviteSentTo(String email) {
    return 'We’ve sent the invite and Google Meet link to $email.';
  }

  @override
  String get channelOpenGoogleMeet => 'Open Google Meet';

  @override
  String get channelFounderCallTitle => 'Be part of the DOMOVINA story';

  @override
  String get channelFounderCallSubtitle =>
      '15 min on Google Meet · one-on-one with the founder · help shape the platform';

  @override
  String get channelChange => 'Change';

  @override
  String episodeNotFoundDetailed(String id) {
    return 'Episode “$id” wasn’t found on the CDN.\n\nCheck that the ID is correct and that the files have been uploaded.';
  }

  @override
  String episodeNotFound(String id) {
    return 'Episode “$id” wasn’t found.';
  }

  @override
  String episodeLoadError(String details) {
    return 'Couldn’t load this episode:\n$details';
  }

  @override
  String get episodeLoading => 'Loading episode';

  @override
  String episodeLinkCopied(String label) {
    return 'Link copied ($label)';
  }

  @override
  String get episodeWholeEpisode => 'whole episode';

  @override
  String get clipShareTitle => 'Chapter as a clip';

  @override
  String get clipTooltip => 'Download or share this chapter';

  @override
  String get clipDownload => 'Download chapter';

  @override
  String clipDownloadSubtitle(int size, int minutes) {
    return 'MP4 · ~$size MB · $minutes min';
  }

  @override
  String get clipCopyLink => 'Copy clip link';

  @override
  String get clipCopyLinkSubtitle => 'To send in a message or chat';

  @override
  String get clipLinkCopied => 'Clip link copied';

  @override
  String get clipHint =>
      'The first time, the clip takes a few seconds to prepare.';

  @override
  String get episodeOpenOnYouTube => 'Open on YouTube';

  @override
  String get episodeOpenOnX => 'Open on 𝕏';

  @override
  String get episodeCopyMomentLink => 'Copy link to this moment';

  @override
  String get episodeVideo => 'Video';

  @override
  String get episodeLanguageLabel => 'Language:';

  @override
  String get episodeContents => 'Contents';

  @override
  String get episodeArticle => 'Article';

  @override
  String get episodeAiPendingTitle => 'AI processing isn’t finished yet';

  @override
  String get episodeAiPendingAudio =>
      'Showing the audio and basic details. The summary, chapters, article and theological analysis arrive as soon as processing finishes.';

  @override
  String get episodeAiPendingVideo =>
      'Showing only the video and basic details from YouTube. The summary, chapters, article and theological analysis arrive as soon as processing finishes.';

  @override
  String get episodeAiPendingInfo =>
      'AI processing isn’t finished yet — showing only the basic details. The summary, chapters and article arrive as soon as it’s done.';

  @override
  String get episodeListen => 'Listen to episode';

  @override
  String get episodeWatchOnYouTube => 'Watch on YouTube';

  @override
  String get episodeMediaUnavailable =>
      'Media isn’t available for this episode.';

  @override
  String get episodeNoChapters => 'No chapters for this episode.';

  @override
  String get episodeKeyTopics => 'Key topics';

  @override
  String get episodeKeyTakeaways => 'Key takeaways';

  @override
  String get episodeSpeakers => 'Speakers';

  @override
  String get episodeTabPlayer => 'Player';

  @override
  String get episodeTabChapters => 'Chapters';

  @override
  String get episodeTabInfo => 'Info';

  @override
  String get episodeMetadata => 'Metadata';

  @override
  String get episodeMetaChannel => 'Channel';

  @override
  String get episodeMetaModelSummary => 'Model (summary)';

  @override
  String get episodeMetaModelArticle => 'Model (article)';

  @override
  String get episodeMetaModelTheology => 'Model (theology)';

  @override
  String get episodeMetaGenerated => 'Generated';

  @override
  String get episodeMetaLanguage => 'Language';

  @override
  String get episodeMetaContentType => 'Content type';

  @override
  String get episodeMetaSentiment => 'Sentiment';

  @override
  String get episodeMetaDate => 'Date';

  @override
  String get episodeMetaDuration => 'Duration';

  @override
  String homeChannelCardMeta(int count, String duration) {
    return 'Channel · $count ep · $duration';
  }

  @override
  String homeChannelMagisteriumTooltip(String label) {
    return '$label\nAn estimate of alignment with Catholic teaching (0–100).';
  }

  @override
  String get homeFooterAbout => 'About';

  @override
  String get homeFooterAboutText =>
      'DOMOVINA.ai uses artificial intelligence to transcribe, summarise and analyse Croatian Catholic podcasts. The Magisterium AI agent rates their alignment with Catholic teaching.';

  @override
  String get homeFooterLinks => 'Links';

  @override
  String get homeFooterSuggestEpisode => 'Suggest an episode';

  @override
  String get homeFooterEpisodeSuggestionSubject =>
      'DOMOVINA.ai — episode suggestion';

  @override
  String get homeFooterContact => 'Contact';

  @override
  String get homeFooterPrivacy => 'Privacy';

  @override
  String get homeFooterTerms => 'Terms of use';

  @override
  String get homeFooterStats => 'Statistics';

  @override
  String homeFooterStatChannels(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'channels',
      one: 'channel',
    );
    return '$_temp0';
  }

  @override
  String homeFooterStatEpisodes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'episodes',
      one: 'episode',
    );
    return '$_temp0';
  }

  @override
  String homeFooterStatHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hours processed',
      one: 'hour processed',
    );
    return '$_temp0';
  }

  @override
  String get homeFooterStatAvgScore => 'average Magisterium score';

  @override
  String get homeFooterSoon => 'Soon';

  @override
  String homeFooterCopyright(int year) {
    return '© $year DOMOVINA.ai';
  }

  @override
  String get homeFooterMadeIn => 'Made in Croatia';

  @override
  String get homeSearchPlaceholderFull => 'Search channels and episodes';

  @override
  String get homeSearchTooltip => 'Search';

  @override
  String get homeSortNewest => 'Newest';

  @override
  String get homeSortMostEpisodes => 'Most episodes';

  @override
  String get homeSortMagisterium => 'Magisterium score';

  @override
  String get homeSortAlphabetical => 'Alphabetical';

  @override
  String get homeSortCustom => 'My order';

  @override
  String get homeReasonShortHiQualityRecent => 'Top pick';

  @override
  String get homeReasonShortHiQuality => 'High Magisterium score';

  @override
  String get homeReasonShortAnyMagisterium => 'AI-processed';

  @override
  String get homeReasonShortNewest => 'Newest';

  @override
  String homeHeroRotationTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Each day we pick the $count best episodes — they rotate automatically.',
      one: 'Each day we pick the best episode — they rotate automatically.',
    );
    return '$_temp0';
  }

  @override
  String get homeHeroRotationBadge => 'In rotation';

  @override
  String get homeHeroEyebrow => 'Featured';

  @override
  String get homeHeroListen => 'Listen';

  @override
  String get homeHeroWhyButton => 'Why?';

  @override
  String get homeWhyDialogTitle => 'Why this is featured';

  @override
  String get homeWhyAlgorithmHeading => 'How the algorithm works';

  @override
  String get homeWhyDialogExplainer =>
      'The featured episode changes every day at midnight — the algorithm shortlists the five best candidates from the active tier and picks one based on the day of the year. The choice stays the same throughout the day (deterministic).';

  @override
  String get homeWhyGotIt => 'Got it';

  @override
  String get homeReasonHeadlineHiQualityRecent => 'High score, fresh episode';

  @override
  String get homeReasonHeadlineHiQuality => 'High Magisterium score';

  @override
  String get homeReasonHeadlineAnyMagisterium => 'AI-processed episode';

  @override
  String get homeReasonHeadlineNewest => 'Newest episode';

  @override
  String get homeWhyFactChannel => 'Channel';

  @override
  String get homeWhyFactScore => 'Magisterium score';

  @override
  String get homeWhyFactPublished => 'Published';

  @override
  String get homeWhyFactAiProcessing => 'AI processing';

  @override
  String get homeWhyFactAiYes =>
      'Yes (transcript, summary and Magisterium analysis)';

  @override
  String get homeWhyFactAiNo => 'No';

  @override
  String get homeWhyFactWeight => 'Algorithm weight';

  @override
  String homeWhyFactWeightValue(String weight) {
    return '$weight (score × 0.6 + recency × 0.4)';
  }

  @override
  String get homeWhyFactPool => 'Candidate pool';

  @override
  String homeWhyFactPoolValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes in the same tier',
      one: '$count episode in the same tier',
    );
    return '$_temp0';
  }

  @override
  String get homeTier1Title => '1. Top pick';

  @override
  String get homeTier1Desc =>
      'AI processing + score ≥ 70 + published in the last 14 days. Ranked by (score × 0.6 + recency × 0.4). The top five enter the daily rotation.';

  @override
  String get homeTier2Title => '2. High score';

  @override
  String get homeTier2Desc =>
      'AI processing + score ≥ 70 (any date). Ranked by score.';

  @override
  String get homeTier3Title => '3. AI-processed';

  @override
  String get homeTier3Desc => 'Any episode with AI processing. Ranked by date.';

  @override
  String get homeTier4Title => '4. Newest';

  @override
  String get homeTier4Desc =>
      'Fallback — the newest episode with no processing at all.';

  @override
  String get homeAgoToday => 'today';

  @override
  String get homeAgoYesterday => 'yesterday';

  @override
  String homeAgoDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days ago',
      one: '$days day ago',
    );
    return '$_temp0';
  }

  @override
  String homeAgoWeeks(int weeks) {
    String _temp0 = intl.Intl.pluralLogic(
      weeks,
      locale: localeName,
      other: '$weeks weeks ago',
      one: '$weeks week ago',
    );
    return '$_temp0';
  }

  @override
  String homeAgoMonths(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months months ago',
      one: '$months month ago',
    );
    return '$_temp0';
  }

  @override
  String homeAgoYears(int years) {
    String _temp0 = intl.Intl.pluralLogic(
      years,
      locale: localeName,
      other: '$years years ago',
      one: '$years year ago',
    );
    return '$_temp0';
  }

  @override
  String get homeComingSoonSnack => 'This feature is coming soon';

  @override
  String homeChannelsLoadError(String error) {
    return 'Couldn\'t load the channels:\n$error';
  }

  @override
  String get homeRailContinue => 'Continue listening';

  @override
  String get homeRailLatest => 'Latest episodes';

  @override
  String get homeRailFreshlyArrived => 'Just arrived';

  @override
  String get homeStatusProcessing => 'Processing';

  @override
  String get homeChannelsEyebrow => 'Channels';

  @override
  String get homeAllChannelsTitle => 'All channels';

  @override
  String homeAllChannelsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Browse and search all $count channels',
      one: 'Browse and search $count channel',
    );
    return '$_temp0';
  }

  @override
  String homeLoadingChannels(int loaded, int total) {
    return 'Loading $loaded/$total channels…';
  }

  @override
  String get homeSearchBarrierLabel => 'Close search';

  @override
  String get homeSearchHint => 'Search channels, episodes and content…';

  @override
  String homeSearchNoResults(String query) {
    return 'No results for “$query”';
  }

  @override
  String get homeSearchNoTitleMatches => 'No matches\nin titles';

  @override
  String get homeSearchSearching => 'Searching…';

  @override
  String get homeSearchNoContentMatches => 'No matches\nin content';

  @override
  String get homeSearchSectionChannels => 'Channels';

  @override
  String get homeSearchSectionEpisodes => 'Episodes';

  @override
  String get homeSearchSectionContent => 'In content';

  @override
  String get homeSearchSemanticLoading => 'Searching the conversation content…';

  @override
  String get homeSearchEmptyTitle => 'Start typing to search';

  @override
  String get homeSearchEmptySubtitle =>
      'Searches channels, episodes and the conversations themselves';

  @override
  String get homeSearchKeyboardHint =>
      '↑ ↓ to move · ← → switch columns · ↵ to open';

  @override
  String homeSearchChannelMeta(int count, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes · $duration',
      one: '$count episode · $duration',
    );
    return '$_temp0';
  }

  @override
  String homeSearchRelevanceTooltip(String score) {
    return 'Relevance (semantic similarity): $score';
  }

  @override
  String get homeSearchOpenById => 'Open by YouTube ID';

  @override
  String get homeSearchIdHint => 'e.g. H-p2Hl6x7I0';

  @override
  String legalLastUpdated(String date) {
    return 'Last updated: $date';
  }

  @override
  String get legalContactTitle => 'Contact';

  @override
  String get legalPrivacyTitle => 'Privacy Policy';

  @override
  String get legalPrivacyIntro =>
      'DOMOVINA.ai is an application that transcribes, summarises and analyses Croatian Catholic podcasts using artificial intelligence. This page is a placeholder for the full privacy policy.';

  @override
  String get legalPrivacyDataTitle => 'What data we collect';

  @override
  String get legalPrivacyDataBody =>
      'If you sign in with a Google account, we collect the email address and name that Google sends to the application. We also store your episode playback progress and favourite markers so that we can sync them across your devices.';

  @override
  String get legalPrivacyContactBody =>
      'For privacy-related enquiries, please contact us at stepanic.matija@gmail.com.';

  @override
  String get legalTermsTitle => 'Terms of Use';

  @override
  String get legalTermsIntro =>
      'By using the DOMOVINA.ai application, you accept these terms. This page is a placeholder for the full terms of use.';

  @override
  String get legalTermsContentTitle => 'Content';

  @override
  String get legalTermsContentBody =>
      'Episode content (videos, transcripts and summaries) is presented for educational purposes. Copyright in the original podcasts belongs to their respective creators and channels.';

  @override
  String get legalTermsAiTitle => 'AI analysis';

  @override
  String get legalTermsAiBody =>
      'Magisterium AI ratings and summaries are machine-generated and may contain errors. They do not represent the official position of the Catholic Church.';

  @override
  String get legalTermsContactBody =>
      'For any enquiries, please contact us at stepanic.matija@gmail.com.';

  @override
  String get magisteriumScoreActivelyPromotes =>
      'Actively promotes Catholic teaching';

  @override
  String get magisteriumScoreMostlyAligned => 'Mostly aligned';

  @override
  String get magisteriumScorePartiallyAligned => 'Partially aligned';

  @override
  String get magisteriumScoreDeviates => 'Departs from teaching';

  @override
  String get magisteriumScoreContradicts => 'Contradicts teaching';

  @override
  String get magisteriumAlignmentSubtitle =>
      'Alignment with Catholic teaching and Sacred Scripture';

  @override
  String magisteriumTheologicalConcerns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count theological concerns',
      one: '$count theological concern',
    );
    return '$_temp0';
  }

  @override
  String get magisteriumArticleHeaderTitle =>
      'Magisterium AI — Theological analysis';

  @override
  String get magisteriumArticleHeaderSubtitle =>
      'Chronological review of alignment with Catholic teaching';

  @override
  String magisteriumAnalysisGeneratedBy(String model, String date) {
    return 'Analysis generated by model $model • $date';
  }

  @override
  String magisteriumSourcesFromChurchDocs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources from Church documents',
      one: '$count source from Church documents',
    );
    return '$_temp0';
  }

  @override
  String get magisteriumTabEvaluation => 'Evaluation';

  @override
  String get magisteriumTabPrompt => 'Prompt';

  @override
  String get magisteriumFullHeaderTitle =>
      'Magisterium AI — Theological evaluation';

  @override
  String magisteriumModelCitations(String model, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count citations',
      one: '$count citation',
    );
    return '$model  •  $_temp0';
  }

  @override
  String get magisteriumSourcesTitle => 'Sources';

  @override
  String magisteriumCitationsFromChurchDocs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count citations from Church documents',
      one: '$count citation from Church documents',
    );
    return '$_temp0';
  }

  @override
  String get magisteriumScoreCaption => 'Magisterium score';

  @override
  String get magisteriumOpenOnMagisterium => 'Open on Magisterium.com';

  @override
  String get mediaYouTubeHigherQuality => 'YouTube player (higher quality)';

  @override
  String get mediaSubtitlesOff => 'Turn off subtitles (C)';

  @override
  String get mediaSubtitlesOn => 'Subtitles (C)';

  @override
  String get mediaBoostVolume => 'Turn on sound';

  @override
  String get mediaPause => 'Pause';

  @override
  String get mediaPlay => 'Play';

  @override
  String get mediaChapters => 'Chapters';

  @override
  String get mediaYouTubeQualityHint =>
      'YouTube player — choose quality in the ⚙ player settings';

  @override
  String get mediaNativePlayerLabel => 'DOMOVINA player';

  @override
  String get mediaLanguageSelection => 'Display language selection';

  @override
  String get mediaTranslationDisclaimer =>
      'Translation is literal, without AI hallucinations.';

  @override
  String get mediaSwitchToCroatian => 'Switch to Croatian';

  @override
  String get mediaSwitchToEnglish => 'Switch to English';

  @override
  String get mediaRemoveFavorite => 'Remove from favorites';

  @override
  String get mediaAddFavorite => 'Add to favorites';

  @override
  String mediaResumingFrom(String time) {
    return 'Resuming from $time';
  }

  @override
  String get mediaSwitchToLightTheme => 'Switch to light theme';

  @override
  String get mediaSwitchToDarkTheme => 'Switch to dark theme';

  @override
  String get mediaViewSimple => 'Simple';

  @override
  String get mediaViewDetailed => 'Detailed';

  @override
  String get mediaViewSimpleTooltip =>
      'Switch to the simple view — large player and chapters, without the article (ideal for listening in the car)';

  @override
  String get mediaViewDetailedTooltip =>
      'Switch to the detailed view — article, Magisterium score and chapters alongside the video';

  @override
  String get mediaUserFallback => 'User';

  @override
  String mediaViaProvider(String provider) {
    return 'via $provider';
  }

  @override
  String get mediaVerifiedIdentity => 'Verified identity';

  @override
  String get mediaMyAccount => 'My account';

  @override
  String get mediaMyChannels => 'My channels';

  @override
  String get mediaSwitchDevice => 'Switch to another device';

  @override
  String mediaMinAmount(String amount) {
    return 'Minimum amount is $amount €';
  }

  @override
  String get mediaPaymentCreateFailed =>
      'Could not create the payment. Please try again.';

  @override
  String get mediaSupportEpisode => 'Support this episode';

  @override
  String get mediaSupportBlurb =>
      'Donate with a single scan — SEPA, no fees. Funds go directly to the creator, transparently on-chain.';

  @override
  String mediaRaisedProgress(String raised, String goal, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# supporters',
      one: '# supporter',
    );
    return 'Raised $raised € of $goal € · $_temp0';
  }

  @override
  String get mediaPreparing => 'Preparing…';

  @override
  String mediaSupportWithAmount(String amount) {
    return 'Support with $amount €';
  }

  @override
  String get mediaScanInBankApp => 'Scan in your banking app';

  @override
  String mediaAmountValue(String amount) {
    return 'Amount: $amount €';
  }

  @override
  String get mediaRecipient => 'Recipient';

  @override
  String get mediaPaymentReference => 'Payment reference';

  @override
  String get mediaAwaitingPayment => 'Awaiting payment confirmation…';

  @override
  String get mediaPaymentConfirmedOnChain => 'Payment confirmed on-chain.';

  @override
  String mediaCopiedLabel(String label) {
    return 'Copied: $label';
  }

  @override
  String get mediaOtherAmount => 'Other';

  @override
  String get ownershipCrumbHome => 'Home';

  @override
  String get ownershipCrumbOwnership => 'Ownership';

  @override
  String get ownershipChannelFallback => 'Channel';

  @override
  String get ownershipMyChannels => 'My channels';

  @override
  String get ownershipLoadChannelFailed => 'We couldn\'t load the channel.';

  @override
  String get ownershipOpenAuthFailed =>
      'We couldn\'t open the authorization page.';

  @override
  String get ownershipSignInToClaim => 'Sign in first to claim this channel.';

  @override
  String get ownershipNoYoutubeId =>
      'This channel isn\'t linked to a YouTube ID yet, so it can\'t be claimed right now.';

  @override
  String get ownershipChannelNotFound => 'Channel not found.';

  @override
  String get ownershipNotOwnerTitle => 'Not the channel owner?';

  @override
  String get ownershipNotOwnerBody =>
      'If you know the owner, send them a message to claim ownership and verify on DOMOVINA.ai.';

  @override
  String get ownershipInviteOwnerWhatsApp => 'Invite the owner (WhatsApp)';

  @override
  String ownershipInviteMessage(String channelTitle, String link) {
    return 'Hello! Your YouTube channel \"$channelTitle\" is on DOMOVINA.ai. You can claim ownership for free and manage your content and payouts — verify yourself as the channel owner here: $link';
  }

  @override
  String get ownershipStepConfirmTitle => 'Confirm ownership';

  @override
  String get ownershipReverifySubtitle =>
      'Ownership is older than 90 days — please confirm it again.';

  @override
  String get ownershipOwnershipVerifiedSubtitle =>
      'Ownership confirmed via your YouTube account.';

  @override
  String get ownershipSignInYoutubeSubtitle =>
      'Sign in with the YouTube account that owns this channel.';

  @override
  String get ownershipOwnershipNote =>
      'Only the Google account that owns the channel can claim it. Editors and managers added in YouTube settings (Channel permissions) can\'t — YouTube doesn\'t list them as owners. If the channel belongs to a Brand account, sign in with the Google account that manages it.';

  @override
  String get ownershipReverifyAction => 'Re-verify';

  @override
  String get ownershipLoginYoutube => 'Sign in with YouTube';

  @override
  String get ownershipStepVerifyIdentityTitle => 'Verify your identity';

  @override
  String get ownershipIdentityVerifiedSubtitle =>
      'Identity verified (eID card).';

  @override
  String get ownershipConnectEosobnaSubtitle =>
      'Connect your eID card (Certilia) — required before payout.';

  @override
  String get ownershipVerifyWithEosobna => 'Verify with eID card';

  @override
  String get ownershipStepConnectWalletTitle => 'Connect a wallet';

  @override
  String get ownershipWalletLockedSubtitle =>
      'Available after ownership and identity verification.';

  @override
  String get ownershipWalletSubtitle =>
      'Register a payout wallet address (destination).';

  @override
  String get ownershipManageWallet => 'Manage wallet';

  @override
  String get ownershipCheckingOwnership => 'Verifying ownership…';

  @override
  String get ownershipMissingAuthData => 'Authorization data is missing.';

  @override
  String ownershipOwnershipConfirmedWithName(String name) {
    return 'Ownership confirmed: $name';
  }

  @override
  String ownershipRequestReceivedWithStatus(String status) {
    return 'Request received (status: $status).';
  }

  @override
  String get ownershipCallbackTitle => 'Ownership confirmation';

  @override
  String get ownershipRevokeDialogTitle => 'Release ownership?';

  @override
  String ownershipRevokeDialogBody(String name) {
    return 'You\'re giving up ownership of \"$name\". Verification and payout status will be reset, and the channel becomes available to claim again. You can reclaim it any time.';
  }

  @override
  String get ownershipRevokeAction => 'Release';

  @override
  String get ownershipRevokedSnack => 'Ownership released.';

  @override
  String get ownershipClaimedChannelsTitle => 'Claimed channels';

  @override
  String get ownershipPayoutWalletsTitle => 'Payout wallets';

  @override
  String get ownershipPayoutWalletsDesc =>
      'The destination where your collected funds are paid out — your crypto wallet (0x, Gnosis). When you request a payout, the platform transfers to this address.\n\nThis is NOT the address that receives donations: each campaign has its own Safe where contributions arrive (visible to everyone on Gnosisscan); you start a payout from campaign management.';

  @override
  String get ownershipNoClaimsBody =>
      'You haven\'t claimed any channels yet. Open a channel and choose \"Claim ownership\" to start verification.';

  @override
  String get ownershipBrowseChannels => 'Browse channels';

  @override
  String get ownershipNeedsReverifyTag => 'needs re-verification';

  @override
  String get ownershipOptionsTooltip => 'Options';

  @override
  String get ownershipCampaignsMenu => 'Campaigns (Support Wall)';

  @override
  String get ownershipRevokeMenu => 'Release ownership';

  @override
  String get ownershipWalletDestVerified => 'Payout destination · verified';

  @override
  String get ownershipWalletDest => 'Payout destination';

  @override
  String get ownershipWalletAddressLabel => 'Your payout wallet address (0x…)';

  @override
  String get ownershipWalletAddressHelper =>
      'The EVM address (Gnosis) where you receive payouts.';

  @override
  String get ownershipAddWallet => 'Add wallet';

  @override
  String get ownershipCampaignFallback => 'Campaign';

  @override
  String get ownershipTabEdit => 'Edit';

  @override
  String get ownershipTabEpisodes => 'Episodes';

  @override
  String get ownershipTabStats => 'Stats';

  @override
  String get ownershipTabPayout => 'Payout';

  @override
  String get ownershipCampaignNotFound => 'Campaign not found.';

  @override
  String get ownershipSaved => 'Saved';

  @override
  String get ownershipSaveFailed => 'Couldn\'t save changes.';

  @override
  String get ownershipFieldTitle => 'Title';

  @override
  String get ownershipFieldDescription => 'Description';

  @override
  String get ownershipFieldGoal => 'Goal (€)';

  @override
  String get ownershipFieldGoalHint => 'empty = no goal';

  @override
  String get ownershipFieldMinAmount => 'Min. amount (€)';

  @override
  String get ownershipFieldState => 'Status';

  @override
  String get ownershipFieldVisibility => 'Visibility';

  @override
  String get ownershipEditNote =>
      'Note: SEPA and on-chain details (IBAN, Safe address) and the slug aren\'t changed here.';

  @override
  String get ownershipSaveChanges => 'Save changes';

  @override
  String get ownershipStateDraft => 'Draft';

  @override
  String get ownershipStateActive => 'Active';

  @override
  String get ownershipStateClosed => 'Closed';

  @override
  String get ownershipStateCancelled => 'Cancelled';

  @override
  String get ownershipStateFunded => 'Funded';

  @override
  String get ownershipVisPublic => 'Public';

  @override
  String get ownershipVisUnlisted => 'Unlisted';

  @override
  String get ownershipVisPrivate => 'Private';

  @override
  String ownershipSupportersContributions(int supporters, int contributions) {
    String _temp0 = intl.Intl.pluralLogic(
      supporters,
      locale: localeName,
      other: '$supporters supporters',
      one: '$supporters supporter',
    );
    String _temp1 = intl.Intl.pluralLogic(
      contributions,
      locale: localeName,
      other: '$contributions contributions',
      one: '$contributions contribution',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String get ownershipSupportWall => 'Support Wall';

  @override
  String get ownershipNoPublicContributions => 'No public contributions yet.';

  @override
  String get ownershipEnterValidAmount => 'Enter a valid amount.';

  @override
  String get ownershipAmountExceedsAvailable =>
      'Amount exceeds the available balance.';

  @override
  String get ownershipEnterDestination =>
      'Enter a destination (0x address or IBAN).';

  @override
  String get ownershipPayoutRequestSent => 'Payout request sent';

  @override
  String get ownershipRequestFailedRetry =>
      'The request failed. Please try again.';

  @override
  String get ownershipErrKycRequired =>
      'eID (KYC) verification is required before payout.';

  @override
  String get ownershipErrInvalidDestination =>
      'Invalid destination (0x address or IBAN).';

  @override
  String get ownershipErrInvalidAmount => 'Invalid amount.';

  @override
  String get ownershipErrNotAuthorized =>
      'You\'re not authorized for this campaign.';

  @override
  String get ownershipErrRequestFailed => 'The request failed.';

  @override
  String get ownershipPayoutNeedsKyc =>
      'Payout requires eID (KYC) verification. Complete it in \"My channels\".';

  @override
  String get ownershipRequestPayout => 'Request payout';

  @override
  String get ownershipDestinationLabel => 'Destination (0x address or IBAN)';

  @override
  String get ownershipAmountLabel => 'Amount (€)';

  @override
  String ownershipAvailableHelper(String amount) {
    return 'Available: $amount €';
  }

  @override
  String get ownershipPayoutHistory => 'Payout history';

  @override
  String get ownershipNoPayouts => 'No payouts yet.';

  @override
  String get ownershipChangeFailed => 'The change failed.';

  @override
  String get ownershipYieldTitle => 'Earn yield (Aave v3 · Gnosis)';

  @override
  String get ownershipYieldSubtitle =>
      'While funds await payout, they earn yield (~3.5% APY, variable). The yield belongs to the campaign. DeFi risk — principal isn\'t guaranteed.';

  @override
  String get ownershipYieldInPool => 'Earning yield (Aave)';

  @override
  String get ownershipYieldAccrued => 'Accrued yield';

  @override
  String ownershipYieldLastSync(String time) {
    return 'last sync: $time';
  }

  @override
  String get ownershipYieldTokenLink => 'aGnoEURe on Gnosisscan';

  @override
  String get ownershipSummaryRaised => 'Raised';

  @override
  String get ownershipSummaryYield => 'Yield (Aave)';

  @override
  String get ownershipSummaryPending => 'In progress';

  @override
  String get ownershipSummaryPaid => 'Paid out';

  @override
  String get ownershipSummaryAvailable => 'Available';

  @override
  String get ownershipPayoutStateRequested => 'Requested';

  @override
  String get ownershipPayoutStateApproved => 'Approved';

  @override
  String get ownershipPayoutStateFailed => 'Failed';

  @override
  String get ownershipCampaignsTitle => 'Campaigns';

  @override
  String get ownershipSignInToManageCampaigns =>
      'Sign in first to manage campaigns.';

  @override
  String get ownershipNotVerifiedOwner =>
      'You\'re not a verified owner of this channel.';

  @override
  String ownershipEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '$count episode',
    );
    return '$_temp0';
  }

  @override
  String get ownershipNoCampaignsTitle => 'No campaigns for this channel yet.';

  @override
  String get ownershipNoCampaignsBody =>
      'Campaigns are created on pinka.io (which also generates the payout Safe). After creating one, link the campaign to your channel so you can manage it here and assign episodes.';

  @override
  String get ownershipEpisodesSaved => 'Episodes saved';

  @override
  String get ownershipEpisodeTaken =>
      'One of the episodes is already in another campaign.';

  @override
  String get ownershipSaveFailedRetry => 'Couldn\'t save. Please try again.';

  @override
  String get ownershipNoEpisodesAvailable =>
      'No episodes available for this channel.';

  @override
  String ownershipSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '$count episode',
    );
    return 'Selected: $_temp0';
  }

  @override
  String get pinkaWallTitle => 'Wall of Support';

  @override
  String get pinkaSupport => 'Support';

  @override
  String get pinkaNoCampaign =>
      'There\'s no active support campaign for this yet.';

  @override
  String get pinkaWallEmpty =>
      'Be the first to show support — your message will appear here.';

  @override
  String get pinkaRaisedLabel => 'raised';

  @override
  String pinkaOfGoal(String amount) {
    return 'of €$amount goal';
  }

  @override
  String pinkaRaised(String amount) {
    return 'Raised €$amount';
  }

  @override
  String pinkaRaisedOfGoal(String raised, String goal) {
    return 'Raised €$raised of €$goal';
  }

  @override
  String pinkaSupportersCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count supporters',
      one: '$count supporter',
    );
    return '$_temp0';
  }

  @override
  String pinkaPaymentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payments',
      one: '$count payment',
    );
    return '$_temp0';
  }

  @override
  String get pinkaVerifyOnchainTitle => 'Verify on-chain';

  @override
  String get pinkaVerifyOnchainBody =>
      'Contributions go straight to the campaign\'s Safe (EURe on Gnosis). Anyone can verify the balance — independently of us.';

  @override
  String pinkaOnchainBalance(String amount) {
    return 'Currently on the Safe: $amount €';
  }

  @override
  String get pinkaEureBalanceOnGnosisscan => 'EURe balance on Gnosisscan';

  @override
  String get pinkaInflowHistory => 'Inflow history (transfers)';

  @override
  String get pinkaFundsWorkingAave =>
      'Funds are currently working on Aave v3 (Gnosis)';

  @override
  String pinkaInAaveLabel(String amount) {
    return 'In Aave: €$amount';
  }

  @override
  String pinkaAaveYieldLabel(String amount) {
    return 'yield: €$amount';
  }

  @override
  String get pinkaAaveExplainer =>
      'That\'s why the EURe balance on the Safe itself is low — the funds are deposited to earn yield and are withdrawn at payout.';

  @override
  String get pinkaAgnoEureBalanceOnGnosisscan =>
      'aGnoEURe balance on Gnosisscan';

  @override
  String pinkaMinAmount(String amount) {
    return 'The minimum amount is €$amount';
  }

  @override
  String get pinkaPaymentCreateFailed =>
      'We couldn\'t prepare the payment. Please try again.';

  @override
  String get pinkaPaymentSentPending =>
      'Payment sent — it will appear on the wall as soon as it\'s confirmed on-chain.';

  @override
  String get pinkaWalletSendFailed =>
      'Sending from the wallet failed or was cancelled.';

  @override
  String get pinkaOnchainBlurb =>
      'Send EURe (Gnosis) directly on-chain — transparent and without intermediaries.';

  @override
  String get pinkaSepaBlurb =>
      'Donate with a single scan — SEPA, no fees. Funds go directly to the author.';

  @override
  String get pinkaCustomAmountHint => 'Other';

  @override
  String get pinkaCustomAmountPlaceholder => '19.91';

  @override
  String get pinkaSafeAddressCopied =>
      'Safe Wallet address copied to clipboard.';

  @override
  String get pinkaCopySafeAddress => 'Copy the Safe Wallet address';

  @override
  String pinkaStepOf(int current, int total) {
    return 'Step $current/$total';
  }

  @override
  String get pinkaStepPaymentTitle => 'Payment from your bank';

  @override
  String get pinkaStepPaymentCustodian => 'Custodian: your bank';

  @override
  String get pinkaStepProcessingTitle => 'Received — processing and checks';

  @override
  String get pinkaStepProcessingCustodian =>
      'Custodian: Monerium (regulated e-money issuer)';

  @override
  String get pinkaStepMintedTitle => 'EURe minted';

  @override
  String get pinkaStepMintedCustodian => 'On the blockchain (Gnosis)';

  @override
  String get pinkaStepForwardingTitle => 'Forwarding to the recipient';

  @override
  String get pinkaStepForwardingCustodian => 'MPT relay';

  @override
  String get pinkaStepSettledTitle => 'With the recipient';

  @override
  String get pinkaStepSettledCustodian => 'Custodian: the recipient';

  @override
  String get pinkaIntentRejected =>
      'The payment was rejected during processing — funds are returned to the sender.';

  @override
  String get pinkaIntentExpired =>
      'The payment window has expired. If you did send the payment, it will appear on the wall once it arrives.';

  @override
  String get pinkaNameHint => 'Name or nickname (optional)';

  @override
  String get pinkaMessageHint => 'A message with your support (optional)';

  @override
  String get pinkaAnonymousLabel =>
      'Donate anonymously (don\'t show me on the wall of support)';

  @override
  String get pinkaPreparing => 'Preparing…';

  @override
  String pinkaSupportWithAmount(String amount) {
    return 'Support with €$amount';
  }

  @override
  String get pinkaWalletConnecting => 'Connecting wallet…';

  @override
  String get pinkaWalletOpening => 'Opening wallet…';

  @override
  String get pinkaWalletConfirming => 'Confirming on-chain…';

  @override
  String pinkaPayFromDomovinaWallet(String amount) {
    return 'Pay €$amount from your DOMOVINA wallet';
  }

  @override
  String get pinkaOrScanOtherWallet => 'or scan with another wallet';

  @override
  String pinkaScanWithWallet(String amount) {
    return 'Scan with your wallet (MetaMask / Monerium) and send €$amount in EURe.';
  }

  @override
  String get pinkaRecipient => 'Recipient';

  @override
  String get pinkaToken => 'Token';

  @override
  String get pinkaOnchainArrivalNote =>
      'Your donation appears on the wall of support once it lands on-chain (~1–2 min).';

  @override
  String get pinkaScanInBankApp => 'Scan in your banking app';

  @override
  String pinkaAmountLabel(String amount) {
    return 'Amount: €$amount';
  }

  @override
  String get pinkaPaymentReference => 'Payment reference';

  @override
  String get pinkaAwaitingPayment => 'Waiting for payment confirmation…';

  @override
  String get pinkaThanksForSupportEmoji => 'Thank you for your support! 🙏';

  @override
  String get pinkaPaymentConfirmedOnchain =>
      'Your payment is confirmed on-chain.';

  @override
  String get pinkaDonateAgain => 'Donate again';

  @override
  String pinkaCopiedLabel(String label) {
    return 'Copied: $label';
  }

  @override
  String get pinkaLink => 'link';

  @override
  String get pinkaAnonymous => 'Anonymous';

  @override
  String get sectionArticle => 'Article';

  @override
  String sectionPlayFrom(String timestamp) {
    return 'Play from $timestamp';
  }

  @override
  String sectionPersonSpeaksHere(String name) {
    return '$name speaks here';
  }

  @override
  String sectionPersonMentionedHere(String name) {
    return 'Mentioned here: $name';
  }

  @override
  String get sectionCopyLink => 'Copy link';

  @override
  String sectionLinkCopied(String timestamp) {
    return 'Link copied: $timestamp';
  }

  @override
  String get sectionTheologicalAssessment => 'Theological assessment';

  @override
  String sectionSources(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sources',
      one: '$count source',
    );
    return '$_temp0';
  }

  @override
  String get sectionSummary => 'Summary';

  @override
  String get sectionKeyTopics => 'Key topics';

  @override
  String get sectionSpeakers => 'Speakers';

  @override
  String get sectionKeyTakeaways => 'Key takeaways';

  @override
  String get sectionChapters => 'Chapters';

  @override
  String get sectionPeople => 'People';

  @override
  String get sectionPlaces => 'Places';

  @override
  String get sectionOrganizations => 'Organizations';

  @override
  String get sectionContents => 'Contents';

  @override
  String get sectionAgeToday => 'today';

  @override
  String get sectionAgeYesterday => 'yesterday';

  @override
  String sectionAgeDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '$count day ago',
    );
    return '$_temp0';
  }

  @override
  String sectionAgeWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wks ago',
      one: 'a week ago',
    );
    return '$_temp0';
  }

  @override
  String sectionAgeMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mo ago',
      one: 'a month ago',
    );
    return '$_temp0';
  }

  @override
  String sectionAgeYears(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count yrs ago',
      one: 'a year ago',
    );
    return '$_temp0';
  }

  @override
  String sectionPublishedOn(String date) {
    return 'Published: $date';
  }

  @override
  String get sectionTheologicalAnalysisSubtitle =>
      'Theological analysis, section by section';

  @override
  String get sectionNoTheologicalAnalysis =>
      'No theological analysis for this section.';

  @override
  String get sectionAudio => 'Audio';

  @override
  String get serviceUnavailable =>
      'This service is currently unavailable. Please try again shortly.';

  @override
  String serviceSignedInAs(String name) {
    return 'You\'re signed in as $name.';
  }

  @override
  String get serviceGenericUser => 'user';

  @override
  String get serviceContinueSignInBrowser =>
      'Continue signing in in your browser…';

  @override
  String get serviceUnexpectedSignInError =>
      'Something went wrong while signing in. Please try again.';

  @override
  String get serviceAuthRateLimited =>
      'Too many attempts — please wait a minute and try again.';

  @override
  String get serviceAuthEmailInvalid =>
      'That email address doesn\'t look right. Please check it.';

  @override
  String get serviceAuthOtpExpired =>
      'The code has expired — request a new one.';

  @override
  String get serviceAuthOtpDisabled =>
      'Sign-in by code is currently unavailable.';

  @override
  String get serviceAuthUserBanned => 'This account is temporarily blocked.';

  @override
  String get serviceAuthSignupDisabled =>
      'New account sign-ups are currently disabled.';

  @override
  String get serviceAuthProviderDisabled =>
      'This sign-in method is currently unavailable.';

  @override
  String get serviceAuthEmailNotConfirmed =>
      'This email address hasn\'t been confirmed yet.';

  @override
  String get serviceAuthNoServerConnection =>
      'Can\'t reach the server. Check your connection and try again.';

  @override
  String get serviceAuthSignInFailed => 'Sign-in failed. Please try again.';

  @override
  String get serviceAccountNoEmailPasskey =>
      'Your account has no email address, so a passkey isn\'t possible right now.';

  @override
  String get servicePasskeyAddedToAccount =>
      'Your passkey was added to your account.';

  @override
  String get servicePasskeyCreated => 'Your passkey was created.';

  @override
  String get serviceEmailSendFailed =>
      'We couldn\'t send the email. Please try again.';

  @override
  String get serviceSignInSuccess => 'You\'re signed in.';

  @override
  String get serviceOtpInvalidOrExpired =>
      'The code is incorrect or has expired — check it or request a new one.';

  @override
  String get serviceOtpCheckFailed => 'We couldn\'t verify the code.';

  @override
  String get serviceAccountDeleteUnavailable =>
      'Deleting your account from the app isn\'t available yet. Email privacy@italk.hr and we\'ll delete it for you.';

  @override
  String serviceAccountDeleteFailedWithStatus(String status) {
    return 'We couldn\'t delete your account ($status). Please try again.';
  }

  @override
  String get serviceAccountDeleteFailed =>
      'We couldn\'t delete your account. Please try again.';

  @override
  String get serviceAccountDeleted =>
      'Your account has been permanently deleted.';

  @override
  String get serviceSignedOutGuest =>
      'You\'re signed out — continuing as a guest.';

  @override
  String get serviceEmailDialogTitle => 'Your email';

  @override
  String get serviceEmailDialogMessage =>
      'We\'ll send you a link and a six-digit code to sign in.';

  @override
  String get serviceEmailDialogHint => 'name@example.com';

  @override
  String get serviceEmailDialogConfirm => 'Send';

  @override
  String get servicePasskeyRequestInProgress =>
      'A passkey request is already in progress — wait for it to finish or refresh the page.';

  @override
  String get servicePasskeyRegisterCancelled =>
      'Passkey registration was cancelled or timed out. Please try again.';

  @override
  String get servicePasskeyPasswordManagerBlockRegister =>
      'A password manager (e.g. LastPass) is blocking the passkey. In its dialog choose \"Use a different passkey\" and pick iCloud/Apple Passwords — or disable LastPass for this site.';

  @override
  String get servicePasskeyAlreadyExists =>
      'This device already has a passkey for this account.';

  @override
  String get servicePasskeyDomainNotAssociated =>
      'This domain isn\'t set up for passkeys. Please try again later.';

  @override
  String get servicePasskeyDeviceUnsupported =>
      'This device doesn\'t support passkeys.';

  @override
  String get servicePasskeyCreateFailed =>
      'A passkey can\'t be created on this device.';

  @override
  String get servicePasskeyNoneOnDevice =>
      'There\'s no passkey saved on this device.';

  @override
  String get servicePasskeyLoginCancelled =>
      'Passkey sign-in was cancelled or timed out. Please try again.';

  @override
  String get servicePasskeyPasswordManagerBlockLogin =>
      'A password manager (e.g. LastPass) is blocking the passkey. In its dialog choose \"Use a different passkey\" — or disable LastPass for this site.';

  @override
  String get servicePasskeyLoginFailed => 'Passkey sign-in failed.';

  @override
  String get servicePasskeyManageUnavailable =>
      'Managing passkeys isn\'t available yet.';

  @override
  String servicePasskeyFetchFailedWithStatus(String status) {
    return 'We couldn\'t load your passkeys ($status).';
  }

  @override
  String get servicePasskeyRemoveUnavailable =>
      'Removing passkeys isn\'t available yet.';

  @override
  String servicePasskeyRemoveFailedWithStatus(String status) {
    return 'We couldn\'t remove the passkey ($status).';
  }

  @override
  String get servicePasskeyFinishFailed =>
      'We couldn\'t finish signing in with your passkey.';

  @override
  String get serviceBackendNoSignInData =>
      'The server didn\'t return the sign-in details.';

  @override
  String get servicePasskeyEmailRequired =>
      'Enter an email to create an account with a passkey.';

  @override
  String servicePasskeyPrepareFailedWithStatus(String status) {
    return 'We couldn\'t prepare the passkey ($status).';
  }

  @override
  String get servicePasskeyNotVerified =>
      'The passkey couldn\'t be verified. Please try again.';

  @override
  String get servicePasskeyUnknownCredential =>
      'This passkey isn\'t recognised — it may belong to a different account.';

  @override
  String get servicePasskeyAccountExists =>
      'An account with that email already exists — sign in with your passkey or Google.';

  @override
  String get serviceSessionExpired =>
      'Your session has expired. Please try again.';

  @override
  String servicePasskeyFinishFailedWithStatus(String status) {
    return 'We couldn\'t finish signing in with your passkey ($status).';
  }

  @override
  String get serviceCertiliaCancelled =>
      'Sign-in with your e-ID was cancelled.';

  @override
  String get serviceCertiliaServerUnavailable =>
      'Certilia is currently unavailable. Please try again shortly.';

  @override
  String get serviceCertiliaFailed => 'Sign-in with your e-ID failed.';

  @override
  String get serviceCertiliaMissingToken =>
      'Certilia didn\'t return a token. Please try again.';

  @override
  String get serviceCertiliaFinishFailed =>
      'We couldn\'t finish signing in with your e-ID.';

  @override
  String get serviceCertiliaInvalidToken =>
      'The Certilia token is invalid. Please try again.';

  @override
  String get serviceCertiliaNoOib =>
      'Certilia didn\'t return an OIB, so sign-in isn\'t possible.';

  @override
  String serviceCertiliaLinkFailedWithStatus(String status) {
    return 'We couldn\'t link your account ($status).';
  }

  @override
  String get serviceHandoffCodeSixDigits =>
      'The code must be exactly six digits.';

  @override
  String get serviceHandoffNoSignInLink =>
      'The server didn\'t return a sign-in link.';

  @override
  String get serviceHandoffNoActiveSession =>
      'This device has no active session — refresh the page and try again.';

  @override
  String get serviceHandoffInvalidOrExpiredCode =>
      'This code doesn\'t exist or has expired.';

  @override
  String get serviceHandoffRequestError =>
      'There was a problem reaching the server. Please try again.';

  @override
  String serviceHandoffTransferFailedWithStatus(String status) {
    return 'The transfer failed ($status).';
  }

  @override
  String get serviceClaimNoAuthUrl =>
      'The server didn\'t return an authorization link.';

  @override
  String get serviceClaimMismatchNoChannel =>
      'The signed-in Google account doesn\'t own this channel. This account doesn\'t manage any YouTube channel. Sign in with the Google account that owns the channel (not just an editor).';

  @override
  String serviceClaimMismatchWithChannel(String name) {
    return 'The signed-in Google account doesn\'t own this channel. With this account you manage the channel: $name. Sign in with the Google account that owns the channel (not just an editor).';
  }

  @override
  String get serviceClaimRevokeFailed =>
      'We couldn\'t release ownership of the channel.';

  @override
  String get serviceClaimChannelMismatch =>
      'The signed-in YouTube account doesn\'t own this channel.';

  @override
  String get serviceClaimNoChannel =>
      'This Google account has no YouTube channel.';

  @override
  String get serviceClaimInvalidState =>
      'The authorization expired. Please try again.';

  @override
  String get serviceClaimAlreadyClaimed =>
      'This channel has already been claimed by another user.';

  @override
  String get serviceClaimNotSignedIn =>
      'You must be signed in to claim a channel.';

  @override
  String get serviceClaimVerifyFailed =>
      'We couldn\'t verify ownership. Please try again.';

  @override
  String get serviceSafeNotEligible =>
      'You don\'t meet the payout requirements yet (ownership, verified identity and a recent re-check).';

  @override
  String get serviceSafeKycRequired =>
      'To receive a payout, first verify your identity with your e-ID (Certilia).';

  @override
  String get serviceSafeWalletNotRegistered =>
      'This wallet address isn\'t registered to your account.';

  @override
  String get serviceSafeNoSafe => 'There\'s no wallet for this episode yet.';

  @override
  String get serviceSafeFrozen => 'This episode\'s wallet is currently frozen.';

  @override
  String get serviceSafeReverifyNeeded =>
      'Ownership needs to be re-verified before a payout.';

  @override
  String get serviceSafeConnectFailed =>
      'We couldn\'t connect to the wallet. Please try again.';

  @override
  String get serviceWalletInvalidAddress =>
      'That wallet address isn\'t valid (it should be 0x followed by 40 hexadecimal characters).';

  @override
  String get serviceWalletNotSignedIn =>
      'You must be signed in to register a wallet.';

  @override
  String get serviceWalletSaveFailed => 'We couldn\'t save your wallet.';

  @override
  String get serviceWalletRemoveFailed => 'We couldn\'t remove your wallet.';

  @override
  String get servicePurchasePackageUnavailable =>
      'This plan is no longer available. Please try again.';

  @override
  String get servicePurchaseNotActivated =>
      'The purchase didn\'t activate your subscription.';

  @override
  String get servicePurchaseFailed =>
      'The purchase didn\'t go through. Please try again.';

  @override
  String get serviceRestoreNoSubscription =>
      'We couldn\'t find an active subscription to restore.';

  @override
  String get serviceRestoreFailed =>
      'We couldn\'t restore your purchases. Please try again.';

  @override
  String get servicePurchaseNotAllowed =>
      'Purchases aren\'t allowed on this device.';

  @override
  String get servicePurchasePending =>
      'Your payment is processing — your subscription activates once it\'s confirmed.';

  @override
  String get servicePurchaseAlreadyOwned =>
      'You already have this subscription. Try \"Restore purchases\".';

  @override
  String get servicePurchaseNetworkError =>
      'Can\'t reach the store. Check your connection and try again.';

  @override
  String get servicePurchaseStoreProblem =>
      'The store isn\'t responding right now. Please try again later.';

  @override
  String tvChannelLoadError(String details) {
    return 'We couldn\'t load this channel:\n$details';
  }

  @override
  String get tvChannelNoEpisodes => 'This channel has no episodes yet.';

  @override
  String tvEpisodeCountPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '$count episode',
    );
    return '$_temp0';
  }

  @override
  String get tvReaderPreparing => 'Preparing reader…';

  @override
  String get tvReaderNotAiProcessed =>
      'This episode hasn\'t been processed by AI yet.\nReader view isn\'t available.';

  @override
  String tvLoadError(String details) {
    return 'Something went wrong while loading:\n$details';
  }

  @override
  String get tvReaderOpenClassic => 'Open standard view';

  @override
  String tvReaderSectionOf(int current, int total) {
    return 'Section $current / $total';
  }

  @override
  String get tvLive => 'Live';

  @override
  String get tvPaused => 'Paused';

  @override
  String get tvReaderNoCommentary =>
      'No theological commentary for this passage.';

  @override
  String get tvReaderChurchTeaching => 'Church teaching for this passage';

  @override
  String get tvReaderOpenFullCommentary => 'OK — open full commentary';

  @override
  String get tvReaderControlsHint =>
      'OK = play/pause   ◀ ▶ = sections   ▼ = Magisterium   BACK = video';

  @override
  String get tvReaderHeadingAssessment => 'Assessment';

  @override
  String get tvReaderHeadingConcerns => 'Points of caution';

  @override
  String get tvReaderHeadingEnrichment => 'Further context';

  @override
  String get tvReaderHeadingCitations => 'Citations from the Magisterium';

  @override
  String get tvReaderCloseHint => 'BACK or OK = close';

  @override
  String get tvRead => 'Read';

  @override
  String get tvFullscreen => 'Fullscreen';

  @override
  String get tvExitFullscreen => 'Exit fullscreen';

  @override
  String get tvLoadingEpisode => 'Loading episode…';

  @override
  String tvEpisodeNotFound(String id) {
    return 'Episode \"$id\" not found.';
  }

  @override
  String get tvBufferStartingEngine => 'Starting the media engine…';

  @override
  String get tvBufferLoadingVideo => 'Loading video…';

  @override
  String get tvBufferFilling => 'Buffering…';

  @override
  String get tvPlayerHint => 'OK = play/pause     ▲ = Read / Fullscreen';

  @override
  String get tvPlayerHintFullscreen => 'OK = play/pause     BACK / F = exit';

  @override
  String tvChaptersWithCount(int count) {
    return 'Chapters ($count)';
  }

  @override
  String get tvSearch => 'Search';

  @override
  String get tvRailContinueListening => 'Continue listening';

  @override
  String get tvRailLatestEpisodes => 'Latest episodes';

  @override
  String tvChannelsWithCount(int count) {
    return 'Channels ($count)';
  }

  @override
  String get tvSortEpisodes => 'Episodes';

  @override
  String get tvSortAlpha => 'A–Z';

  @override
  String get tvSortShuffle => 'Shuffle';

  @override
  String tvLoadingChannels(int loaded, int total) {
    return 'Loading $loaded/$total channels…';
  }

  @override
  String get tvTipsPreparingCatalog => 'Preparing the catalogue…';

  @override
  String get tvPlay => 'Play';

  @override
  String get authSectionLanguage => 'Language';

  @override
  String personEpisodesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '$count episode',
    );
    return '$_temp0';
  }

  @override
  String get personAppearsOn => 'Appears on';

  @override
  String get personActivityOverTime => 'Activity over time';

  @override
  String get personEpisodesHeading => 'Episodes';

  @override
  String get personNotFoundTitle => 'Person not found';

  @override
  String get personNotFoundBody =>
      'This person isn\'t in our speaker database yet, or has no processed episodes.';

  @override
  String get personShareTooltip => 'Share profile';

  @override
  String get personLinkCopied => 'Profile link copied';

  @override
  String get personMentionedIn => 'Mentioned in';

  @override
  String get appInstallBannerIos => 'DOMOVINA.ai also has an iPhone app.';

  @override
  String get appInstallBannerAndroid => 'DOMOVINA.ai also has an Android app.';

  @override
  String get appInstallBannerAction => 'Get it';

  @override
  String get pinkaGridIntro =>
      'Every square is one contribution — the closer to the centre, the bigger the support.';

  @override
  String get pinkaGridTapHint => 'Tap a free square to pick your amount.';

  @override
  String get pinkaGridZoneOuterBelt => 'Outer belt';

  @override
  String get pinkaGridZoneDefenseRing => 'Defense ring';

  @override
  String get pinkaGridZoneMidBelt => 'Midfield belt';

  @override
  String get pinkaGridZoneHighZone => 'High ground';

  @override
  String get pinkaGridZoneGoldenCircle => 'Golden circle';

  @override
  String get pinkaGridZoneBusiness => 'Business zone';

  @override
  String get pinkaGridZoneExecutive => 'Executive zone';

  @override
  String get pinkaGridZonePrestige => 'Prestige';

  @override
  String get pinkaGridZoneElite => 'Elite';

  @override
  String get pinkaGridZoneCore => 'Core';

  @override
  String pinkaGridZonePriceLabel(String name, String price) {
    return '$name · $price €';
  }

  @override
  String pinkaGridAmountSet(String name, String price) {
    return '$name — amount set to $price €.';
  }

  @override
  String get pinkaGridTakenTitle => 'This square is already taken';

  @override
  String get pinkaSlotIntro =>
      'Pick your square — the closer to the centre, the bigger the contribution. Your spot is held while you pay.';

  @override
  String pinkaSlotZoneFallback(int index) {
    return 'Zone $index';
  }

  @override
  String get pinkaSlotStatusHeld => 'Held — someone is paying right now';

  @override
  String get pinkaSlotStatusBlocked => 'This spot is not for sale';

  @override
  String get pinkaSlotHeldTitle => 'This square is held';

  @override
  String get pinkaSlotHeldBody =>
      'Someone is paying for it right now. If the payment doesn\'t land, the square goes back up — try later or pick another one.';

  @override
  String pinkaSlotPriceLocked(String price) {
    return 'Price of this spot: $price €';
  }

  @override
  String get pinkaSlotTopUpHint =>
      'You can give more — less than the price of the spot you can\'t.';

  @override
  String get pinkaSlotTopUpLabel => 'Amount';

  @override
  String get pinkaSlotClear => 'Cancel';

  @override
  String pinkaSlotBelowPrice(String price) {
    return 'The amount can\'t be lower than the price of the spot ($price €).';
  }

  @override
  String get pinkaSlotTakenError =>
      'Someone was faster — that square has just been taken. Pick another one.';

  @override
  String pinkaSlotHoldCountdown(String time) {
    return 'Your spot is held for another $time.';
  }

  @override
  String get pinkaSlotHoldExpired =>
      'The hold expired, but your payment still counts — once it lands you get the same square if it\'s free, otherwise the nearest one in the same or a pricier zone.';

  @override
  String get pinkaSlotHoldReserved => 'Your spot is held.';

  @override
  String get pinkaSlotHoldReassure =>
      'If the transfer stalls at your bank\'s or the recipient\'s checks, don\'t worry — as long as it arrives within 24 hours we\'ll process it.';

  @override
  String get pinkaSlotPickerOpen => 'Zoom in';

  @override
  String get pinkaSlotPickerTitle => 'Pick your spot';

  @override
  String get pinkaSlotPickerHint =>
      'Drag and pinch to zoom; the square under the crosshair is your pick.';

  @override
  String pinkaSlotPickerConfirm(String price) {
    return 'Confirm spot · $price €';
  }

  @override
  String get pinkaSlotPickerTaken => 'This spot is taken';

  @override
  String get pinkaSlotPickerOffGrid => 'Move the crosshair onto the grid';
}
