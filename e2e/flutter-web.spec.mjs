// @ts-check
import { test, expect } from '@playwright/test';

// Produkcija ili lokalni dev server
const BASE = process.env.BASE_URL || 'https://domovina.ai';
const TEST_VIDEO = 'H-p2Hl6x7I0';

test.describe('HomeScreen', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(BASE, { waitUntil: 'networkidle' });
    // Flutter treba ~2-5s za bootstrap + semantics tree render
    await page.waitForTimeout(5000);
  });

  test('naslov i subtitle su vidljivi u accessibility tree', async ({ page }) => {
    // Flutter semantics generira flt-semantics elemente s ARIA atributima.
    // Playwright getByRole/getByText radi jer čita accessibility tree, ne DOM.
    await expect(page.getByText('Domovina.ai')).toBeAttached();
    await expect(page.getByText('Unesi YouTube ID epizode')).toBeAttached();
  });

  test('input field je interaktivan — unos teksta', async ({ page }) => {
    const input = page.getByRole('textbox', { name: /youtube/i });
    await expect(input).toBeAttached();
    await input.fill(TEST_VIDEO);
  });

  test('gumb "Otvori epizodu" je klikabilan', async ({ page }) => {
    await expect(page.getByRole('button', { name: /otvori/i })).toBeAttached();
  });

  test('validacija — prazni submit ne navigira', async ({ page }) => {
    await page.getByRole('button', { name: /otvori/i }).click();
    await page.waitForTimeout(1000);
    // I dalje na home page
    await expect(page.getByText('Unesi YouTube ID epizode')).toBeAttached();
  });
});

test.describe('EpisodeScreen — navigacija', () => {
  test('direktni URL /v/<id> učitava epizodu', async ({ page }) => {
    await page.goto(`${BASE}/v/${TEST_VIDEO}`, { waitUntil: 'networkidle' });
    // Čekaj Flutter bootstrap + CDN load (5 JSON fajlova paralelno)
    await page.waitForTimeout(10000);
    // HomeScreen input NE smije biti prisutan
    await expect(page.getByText('Unesi YouTube ID epizode')).not.toBeAttached();
  });

  test('video kontrole su u accessibility tree', async ({ page }) => {
    await page.goto(`${BASE}/v/${TEST_VIDEO}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(10000);

    // Play/Pause — tooltip = semantic label
    const play = page.getByRole('button', { name: 'Reproduciraj' });
    const pause = page.getByRole('button', { name: 'Pauziraj' });
    const hasPlay = await play.count() > 0;
    const hasPause = await pause.count() > 0;
    expect(hasPlay || hasPause).toBeTruthy();

    // Skip gumbi
    await expect(page.getByRole('button', { name: '-10s' })).toBeAttached();
    await expect(page.getByRole('button', { name: '+10s' })).toBeAttached();
  });

  test('sadržaj sekcija je pristupačan', async ({ page }) => {
    await page.goto(`${BASE}/v/${TEST_VIDEO}`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(10000);

    // Barem jedna sekcija mora biti u accessibility tree
    const sections = ['Sažetak', 'Poglavlja', 'Članak'];
    let found = 0;
    for (const s of sections) {
      if (await page.getByText(s, { exact: true }).count() > 0) found++;
    }
    expect(found).toBeGreaterThan(0);
  });
});

test.describe('EpisodeScreen — full user flow', () => {
  test('unesi ID na HomeScreen → navigiraj → vidi sadržaj', async ({ page }) => {
    await page.goto(BASE, { waitUntil: 'networkidle' });
    await page.waitForTimeout(5000);

    // 1. Unesi YouTube ID
    const input = page.getByRole('textbox', { name: /youtube/i });
    await input.fill(TEST_VIDEO);

    // 2. Klikni gumb
    await page.getByRole('button', { name: /otvori/i }).click();

    // 3. Čekaj CDN load
    await page.waitForTimeout(12000);

    // 4. Verificiraj da smo na EpisodeScreen
    await expect(page.getByText('Unesi YouTube ID epizode')).not.toBeAttached();

    // 5. Video kontrole postoje
    const play = page.getByRole('button', { name: 'Reproduciraj' });
    const pause = page.getByRole('button', { name: 'Pauziraj' });
    expect((await play.count()) + (await pause.count())).toBeGreaterThan(0);
  });
});

test.describe('Error handling', () => {
  test('nepostojeći video prikazuje error', async ({ page }) => {
    await page.goto(`${BASE}/v/nepostojeci_xyz_000`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(10000);
    await expect(page.getByText('Natrag')).toBeAttached();
  });
});
