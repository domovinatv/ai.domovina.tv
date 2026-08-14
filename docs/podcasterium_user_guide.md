# Podcasterium — što korisnik i kreator stvarno dobiju

*Verificirano protiv `main` @ 7de73ea, 14. kolovoza 2026.*

Ovo je vodič kroz **ono što postoji danas u produkciji**. Svaka tvrdnja se
može otvoriti u aplikaciji. Ono što još ne postoji je na kraju, pod „Što još
ne radimo" — jer obećanje koje aplikacija ne ispuni košta više nego značajka
koju nismo spomenuli.

> **Registar:** aplikacija korisniku govori „ti" (CLAUDE.md, i18n pravilo), pa
> je i ovaj tekst pisan tako. „Vi" ide samo u pravne tekstove i poruke trećim
> stranama.

---

## Za slušatelja

### 1. Gledaš i čitaš istovremeno

Otvoriš epizodu i dobiješ dvoje odjednom: video svira, a uz njega ide
**strukturiran članak** — poglavlja, odlomci, interpunkcija. Nije sirovi
transkript. AI dijeli razgovor na tematske blokove od ~35–45 minuta i piše
novinarski tekst za svaki.

Na širokom ekranu tekst i AI analiza stoje jedno uz drugo i **skrolaju
zajedno** — red uz red, ne dva neovisna stupca.

### 2. Skočiš točno gdje treba

Tap na poglavlje seeka video. Podijeliš li link s vremenskom oznakom
(`/v/<id>/t/<sekunda>`), primatelj otvara točno tu sekundu — i pretpregled
poveznice u Telegramu ili iMessageu pokazuje baš taj dio, ne generičnu sliku.

Možeš izrezati i **cijelo poglavlje kao MP4** i poslati ga kao datoteku.

### 3. Vidiš tko govori

Diarizacija (obrada zvuka, pyannote 3.1) dijeli razgovor po govornicima, pa
uz tekst stoji ime. Titlovi se rendaju iz `diarized.srt` i rade i u fullscreenu.

> Ovo radi **iz zvuka**, ne iz slike. Nema prepoznavanja lica.

### 4. Pratiš osobu kroz cijeli korpus

Klik na ime otvara profil osobe (`/p/:slug`) koji spaja dvije stvari koje
druge platforme drže odvojeno:

- **gdje ta osoba govori** — epizode u kojima je diariziran govornik
- **gdje se spominje** — epizode u kojima ju netko drugi spominje

Zato profil postoji i za nekoga tko nikad nije bio gost. Kad spomen ima
razriješenu sekundu, tap seeka na nju; kad nema (oko 40 % spomena), otvara
epizodu od početka — i sučelje to jasno razlikuje, nikad ne tvrdi „govori
ovdje" ako to ne zna.

### 5. Tražiš na dva načina

- **Po riječi** — Meilisearch, trpi tipfelere, dijakritike su svejedno.
- **Po značenju** — semantička pretraga vraća isječak transkripta s točnom
  sekundom i deep-linkom, čak i kad tvoje riječi nisu izgovorene.

### 6. Slušaš gdje god jesi

Web (uključujući PWA na iPhoneu, s kontrolama na zaključanom zaslonu), iOS,
Android, i **Android TV s daljinskim** — zasebno Leanback sučelje, ne
razvučena mobilna aplikacija. Handoff prebacuje sesiju mobitel ↔ web.

Postoji i PiP, brzina reprodukcije, poništavanje slučajnog skoka („Undo"),
favoriti i nastavak gledanja gdje si stao.

### 7. Neke epizode nisu videi

Dio korpusa su audio podcasti bez videa. Aplikacija to sama razriješi i
prikaže cover art umjesto praznog playera.

---

## Za kreatora

### Što dobiješ

Tvoja epizoda postaje **pretraživ, indeksiran, čitljiv dokument** — bez tvog
dodatnog rada na tekstu. Publika koja dolazi čitati je drukčija od publike
koja skrola: studenti, novinari, ljudi koji citiraju.

Nema preporuka sa strane. Nema Shortsa. Nema sljedećeg videa koji otima
gledatelja usred tvoje rečenice.

### Kako se kanal preuzima

1. Otvoriš stranicu svog kanala i klikneš preuzimanje vlasništva (`/c/:slug/claim`).
2. Dokažeš da je kanal tvoj kroz YouTube (`/youtube-claim/callback`).
3. Za isplate ide KYC provjera; sredstva idu na Safe Multisig gdje si supotpisnik.

Nakon toga imaš `/account/channels` — pregled kanala i pinka kampanja.

### Podrška publike

Gledatelj može poduprijeti kanal izravno, kroz panel unutar članka:
**SEPA (EPC QR kod)** ili **on-chain (EURe/MPT)**. Podrška se vidi na zidu
podrške — mreži 120×120 na stranici kanala.

> Iskreno o proviziji: „bez posrednika" vrijedi za SEPA i on-chain rail, gdje
> novac ide izravno. Pretplate kroz iOS i Android aplikaciju idu preko
> trgovina i **nose njihovu proviziju** — to nije nešto što možemo zaobići.

---

## Realno stanje korpusa

Na dan 14. kolovoza 2026.:

| | |
| :--- | ---: |
| Kanala | 48 |
| Epizoda | 3 175 |
| Sati sadržaja | ≈ 3 036 |
| Prosječna epizoda | 57 min |
| **s transkriptom, diarizacijom i člankom** | **3 160 — 99,5 %** |
| s Magisterium ocjenom | 311 — 9,8 % |
| s engleskim prijevodom | 40 — 1,3 % |

Dakle: **gotovo sve što je u katalogu je i obrađeno** — čitljiv članak,
poglavlja i imenovani govornici postoje za 99,5 % epizoda. Petnaestak epizoda
čeka obradu i prikazuju se u osnovnom prikazu.

Dvije stvari su rjeđe nego što se čini iz sučelja:

- **Magisterium ocjena postoji za svaku desetu epizodu.** Kad je nema, epizoda
  je i dalje potpuno čitljiva — samo nema bedž s ocjenom.
- **Engleski prijevod postoji za 40 epizoda.** Gdje ga nema, prebacivač jezika
  ostaje na hrvatskom.

I jedna stvar koju treba znati unaprijed: **članak se piše na hrvatskom bez
obzira na jezik podcasta.** Engleski podcast (npr. Sub Club) dobiva engleski
zvuk i hrvatski tekst uz njega. Za hrvatsku publiku to je značajka; ako
očekuješ engleski članak uz engleski podcast, danas ga nema.

---

## Što još ne radimo

Popis je ovdje namjerno — bolje je znati granicu nego je otkriti.

- **Nema RSS ingestije.** Ulaz je YouTube kanal, X post ili audio feed preko
  našeg pipelinea. „Zalijepi svoj RSS" trenutno ne postoji.
- **Nema samoposlužne obrade.** Kanal ne uđe sam od sebe — pipeline se
  pokreće ručno i traje. „U roku od par sati" nije obećanje koje danas možemo
  održati.
- **Nema prepoznavanja lica ni govornika iz slike.**
- **Ocjena nije provjera činjenica.** Magisterium ocjena mjeri **usklađenost s
  katoličkim naukom** (od „aktivno promiče" do „proturječi"), ne istinitost
  tvrdnji. Ne prodavati je kao fact-checking. Postoji za 9,8 % epizoda.
- **Nema članka na jeziku izvora.** Pipeline piše hrvatski, uvijek.
- **e-Osobna i glasanje su samo za Hrvatsku.** Ovise o sustavu e-Građani.
- **Zaustavljena stavka na iPhone Dynamic Islandu** zna ostati vidljiva nakon
  kraja reprodukcije — poznat browserski problem, ne kvar tvog uređaja.

---

*Tehnički detalji: `docs/podcasterium_technical_manual.md`.
Analiza i pozicioniranje: `docs/podcasterium_analysis_report.md`.*
