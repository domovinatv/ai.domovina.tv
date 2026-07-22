# E2E testiranje (Playwright/Cypress) na Flutter webu

Flutter web crta na canvas (skwasm/WebGL) — DOM nema klasične elemente, pa
standardni selektori ne rade dok se ne uključi **semantics DOM** (Flutterovo
a11y stablo: `flt-semantics` čvorovi s ARIA rolama).

## Kako uključiti semantics

Dvije putanje (obje potvrđene na Flutter 3.41.6 release buildu, bez crasha):

1. **`?a11y=1` query param** — `main.dart` odmah zove `ensureSemantics()`.
   Deterministički, preporučeno za e2e: `https://domovina.ai/c/domovina-tv/doniraj?a11y=1`
2. **Ugrađeni placeholder** — klik na `flt-semantics-placeholder`
   (`role="button"`, `aria-label="Enable accessibility"`); ovim putem idu
   screen readeri. Pali identično stablo.

Povijest: stara CLAUDE.md zabrana ("ensureSemantics crasha release build")
opovrgnuta je mjerenjem 2026-07-22 — vidi CLAUDE.md Known Issues.

## Stabilni identifieri

`Semantics(identifier: '...')` u Dart kodu izlazi kao atribut
`flt-semantics-identifier` na ARIA čvoru. Postojeća sidra (doniraj ekran,
`lib/pinka_sdk/`):

| Identifier | Element |
|---|---|
| `pinka-grid-wall` | Zid podrške (grid kvadratića) |
| `pinka-amount-input` | Polje za vlastiti iznos |
| `pinka-sepa-submit` | SEPA "Podrži s N €" gumb |
| `pinka-wall-list` | Popis podržavatelja |

Konvencija za nova sidra: `<područje>-<element>` kebab-case, dodaješ
`Semantics(identifier: ...)` wrapper (bez aktivnog semantics stabla nema
runtime troška).

## Playwright primjer (/c/domovina-tv/doniraj)

```ts
import { test, expect } from '@playwright/test';

const byId = (id: string) => `[flt-semantics-identifier="${id}"]`;

test('zid podrške: sidra i SEPA gumb', async ({ page }) => {
  await page.goto('https://domovina.ai/c/domovina-tv/doniraj?a11y=1');

  // Semantics DOM se generira nakon prvog framea + fetch kampanje.
  await expect(page.locator(byId('pinka-grid-wall'))).toBeAttached({ timeout: 30_000 });
  await expect(page.locator(byId('pinka-wall-list'))).toBeAttached();

  // Role-based selektori rade normalno (ARIA):
  await expect(page.getByRole('button', { name: /Podrži s/ })).toBeVisible();

  // Iznos + submit preko identifiera:
  await page.locator(byId('pinka-amount-input')).locator('input,textarea').fill('5');
  await page.locator(byId('pinka-sepa-submit')).click();
});
```

Napomene:
- U automation/headless Chromeu nema WebGL-a → CPU fallback rendering je spor;
  koristi izdašne timeoute i verificiraj kroz DOM/konzolu, ne screenshotove.
- `flutter_driver`/`integration_test` s web-driverom postoji, ali standardni
  browser e2e alati preko semantics DOM-a su primarni pristup ovog repoa.
