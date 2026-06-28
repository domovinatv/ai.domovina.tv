import 'package:flutter_test/flutter_test.dart';
import 'package:domovina_ai/services/revenue_cat/rc_models.dart';
import 'package:domovina_ai/screens/subscribe/upgrade_trigger.dart';

RcPackage pkg(RcPlan plan, String id) => RcPackage(
      id: id,
      plan: plan,
      productId: 'domovina_plus_${plan.name}',
      priceString: '0,00 €',
      title: plan.name,
    );

void main() {
  group('RcOfferings plan selection', () {
    test('picks the right package per plan', () {
      final offerings = RcOfferings([
        pkg(RcPlan.monthly, r'$rc_monthly'),
        pkg(RcPlan.annual, r'$rc_annual'),
        pkg(RcPlan.lifetime, r'$rc_lifetime'),
      ]);
      expect(offerings.monthly?.id, r'$rc_monthly');
      expect(offerings.annual?.id, r'$rc_annual');
      expect(offerings.lifetime?.id, r'$rc_lifetime');
      expect(offerings.isEmpty, isFalse);
    });

    test('missing plans return null; empty is empty', () {
      final offerings = RcOfferings([pkg(RcPlan.monthly, r'$rc_monthly')]);
      expect(offerings.monthly, isNotNull);
      expect(offerings.annual, isNull);
      expect(offerings.lifetime, isNull);
      expect(RcOfferings.empty.isEmpty, isTrue);
      expect(RcOfferings.empty.monthly, isNull);
    });
  });

  group('RcPurchaseResult', () {
    test('ok only for success', () {
      expect(const RcPurchaseResult(RcPurchaseStatus.success).ok, isTrue);
      expect(RcPurchaseResult.cancelled.ok, isFalse);
      expect(RcPurchaseResult.unsupported.ok, isFalse);
    });
  });

  group('entitlement constant', () {
    test('matches the single gated entitlement id', () {
      expect(kDomovinaPlusEntitlement, 'domovina_plus');
      expect(kDefaultOfferingId, 'default');
    });
  });

  group('UpgradeTrigger', () {
    test('slug round-trips for every value', () {
      for (final t in UpgradeTrigger.values) {
        expect(UpgradeTriggerCopy.fromSlug(t.slug), t);
      }
    });

    test('unknown / null slug falls back to generic', () {
      expect(UpgradeTriggerCopy.fromSlug('nonsense'), UpgradeTrigger.generic);
      expect(UpgradeTriggerCopy.fromSlug(null), UpgradeTrigger.generic);
    });

    test('every trigger has non-empty headline + subtitle', () {
      for (final t in UpgradeTrigger.values) {
        expect(t.headline, isNotEmpty);
        expect(t.subtitle, isNotEmpty);
      }
    });
  });
}
