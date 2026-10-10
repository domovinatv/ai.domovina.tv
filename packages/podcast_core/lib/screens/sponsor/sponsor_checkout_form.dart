import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/sponsor_offer.dart';
import '../../models/sponsored_moment.dart';
import '../../pinka_sdk/pinka_sdk.dart';
import '../../router/nav.dart' show closeOnRouteChange;
import '../../services/file_pick.dart';
import '../../services/sponsored_moments_service.dart';
import '../../widgets/sponsor_timeline_bar.dart';
import '../../widgets/sponsored_moment_widgets.dart';
import '../../widgets/sponsors_in_video_section.dart' show formatSponsorClock;

/// Ono što forma preda ekranu: narudžba bez `logo_path` + bajtovi loga koje
/// ekran uploada tek na „Nastavi na plaćanje" (upload traži sesiju, a
/// korisnik do zadnjeg trenutka može logo maknuti).
typedef SponsorCheckoutDraft = ({
  PinkaSponsorOrder order,
  ({Uint8List bytes, String ext})? logo,
});

/// Unos forme koji mora preživjeti povratak na kartu (409 `slot_taken`,
/// „Promijeni trenutak"): vlasnik je ekran, ne `State` forme — inače bi kupac
/// nakon sudara oko trenutka sve podatke tvrtke tipkao ispočetka.
class SponsorCheckoutFormData {
  final brand = TextEditingController();
  final tagline = TextEditingController();
  final link = TextEditingController();
  final company = TextEditingController();
  final oib = TextEditingController();
  final vat = TextEditingController();
  final street = TextEditingController();
  final city = TextEditingController();
  final postal = TextEditingController();
  final country = TextEditingController(text: 'HR');
  final email = TextEditingController();
  final reference = TextEditingController();
  bool terms = false;
  ({Uint8List bytes, String ext})? logo;

  List<TextEditingController> get _all => [
    brand,
    tagline,
    link,
    company,
    oib,
    vat,
    street,
    city,
    postal,
    country,
    email,
    reference,
  ];

  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
  }
}

/// Forma checkouta: kreativa, podaci za račun, pregled i kvačica uvjeta.
///
/// Validacija zrcali ugovor §5 (duljine, https, OIB kontrolna znamenka, VAT
/// oblik) da korisnik grešku vidi prije mreže; server je i dalje provjerava i
/// tada vraća `invalid_sponsor:<polje>` koji ekran prikaže iznad gumba.
class SponsorCheckoutForm extends StatefulWidget {
  final SponsorOffer offer;
  final SponsorCheckoutFormData data;
  final bool submitting;
  final String? error;
  final VoidCallback onChangeMoment;
  final void Function(SponsorCheckoutDraft draft) onSubmit;

  const SponsorCheckoutForm({
    super.key,
    required this.offer,
    required this.data,
    required this.submitting,
    required this.onChangeMoment,
    required this.onSubmit,
    this.error,
  });

  @override
  State<SponsorCheckoutForm> createState() => _SponsorCheckoutFormState();
}

class _SponsorCheckoutFormState extends State<SponsorCheckoutForm> {
  final _formKey = GlobalKey<FormState>();
  bool _termsError = false;
  String? _logoError;

  SponsorCheckoutFormData get _d => widget.data;
  TextEditingController get _brand => _d.brand;
  TextEditingController get _tagline => _d.tagline;
  TextEditingController get _link => _d.link;
  TextEditingController get _company => _d.company;
  TextEditingController get _oib => _d.oib;
  TextEditingController get _vat => _d.vat;
  TextEditingController get _street => _d.street;
  TextEditingController get _city => _d.city;
  TextEditingController get _postal => _d.postal;
  TextEditingController get _country => _d.country;
  TextEditingController get _email => _d.email;
  TextEditingController get _reference => _d.reference;
  bool get _terms => _d.terms;
  set _terms(bool v) => _d.terms = v;
  ({Uint8List bytes, String ext})? get _logo => _d.logo;
  set _logo(({Uint8List bytes, String ext})? v) => _d.logo = v;

  void _rebuild() => setState(() {});

  @override
  void initState() {
    super.initState();
    // Pregled se crta iz polja kreative dok korisnik tipka.
    for (final c in [_brand, _tagline, _link]) {
      c.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    // Kontroleri pripadaju ekranu; ovdje se samo odjavljujemo.
    for (final c in [_brand, _tagline, _link]) {
      c.removeListener(_rebuild);
    }
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picked = await pickImageFile();
    if (picked == null || !mounted) return;
    final dot = picked.name.lastIndexOf('.');
    final ext = dot < 0 ? '' : picked.name.substring(dot + 1).toLowerCase();
    final l = AppLocalizations.of(context);
    if (!SponsorCampaign.logoExtensions.contains(ext)) {
      setState(() => _logoError = l.sponsorLogoBadType);
      return;
    }
    if (picked.bytes.length > SponsorCampaign.logoMaxBytes) {
      setState(() => _logoError = l.sponsorLogoTooBig);
      return;
    }
    setState(() {
      _logo = (bytes: picked.bytes, ext: ext);
      _logoError = null;
    });
  }

  void _submit() {
    final ok = _formKey.currentState?.validate() ?? false;
    setState(() => _termsError = !_terms);
    if (!ok || !_terms) return;
    widget.onSubmit((
      order: PinkaSponsorOrder(
        brand: _brand.text,
        tagline: _tagline.text,
        linkUrl: _link.text,
        termsAccepted: _terms,
        buyer: PinkaSponsorBuyer(
          company: _company.text,
          oib: _oib.text,
          vatId: _vat.text,
          email: _email.text,
          street: _street.text,
          city: _city.text,
          postalCode: _postal.text,
          country: _country.text,
          reference: _reference.text,
        ),
      ),
      logo: _logo,
    ));
  }

  // ── validatori (ugovor §5) ────────────────────────────────────────────
  String? Function(String?) _len(int max, {bool required = false}) {
    final l = AppLocalizations.of(context);
    return (v) {
      final t = (v ?? '').trim();
      if (required && t.isEmpty) return l.sponsorErrorRequired;
      if (t.length > max) return l.sponsorErrorTooLong(max);
      return null;
    };
  }

  String? _validateLink(String? v) {
    final l = AppLocalizations.of(context);
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final uri = Uri.tryParse(t);
    if (t.length > 500 ||
        t.contains(' ') ||
        uri == null ||
        !uri.isScheme('https') ||
        uri.host.isEmpty) {
      return l.sponsorErrorLink;
    }
    return null;
  }

  String? _validateOib(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return isValidOib(t) ? null : AppLocalizations.of(context).sponsorErrorOib;
  }

  String? _validateVat(String? v) {
    final t = (v ?? '').replaceAll(' ', '').toUpperCase();
    if (t.isEmpty) return null;
    return RegExp(r'^[A-Z]{2}[A-Z0-9]{2,13}$').hasMatch(t)
        ? null
        : AppLocalizations.of(context).sponsorErrorVat;
  }

  String? _validateEmail(String? v) {
    final l = AppLocalizations.of(context);
    final t = (v ?? '').trim();
    if (t.isEmpty) return l.sponsorErrorRequired;
    if (t.length > 200 || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
      return l.sponsorErrorEmail;
    }
    return null;
  }

  String? _validateCountry(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    return RegExp(r'^[A-Za-z]{2}$').hasMatch(t)
        ? null
        : AppLocalizations.of(context).sponsorErrorCountry;
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? Function(String?)? validator,
    String? helper,
    TextInputType? keyboard,
    int? maxLength,
    Iterable<String>? autofill,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: c,
      enabled: !widget.submitting,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
      maxLength: maxLength,
      keyboardType: keyboard,
      autofillHints: autofill,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final o = widget.offer;
    final range =
        '${formatSponsorClock(o.start)}–${formatSponsorClock(o.end)}';
    final zone = sponsorZoneLabel(o.zone, l);
    final heading = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );

    final preview = SponsoredMoment(
      slotKey: o.slotKey,
      youtubeId: o.youtubeId,
      start: o.start,
      end: o.end,
      brand: _brand.text.trim().isEmpty ? '…' : _brand.text.trim(),
      tagline: _tagline.text.trim().isEmpty ? null : _tagline.text.trim(),
      linkUrl: _validateLink(_link.text) == null && _link.text.trim().isNotEmpty
          ? _link.text.trim()
          : null,
    );

    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.sponsorCheckoutTitle, style: heading),
            const SizedBox(height: 6),
            Text(l.sponsorCheckoutMoment(range, zone)),
            if (o.title != null)
              Text(
                o.title!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              '${l.sponsorPriceGross(fmtEur(o.priceCents))} · '
              '${l.sponsorRunDays(o.runDays)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.arrow_back, size: 16),
                label: Text(l.sponsorCheckoutChange),
                onPressed: widget.submitting ? null : widget.onChangeMoment,
              ),
            ),
            const SizedBox(height: 12),
            Text(l.sponsorCreativeSection, style: heading),
            const SizedBox(height: 10),
            _field(
              _brand,
              l.sponsorFieldBrand,
              helper: l.sponsorFieldBrandHelp,
              maxLength: 60,
              validator: _len(60, required: true),
            ),
            _field(
              _tagline,
              l.sponsorFieldTagline,
              maxLength: 120,
              validator: _len(120),
            ),
            _field(
              _link,
              l.sponsorFieldLink,
              keyboard: TextInputType.url,
              validator: _validateLink,
              autofill: const [AutofillHints.url],
            ),
            if (fileUploadSupported) ...[
              Text(
                l.sponsorFieldLogo,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (_logo != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(
                        _logo!.bytes,
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: widget.submitting
                          ? null
                          : () => setState(() => _logo = null),
                      child: Text(l.sponsorLogoRemove),
                    ),
                  ] else
                    OutlinedButton.icon(
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: Text(l.sponsorLogoPick),
                      onPressed: widget.submitting ? null : _pickLogo,
                    ),
                ],
              ),
              if (_logoError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _logoError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            Text(l.sponsorPreviewTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            SponsoredMomentCard(moment: preview, active: true),
            const SizedBox(height: 24),
            Text(l.sponsorCompanySection, style: heading),
            const SizedBox(height: 10),
            _field(
              _company,
              l.sponsorFieldCompany,
              maxLength: 200,
              validator: _len(200, required: true),
              autofill: const [AutofillHints.organizationName],
            ),
            _field(
              _oib,
              l.sponsorFieldOib,
              keyboard: TextInputType.number,
              maxLength: 11,
              validator: _validateOib,
            ),
            _field(_vat, l.sponsorFieldVat, validator: _validateVat),
            _field(
              _street,
              l.sponsorFieldStreet,
              maxLength: 200,
              validator: _len(200),
              autofill: const [AutofillHints.streetAddressLine1],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    _postal,
                    l.sponsorFieldPostal,
                    maxLength: 16,
                    validator: _len(16),
                    autofill: const [AutofillHints.postalCode],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _field(
                    _city,
                    l.sponsorFieldCity,
                    maxLength: 100,
                    validator: _len(100),
                    autofill: const [AutofillHints.addressCity],
                  ),
                ),
              ],
            ),
            _field(
              _country,
              l.sponsorFieldCountry,
              maxLength: 2,
              validator: _validateCountry,
              autofill: const [AutofillHints.countryCode],
            ),
            _field(
              _email,
              l.sponsorFieldEmail,
              keyboard: TextInputType.emailAddress,
              validator: _validateEmail,
              autofill: const [AutofillHints.email],
            ),
            _field(
              _reference,
              l.sponsorFieldReference,
              maxLength: 100,
              validator: _len(100),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _terms,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.sponsorTermsAccept),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => showSponsorTerms(context),
                  child: Text(l.sponsorTermsRead),
                ),
              ),
              onChanged: widget.submitting
                  ? null
                  : (v) => setState(() {
                      _terms = v ?? false;
                      if (_terms) _termsError = false;
                    }),
            ),
            if (_termsError)
              Text(
                l.sponsorErrorTerms,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            if (widget.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: widget.submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_2),
              label: Text(l.sponsorSubmit),
              onPressed: widget.submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Uvjeti oglašavanja — formalni registar („Vi"), jer su ugovorni tekst.
Future<void> showSponsorTerms(BuildContext context) {
  final l = AppLocalizations.of(context);
  // Browserov Back mijenja rutu ISPOD dijaloga — vidi `closeOnRouteChange`.
  final navigator = Navigator.of(context);
  late final VoidCallback unsubscribe;
  unsubscribe = closeOnRouteChange(context, () {
    if (navigator.canPop()) navigator.pop();
  });
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.sponsorTermsTitle),
      content: SingleChildScrollView(child: Text(l.sponsorTermsBody)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l.commonClose),
        ),
      ],
    ),
  ).whenComplete(unsubscribe);
}
