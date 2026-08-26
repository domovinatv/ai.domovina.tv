# Sponzorski trenuci — kako ovo objasniti čovjeku

*Prateći materijal uz [`plans/2026-08-26-p2p-oglasni-prostor.md`](../plans/2026-08-26-p2p-oglasni-prostor.md).
Ovaj dokument nije tehnički — piše se da se **čita naglas**.*

Četiri čitatelja, četiri različita razgovora: **kreator**, **slušatelj**,
**brand**, **investitor**. Prvo §1 (mehanizam u ljudskim riječima), pa idi ravno
na svoju sekciju.

> **Upute AI asistentu i sebi**: brojke u §2 su **ilustrativna aritmetika**, ne
> cjenik. Pravi cjenik ne postoji jer javnih podataka o cijenama oglasa za
> Hrvatsku nema. §7 je popis tvrdnji koje se **ne smiju** izgovoriti.

---

## 1. Tri načina da se prostor preproda, i zašto smo izabrali treći

Problem je uvijek isti: netko je kupio oglasni prostor, a poslije se pojavi netko
tko bi za isti prostor platio više. Kako to razriješiti, a da nitko ne bude
prevaren?

### 1.1 Aukcija — svi u istoj sobi u isto vrijeme

Klasika. Svi zainteresirani se nadmeću dok jedan ne ostane.

**Zašto kod nas ne radi**: aukcija traži **gomilu ponuđača u istom trenutku**. Za
jedan trenutak u hrvatskom podcastu o poduzetništvu realno postoje dva ili tri
moguća oglašivača, i nisu online u isto vrijeme. Aukcija s dva sudionika nije
otkrivanje cijene nego neugodnost.

Uz to, aukcija rješava **prvu prodaju**. Naš problem je drugi: preuzeti nešto što
je već prodano i već se prikazuje.

### 1.2 Harberger — „sam reci koliko vrijedi, i pripazi što ćeš reći"

Ovo si prvi put čuo, pa idemo polako. Zove se po ekonomistu **Arnoldu
Harbergeru**, a u širu publiku ga je 2018. gurnula knjiga *Radical Markets*
(Posner i Weyl).

Rješava stvaran problem: **vlasnik koji sjedi na nečemu vrijednom i ne da ga
nikome.** Prazna parcela u centru grada. Vlasnik je ne koristi, ali traži
besmislenu cijenu, i tako godinama. Društvo gubi.

Harberger vezuje tri pravila u čvor:

1. **Ti sam objaviš koliko tvoje vlasništvo vrijedi.**
2. **Plaćaš stalni porez na tu tvoju cijenu** (recimo 7 % godišnje).
3. **Bilo tko ti to može kupiti po toj cijeni, kad god hoće, bez tvog pristanka.**

Ljepota je u tome što se pravila 2 i 3 **povlače u suprotnim smjerovima**.

- Kažeš da vrijedi malo → porez ti je jeftin, ali ti to netko odmah otme.
- Kažeš da vrijedi puno → nitko ti ne dira, ali krvariš porez.

Nema načina da lažeš a da te to ne košta. Sustav te **prisiljava da kažeš istinu**
o tome koliko ti nešto stvarno vrijedi. To je genijalno, i zato mehanizam ima
obožavatelje.

**Zašto smo ga ipak odbacili** — četiri razloga, svaki sam za sebe dovoljan:

| | |
|---|---|
| **Otimanje iz inata** | Konkurent ne želi tvoj trenutak. Želi da ga **ti nemaš**. Kupi ti ga na dan kad kampanja kreće i ostavi prazno. U Harbergeru ga ne možeš odbiti. Nijedna banka ne ulazi u sustav u kojem joj konkurencija može povući oglas kad hoće. |
| **Samoprocjena na plitkom tržištu je pogađanje** | Sam procijeniš vrijednost samo ako postoji tržište koje ti šapće koliko stvari vrijede. Kod nas ne postoji. Onda ne procjenjuješ nego se kockaš protiv protivnika. |
| **Stalni porez je knjigovodstvena mora** | Marketing ima stavku „sponzorstvo: 400 €". Nema stavku „400 € plus promjenjivi dnevni porez na samoprocijenjenu vrijednost koju revidiramo tjedno". |
| **Trajna nelagoda** | Nitko ne radi kreativu za mjesto koje može nestati za sat vremena. |

Provjerili smo i praksu: postoje stvarne izvedbe Harbergera (umjetnost, virtualna
zemljišta), ali **za oglasni prostor postoje samo hackathon projekti**. Nitko to
nije doveo do proizvoda.

### 1.3 Ljestvica otkupa — ono što smo izabrali

Tri pravila, i sva tri stanu u jednu rečenicu koju možeš izgovoriti kupcu:

> **Kupiš po cijeni. Od tog trena na tvom mjestu javno piše cijena po kojoj te
> netko može zamijeniti — a ona je uvijek 50 % viša od one koju si ti platio. I
> ako se netko javi, ti imaš tri dana da izjednačiš i ostaneš.**

Uz to dvije zaštite:

- **Prvih 30 dana te nitko ne može dirati.** Zajamčeni let. Bez toga nitko ne bi
  kupovao.
- **Tko te izbacuje mora unaprijed imati odobren oglas.** Ne isporuči li ga u
  sedam dana, mjesto ti se vraća, a njemu polog propada. Otimanje iz inata je
  time skupo i besmisleno.

**Razlika prema Harbergeru u jednoj rečenici**: kod Harbergera ti sam izmišljaš
cijenu i stalno plaćaš porez; kod ljestvice cijena **raste po pravilu**, plaćaš
jednom, i imaš pravo ostati.

---

## 2. Zašto je ispadanje **dobra vijest** — jedan primjer s brojkama

> Brojke su izmišljene radi računa. **Nisu cjenik.**

Kreator otvori trenutak od deset minuta u kojem se razgovara o tome kako mali
poduzetnik dolazi do kapitala, i stavi cijenu **400 €**.

**Prva prodaja.** Banka kupi za 400 €. Kreatoru ide **svih 400 €**. Platforma
uzima **0 €**.

**Prođe 45 dana.** Javi se fintech koji bi isti trenutak. Cijena mu je unaprijed
poznata i javna: **600 €** (400 × 1,5).

Banka dobiva tri dana da odluči.

**Ako banka izjednači** — plati 600 €, ostaje na mjestu, a nova cijena za sve
buduće izazivače postaje 900 €. Kreator dobije razliku umanjenu za naknadu
platforme: **170 €**. Ukupno je zaradio 570 € na istih deset minuta.

**Ako banka pusti** — fintech plati 600 €, i taj se novac razdijeli ovako:

| tko | koliko | zašto |
|---|---|---|
| **Banka** (koja ispada) | **450 €** | povrat svih 400 € + 50 € udjela u razlici |
| **Kreator** | **120 €** | 60 % razlike, povrh 400 € koje već ima → ukupno **520 €** |
| **domovina.ai** | **30 €** | 15 % razlike — **jedini novac koji platforma ikad vidi** |

Pogledaj redak s bankom još jednom. Banka je platila 400 €, dobila natrag 450 €,
**i uz to se 45 dana reklamirala**.

> **Rečenica koju pamtiš**: kod nas se oglašivač koji ispadne nije opekao — nego
> se reklamirao besplatno i još zaradio.

To je razlog zbog kojeg netko uopće smije biti prvi kupac. I to je razlog zbog
kojeg cijeli sustav ne zbraja na nulu.

---

## 3. Kreatoru podcasta

**Jedna rečenica:**

> Prodaješ deset minuta svoje epizode, dobiješ **cijeli iznos**, znaš tko ti je
> to platio, i ako ga poslije netko zamijeni — **naplatiš isti trenutak ponovo**.

**Što ga boli danas** (ne pretpostavljaj — pusti ga da to kaže sam, pa potvrdi):

- YouTube mu daje 55 % od onoga što je preostalo nakon što je posrednički lanac
  uzeo otprilike pola. Kraj tog računa nitko mu ne pokazuje.
- **Ne zna tko se na njemu oglašava.** Nema odnos ni s kim.
- **Ne može odbiti oglašivača.** Može isključiti grubu kategoriju, i to je sve.
- **Epizoda od prošle godine mu ne zarađuje ništa.** Mrtva je.

**Kako to okrenuti u 30 sekundi:**

> „Ti cijenu određuješ sam. Prvi put kad se netko javi, dobiješ **sve** — mi ne
> uzimamo ništa. Znaš mu ime i možeš ga odbiti ako ti se ne sviđa. A tvoje stare
> epizode nisu mrtve — one su zaliha. Kod nas je epizoda od prije godinu dana
> jednako kupljiva kao jučerašnja."

**Adut na kraju**, jer ovo drugdje ne postoji:

> „I ovo je čudno dok ne sjedne: **isti trenutak možeš naplatiti više puta.**
> Ako se za tvojih deset minuta poslije javi netko drugi, ti opet dobiješ svoj
> dio. Deset minuta koje si snimio jednom."

**Prigovori koje ćeš stvarno čuti:**

| on kaže | ti odgovaraš |
|---|---|
| „Imam premalo gledatelja da bi to itko kupio." | „Ne prodaješ gledatelje nego temu. Netko traži točno ono o čemu si pričao, i njemu je svejedno je li te čulo tisuću ili deset tisuća ljudi." |
| „Ne želim reklame u svojoj emisiji." | „Ništa ne prekida. Nema ni jedne sekunde reklame. Znak u kutu i redak u tekstu — ako ti se ne sviđa, ne otvaraš." |
| „Koliko to zapravo nosi?" | „**Pošteno: ne znam.** Nitko u Hrvatskoj to nije radio i podaci ne postoje. Zato prvi krug radimo na mom kanalu, s pravim novcem, i pokazat ću ti brojku kad je budem imao." |
| „A što ako mi netko otme sponzora?" | „Ne može ti ga otme — ti si kreator, ti si na dobitku u svakom slučaju. Otimanje se događa među oglašivačima, i svaki put kad se dogodi, **ti dobiješ još jednom.**" |

---

## 4. Slušatelju

**Jedna rečenica:**

> Nikad te nećemo prekinuti.

Ovdje ne treba prodavati. Treba **priznati** da oglasi postoje i objasniti zašto
su ovi drukčiji.

> „Da, ovo je plaćeno. Piše tko je platio i možeš to provjeriti jednim dodirom.
> Ali ništa se ne zaustavlja — nema reklame prije epizode, nema prekida u
> sredini, nema odbrojavanja do gumba 'preskoči'. Znak u kutu i jedan redak u
> tekstu. Ako te ne zanima, ne otvaraš ga i on nestane."

**Dodaj, jer je istina i jer se pamti:**

> „I ne pratimo tebe. Oglas je vezan za **temu o kojoj se govori**, ne za to tko
> si ti i što si prije gledao."

To nije marketing nego posljedica dizajna: prodajemo kontekst, pa nam profiliranje
nije ni potrebno.

**Ako netko pita „a mogu li to isključiti?"** — odgovor je pošten:

> „Ne. To je ono što plaća da epizoda postoji, a nikoga ne prekida. Ako te
> ikad prekine — javi mi, jer smo tada nešto pokvarili."

---

## 5. Brandu

**Jedna rečenica:**

> Ne kupujete publiku podcasta nego **onih deset minuta u kojima se govori točno
> o vama** — i imate transkript kao dokaz.

**Četiri stvari koje drugdje ne možete kupiti:**

1. **Trenutak koji se može imenovati.** Ne „podcast o poduzetništvu", nego
   „deset minuta o tome kako mali poduzetnik u Hrvatskoj dolazi do kapitala".
   Prije kupnje vidite izvadak iz transkripta.
2. **Placement koji ostaje.** Impresija nestane isti dan. Epizoda i njen članak
   se čitaju mjesecima poslije, a vaš znak ostaje na njima.
3. **Stare epizode.** Na svim ostalim platformama je sadržaj od prošle godine
   mrtav. Kod nas je kupljiv — a najbolji trenuci su često u epizodi koja je
   izašla davno.
4. **Zaštita od gubitka.** Ako vas netko poslije zamijeni, **dobijete natrag sve
   što ste platili plus udio u razlici.** Najgori ishod nije gubitak.

**Rečenica za kraj sastanka:**

> „Najgori ishod je da ste se reklamirali besplatno i još na tome zaradili."

**Prigovori:**

| on kaže | ti odgovaraš |
|---|---|
| „Koliko ljudi to vidi?" | „Manje nego na YouTubeu, i to vam neću ljepšati. Ali kupujete precizan kontekst i trajno mjesto, a ne prolazne prikaze. I danas je jeftino upravo zato što je rano." |
| „Kako znam da je isporučeno?" | „Mi crtamo taj znak u vlastitom playeru, pa broj prikaza ne procjenjujemo — **znamo ga**. Dobivate sirove brojke. I usput: ne naplaćujemo po prikazu, pa nemamo razloga napuhavati ga." |
| „Što ako se u epizodi kaže nešto što nam ne odgovara?" | „Zato svaki trenutak prije prodaje prolazi provjeru prikladnosti, a vi vidite transkript prije nego platite. Sadržaj vam ne prodajemo naslijepo." |
| „Zvuči komplicirano." | „Za vas su dvije odluke: koji trenutak i po kojoj cijeni. Sve ostalo se događa samo od sebe." |

---

## 6. Investitoru

Ovdje je najveći rizik da vas svrstaju u ladicu „NFT oglasi" i prestanu slušati.
Zato **vodi s podatkom, a ne s mehanizmom**, i sam iznesi loše vijesti.

**Jedna rečenica:**

> Nitko na tržištu ne prodaje **trenutak**, a mi na podlozi za to već sjedimo —
> 3.047 sati dijariziranih transkripata s temama i vremenskim sidrima.

**Redoslijed koji radi:**

1. **Rupa na tržištu, s dokazom.** Kontekstualni dobavljači (Sounder → Triton,
   Barometer → The Trade Desk) ocjenjuju **cijelu epizodu**. Alati za rezanje
   reklamnih pauza rade **detekciju tišine**. Presjek — semantički odabir točnog
   trenutka — **ne postoji ni kod koga**.
2. **Obrambeni jarak nije tržište nego pipeline.** Marketplace može svatko.
   Katalog obrađenih epizoda s vremenski usidrenim temama ne može — to je
   godina rada koja već stoji.
3. **Regulatorni vjetar u leđa.** DSA i privatnost ruše ciljanje po osobi. Mi ne
   ciljamo osobu nego sadržaj, pa nas ta struja **nosi umjesto da nas guši**.
4. **Model prihoda — bez uljepšavanja.** Naknada na preprodaji **nije plan
   prihoda**. NYIAX je s Nasdaqovom tehnologijom šest godina pokušavao pokrenuti
   trgovanje oglasnim ugovorima i nije uspio. Nula posto na primarnoj prodaji je
   **trošak stjecanja kreatora plaćen odricanjem od provizije** — to je razlog
   zbog kojeg kreator uopće dolazi.
5. **Što mjeriti** — ne promet. Mjeri **koliko je ponuđenih trenutaka prodano**
   i **koliko je otkupa izvršeno**. Otkup je jedini pošten pokazatelj da potražnja
   premašuje ponudu. Dok otkupa nema, sekundarnog tržišta nema, i to treba reći.

**Loše vijesti koje iznosiš sam** — ovo gradi povjerenje, ne ruši ga:

- Pilot-kanal ima **7 epizoda i 28 pratitelja**. Dokazuje mehanizam, ne potražnju.
- **Podaci o cijenama oglasa za Hrvatsku ne postoje javno.** Prvi cjenik je
  pogađanje.
- **Isplata kreatoru trenutno ne radi** za tuđe kanale — dio sustava je nedovršen.
- **Pet pravnih pitanja čeka odvjetnika** (MiCA, oznaka sponzora, PDV).
- **Tolerancija na sponzorski znak nije istražena** ni kod koga; YouTube je svoj
  overlay format ugasio 2023.

Zatvori time da si svaku od tih rupa **imenovao prije nego što ju je našao on**.

---

## 7. Što se NE smije reći

| zabranjeno | zašto |
|---|---|
| bilo koja cijena, CPM ili prihod kao činjenica | podaci za Hrvatsku ne postoje; sve brojke u §2 su ilustracija |
| „brandovi kao Lidl i IKEA su zainteresirani" | nitko od njih nije kontaktiran |
| „istraživanja pokazuju da slušatelji preferiraju ovaj format" | takvog istraživanja **nema** |
| „tokenizirano" / „na blockchainu" | faze 1–3 su namjerno bez toga; reći suprotno je neistina i otvara MiCA razgovor bez potrebe |
| „kreator zarađuje X puta više nego na YouTubeu" | usporedba postoji, ali za konkretan iznos nemamo pokriće |
| „platforma nikad ništa ne uzima" | uzima 15 % razlike pri otkupu — reci to sam, prije nego netko otkrije |
| bilo što o dosegu pilot-kanala što zvuči veće od „28 pratitelja" | provjerljivo u sekundi |

---

## 8. Ako imaš samo jednu rečenicu

| kome | rečenica |
|---|---|
| **kreatoru** | „Isti trenutak možeš naplatiti više puta, i prvi put dobivaš sve." |
| **slušatelju** | „Nikad te nećemo prekinuti." |
| **brandu** | „Najgori ishod je da ste se reklamirali besplatno i još zaradili." |
| **investitoru** | „Nitko ne prodaje trenutak, a mi na podlozi za to već sjedimo." |
