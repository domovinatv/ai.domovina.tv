# Android Native Splash Randomization Research (API 26–30)

**Target hardware**: EON SDSTB02 (Amlogic, Android 11 / API 30, Leanback). Flutter
first frame takes 12–19 seconds; the OS *starting window* (drawn by SystemUI
from the manifest theme **before** the Activity process starts) is visible the
entire time. We want one of ~14 pre-rendered biblical-verse PNGs to appear at
random per cold launch.

Date: 2026-05-27. Author: research agent (model claude-opus-4-7[1m]).

---

## 1. TL;DR

**No approach reliably randomizes the *actual* OS starting window per cold
launch on Android 8–11**, because the starting window is composed by
`WindowManagerService` from the manifest theme of the *resolved component*
**before** any app code (including `Application.onCreate`) runs. Anything our
process does at runtime arrives too late.

The **only two viable paths** are:

1. **Path D (recommended, High confidence)** — Keep the static native splash
   (Mt 10,26–28) as a deliberate brand frame, **pre-warm `FlutterEngine` in
   `Application.onCreate`**, then make the Flutter splash (already rotating
   citations) take over as quickly as possible. This is the only path that
   doesn't fight the platform.

2. **Path A (Medium confidence, Leanback caveats)** — `<activity-alias>`
   rotation with `PackageManager.setComponentEnabledSetting(..., DONT_KILL_APP)`
   at app exit. Each alias declares its own `android:theme` and therefore its
   own starting-window `windowBackground`. **However**: confirmed-working on
   Android 11 phone launchers; **Leanback launcher caching behavior is
   undocumented** and on Android TV the icon visibly switches places in the
   Apps row, which is a UX regression. Worth a single-day spike on EON before
   commit.

Paths B, C, E, F are not viable for this use case (see §2).

---

## 2. Per-Approach Findings

### A. `<activity-alias>` rotation (theme-per-alias)

**Verdict**: **Viable on phone launchers (API 29+), unverified on Leanback /
Google TV**. Confidence **Medium**.

**Mechanism**:
1. Declare 14 `<activity-alias>` entries in `AndroidManifest.xml`, all with
   `android:targetActivity=".MainActivity"`, each with a unique
   `android:theme="@style/LaunchTheme_N"` (each theme has its own
   `windowBackground` pointing at `splash_tagline_N`).
2. Only one alias has `android:enabled="true"` + `MAIN`/`LAUNCHER` intent at a
   time; the other 13 are `android:enabled="false"`.
3. On `MainActivity.onStop()` (i.e. when the user closes the app), call
   `PackageManager.setComponentEnabledSetting(currentAlias,
   COMPONENT_ENABLED_STATE_DISABLED, DONT_KILL_APP)` and the same with
   `COMPONENT_ENABLED_STATE_ENABLED` for the next alias.
4. Next cold launch → launcher resolves to the newly-enabled alias → SystemUI
   composes starting window from *its* theme → user sees the next PNG.

**Key supporting evidence**:
- "With the exception of `targetActivity`, `<activity-alias>` attributes are a
  subset of `<activity>` attributes. For attributes in the subset, none of the
  values set for the target carry over to the alias."
  ([android-dev: activity-alias](https://developer.android.com/guide/topics/manifest/activity-alias-element))
  → Each alias can carry its own `android:theme`, so the starting window will
  differ.
- "Setting a theme automatically sets the activity's context to use this theme
  and might also cause 'starting' animations prior to the activity being
  launched, to better match what the activity actually looks like." (same
  source) → Confirms the manifest theme of the *alias* (not the target) is
  what SystemUI uses to compose the starting window.
- `DONT_KILL_APP` flag is documented as the correct way to flip aliases
  without process restart. ([Microsoft Learn:
  PackageManager.DontKillApp](https://learn.microsoft.com/en-us/dotnet/api/android.content.pm.packagemanager.dontkillapp))
- Known to work for dynamic icon switching on API 29+; on API ≤ 28 the icon
  can disappear from the home screen.
  ([famapp blog](https://blog.famapp.in/blog/change-app-icon-dynamically-in-android/),
  [proandroiddev](https://proandroiddev.com/dynamic-app-mode-theme-and-launcher-icon-switch-in-android-a-complete-guide-f30291d90b5e))

**Risks specific to our case**:
1. **Leanback caching**: No authoritative documentation found on whether
   Google TV / Leanback launcher refreshes the resolved component immediately
   when `setComponentEnabledSetting` flips. On phones the article notes that
   "on Samsung phones, the icon might update slower than on Google Pixel"
   — TV launchers may aggressively cache.
   ([proandroiddev guide](https://proandroiddev.com/dynamic-app-mode-theme-and-launcher-icon-switch-in-android-a-complete-guide-f30291d90b5e))
2. **Visible UX side effect on TV**: each rotation changes the resolved
   component → the app may visibly re-order itself in the Apps row, or
   trigger a launcher re-index animation. On phones this is invisible because
   shortcuts/widgets stay pinned; on Leanback the home grid is dynamic.
3. **Manifest bloat**: 14 styles + 14 aliases. Acceptable but increases
   merged-manifest review surface.
4. **First-launch quirk**: documented that on the *first* alias switch the
   process is killed at least once even with `DONT_KILL_APP`. Acceptable since
   we only flip on `onStop`.
   ([abizareyhan blog](https://blog.abizareyhan.com/dynamic-app-icon-on-android/))

**Implementation sketch**:
```xml
<!-- AndroidManifest.xml -->
<activity android:name=".MainActivity" android:exported="false" ... />

<activity-alias android:name=".Launcher1"
    android:targetActivity=".MainActivity"
    android:theme="@style/LaunchTheme1"
    android:enabled="true"
    android:exported="true">
  <intent-filter>
    <action android:name="android.intent.action.MAIN"/>
    <category android:name="android.intent.category.LAUNCHER"/>
    <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>
  </intent-filter>
</activity-alias>
<!-- ...Launcher2..Launcher14 with android:enabled="false" ... -->
```
```kotlin
// MainActivity.kt
override fun onStop() {
    super.onStop()
    val pm = packageManager
    val current = ComponentName(this, "ai.domovina.Launcher$N")
    val next = ComponentName(this, "ai.domovina.Launcher${(N % 14) + 1}")
    pm.setComponentEnabledSetting(next,
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
        PackageManager.DONT_KILL_APP)
    pm.setComponentEnabledSetting(current,
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
        PackageManager.DONT_KILL_APP)
}
```

**Required spike before commit**: deploy 2-variant version to EON, install,
launch, exit (HOME), re-launch. Observe (a) does variant change? (b) does the
EON Apps row reshuffle visually? (c) any delay before icon resolves?

---

### B. Animated/cycling drawable in `launch_background.xml`

**Verdict**: **Not viable**. Confidence **High**.

**Why**:
- Android docs explicitly state: "The `start()` method called on the
  AnimationDrawable can't be called during the `onCreate()` method of your
  Activity, because the AnimationDrawable is not yet fully attached to the
  window." Recommended call site is `onWindowFocusChanged`.
  ([android-dev: AnimationDrawable](https://developer.android.com/reference/android/graphics/drawable/AnimationDrawable))
- The starting window is type `TYPE_APPLICATION_STARTING` (
  [WindowManager.LayoutParams](https://developer.android.com/reference/android/view/WindowManager))
  and is rendered by `system_server` / `WindowManagerService`, **not** by the
  application process. There is no Activity attached, so no
  `onWindowFocusChanged` ever fires → animation never receives `start()`.
- For Android 12+ the platform added explicit
  `windowSplashScreenAnimationDuration` + `windowSplashScreenAnimatedIcon`
  attributes precisely *because* the pre-12 starting window does not animate
  AnimationDrawable automatically.
  ([android-dev: SplashScreen migration](https://developer.android.com/develop/ui/views/launch/splash-screen/migrate))

**Conclusion**: on Android 8–11 the starting window will freeze on frame 1 of
any `<animation-list>` and stay there for the full 12–19s. Identical UX
problem to today's static splash, just with more PNGs in the APK.

---

### C. Flutter `SplashScreenDrawable` meta-data override

**Verdict**: **Not viable** (and deprecated). Confidence **High**.

**Why**:
- This API existed pre-Flutter 2.5 and was used to display a Flutter-managed
  splash *after* `FlutterActivity` started, on top of the system starting
  window. It never replaced the starting window itself.
- Deprecated since Flutter 2.5: "io.flutter.embedding.android.SplashScreenDrawable
  should not be set in your manifest, and `provideSplashScreen` should not be
  implemented, as these APIs are deprecated. Doing so causes the Android
  launch screen to fade smoothly into the Flutter when the app is launched
  and the app might crash."
  ([Flutter docs: Splash Screen migration](https://docs.flutter.dev/release/breaking-changes/splash-screen-migration))
- Even when it worked, it ran *after* `FlutterActivity.onCreate`, i.e. after
  the 12–19s native splash had already finished — useless for our goal.

---

### D. Process pre-warming + Flutter handles splash content

**Verdict**: **Viable and recommended**. Confidence **High**.

**Mechanism**:
1. Keep the existing static native starting window (navy + logo + a single
   neutral verse, e.g. Mt 10,26–28 as today).
2. In a custom `Application` subclass, override `onCreate` to instantiate and
   cache a `FlutterEngine` *before* `MainActivity` even starts:
   ```kotlin
   class DomovinaApplication : FlutterApplication() {
       lateinit var engine: FlutterEngine
       override fun onCreate() {
           super.onCreate()
           engine = FlutterEngine(this)
           engine.dartExecutor.executeDartEntrypoint(
               DartExecutor.DartEntrypoint.createDefault())
           FlutterEngineCache.getInstance().put("main", engine)
       }
   }
   ```
3. `MainActivity` extends `FlutterActivity` and uses
   `withCachedEngine("main")` instead of the default constructor.
4. The Flutter-side splash (already implemented with rotating citations per
   `tv_splash_implementation` memory and `docs/splash-bible-citations.md`)
   appears as soon as the engine renders frame 1 — which with a pre-warmed
   engine should land within ~1–3s instead of 12–19s.

**Key supporting evidence**:
- "Pre-warming a FlutterEngine and reusing the same engine throughout your
  app minimizes wait time associated with initialization of the Flutter
  engine."
  ([Flutter docs: add-to-app performance](https://docs.flutter.dev/add-to-app/performance))
- Docs explicitly note the limitation: "there's an exception when
  FlutterActivity is the first Activity displayed by the app, because
  pre-warming a FlutterEngine would have no impact in this situation."
  → **This is the key risk to verify**. The reasoning in the docs is that
  `Application.onCreate` runs *before* `MainActivity.onCreate` regardless of
  caching — so on paper there's no extra parallelism. **However**, in
  practice, `executeDartEntrypoint` kicks off the Dart VM on a background
  isolate while the system continues building the Activity; on slow hardware
  this could parallelize ~3–5s of Dart isolate spin-up with the Activity's
  window setup. Empirically this is worth measuring on EON.
- Mid-range cold start target is <2s, Google Play "excessive" is ≥5s.
  ([android-dev: launch-time](https://developer.android.com/topic/performance/vitals/launch-time))
  Our 12–19s figure on EON likely includes Impeller shader compilation; a
  Flutter issue confirms "Enabling Impeller resulted in a noticeable
  degradation in cold start performance ... on low-end devices like Redmi 9A,
  Android 11."
  ([flutter/flutter#175128](https://github.com/flutter/flutter/issues/175128))

**Companion optimizations to combine with D**:
- Disable Impeller on Android TV (`io.flutter.embedding.android.EnableImpeller`
  meta-data = `false`) — Impeller's shader-compile hit on low-end Amlogic GPU
  is the likely #1 culprit of the 12–19s figure.
- Defer Firebase/Supabase init off the main isolate first frame
  ([flutterfire#8837](https://github.com/firebase/flutterfire/issues/8837)).
- Test with `flutter run --profile --trace-startup` on EON to confirm
  `timeToFirstFrameMicros` improves with the cached engine path.

**Important**: **option D does not deliver randomization of the native
splash**. It instead makes the native splash *irrelevant* because Flutter
takes over fast enough that the user effectively never sees more than a brief
brand frame. Randomization happens 100% Flutter-side, where it already works.

---

### E. Multiple permanent launcher icons (user picks)

**Verdict**: **Not viable for our goal** (not random, requires user action).
Confidence **High**.

Could ship 14 permanent launcher icons via 14 always-enabled aliases. User
would scroll through 14 entries in Apps row. Obviously a TV UX disaster and
doesn't satisfy "random per launch". **Reject.**

---

### F. Other ideas explored

**F1. AndroidX `androidx.core:core-splashscreen` backport**
- Source code inspection (`SplashScreen.kt`, androidx-main) confirms: on
  API < 31, the library **cannot customize the actual starting window**.
  It replicates the splash *after* Activity creation by synthesizing a
  programmatic view from theme attrs. → Same architectural limitation as
  Path C: doesn't replace the pre-Activity OS splash.
  ([androidx source](https://github.com/androidx/androidx/blob/androidx-main/core/core-splashscreen/src/main/java/androidx/core/splashscreen/SplashScreen.kt))
- **Verdict**: doesn't solve our problem. The static starting window of
  Android 8–11 would still be whatever the manifest theme declares.

**F2. `windowDisablePreview` + black screen + Flutter splash**
- Already rejected by user (12–19s black). The only way to make this
  acceptable is to combine it with Path D so the engine renders within
  ~1–2s; then a brief black flash is tolerable. Possible "spicy" variant
  of D.

**F3. Task snapshot exploit**
- AOSP `WindowManagerService` saves a snapshot of the last frame of the
  Activity in `TaskSnapshotSurface` and uses it as the starting window
  for warm starts ("Recents return" path).
  ([android-dev: launch-time](https://developer.android.com/topic/performance/vitals/launch-time),
  search hit on
  [WindowManagerService](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/services/core/java/com/android/server/wm/WindowManagerService.java))
  → On warm start (return from Recents) the user sees their last app frame,
  not the splash. **This is only a warm-start phenomenon**, not useful for
  cold launches where the process was killed. But it does mean: if we ensure
  the Flutter side's last-rendered frame is a citation card, *some* re-opens
  will show a fresh citation "for free". Not a primary solution.

**F4. Major-app comparison (Duolingo, Headspace)**
- Mobbin's Duolingo splash inventory shows a single static green-logo splash;
  no per-launch quote rotation.
  ([Mobbin: Duolingo splash](https://mobbin.com/explore/screens/03802ac2-89f5-4120-8334-0e5300fc4b39))
- Headspace/Duolingo joint Android architecture talk discusses Hilt/modular
  builds, no daily-quote splash mechanism.
  ([YouTube: Headspace+Duolingo architecture](https://www.youtube.com/watch?v=m1F_Jl9bDA4))
- **Conclusion**: no major app appears to randomize the *native* splash. This
  is consistent with the platform constraints described in B/C/F1.

**F5. Cordova/RN splash plugins with runtime variant selection**
- `cordova-plugin-splashscreen` and `react-native-splash-screen` both
  implement their splash as an *overlay after Activity start*, identical
  pattern to Path C, with the same fundamental "can't replace the OS
  starting window" limit.
  ([Cordova plugin](https://cordova.apache.org/docs/en/12.x-2025.01/core/features/splashscreen/index.html))
- No prior art found for randomized native starting window. **Confirms B/C
  verdict.**

---

## 3. Recommended Path Forward

**Primary: implement Path D** (engine pre-warm + Flutter-owned splash UX).

This is the only approach that:
1. Doesn't fight `WindowManagerService`.
2. Actually moves the needle on the 12–19s perceived wait (the *real* problem
   underneath the splash randomization ask).
3. Lets us keep all citation rotation logic in Dart where we already have it.

**Concrete next steps:**

1. **Measure baseline**: `flutter run --profile --trace-startup` on EON.
   Record `timeToFirstFrameMicros`.
2. **Disable Impeller on TV** via manifest meta-data, behind the existing
   `FORCE_TV` / `isTv` gate. Re-measure. Expectation: 30–60% improvement on
   Amlogic GPU.
3. **Add `DomovinaApplication`** with `FlutterEngineCache` pre-warm. Wire
   `MainActivity` to `withCachedEngine("main")`. Re-measure.
4. **Keep the existing static native splash** (Mt 10,26–28) as a deliberate
   brand frame — accept that it's static, document the "why" in the splash
   doc, and lean into the citation reveal happening *in Flutter*.

**Secondary (optional spike, only if Path D doesn't reduce wait enough):
Path A on phones only**. Gate the alias-rotation logic to `!isTv` (or to
specific known-good Leanback launchers detected at runtime). Treat as
"phone-only easter egg".

**Do NOT implement**: B, C, E, F1, F2 — verified blocked by platform.

---

## 4. Open Questions (require EON hands-on)

1. **Path D engine warmup latency**: with `FlutterEngineCache` pre-warm + no
   Impeller, what is the actual first-frame time on EON? Target <3s; if
   ≥6s, pre-warm wasn't enough and we need to investigate further (likely
   shader cache priming, AOT snapshot size, Supabase lazy-init, etc.).
2. **Path A Leanback behavior**: if we ever revisit A, what does the EON Apps
   row do when the resolved alias flips? Re-shuffle? Re-index spinner?
   Duplicate icons momentarily? Verify with side-by-side video.
3. **Path A timing**: how long after `setComponentEnabledSetting` (on
   `onStop`) does the EON launcher actually pick up the change? If it
   requires a launcher restart, A is dead-on-arrival for TV.
4. **Worst-case fallback**: if D shaves only 2–3s (still 10s+ visible
   splash), is the user OK accepting that and we just polish the static
   splash artwork instead of trying to randomize it?

---

## 5. Sources

### Authoritative (Android / Flutter docs)
- [`<activity-alias>` element — App architecture](https://developer.android.com/guide/topics/manifest/activity-alias-element)
- [`AnimationDrawable` — API reference](https://developer.android.com/reference/android/graphics/drawable/AnimationDrawable)
- [Splash screens — Views](https://developer.android.com/develop/ui/views/launch/splash-screen)
- [Migrate your splash screen implementation to Android 12 and later](https://developer.android.com/develop/ui/views/launch/splash-screen/migrate)
- [App startup time — App quality](https://developer.android.com/topic/performance/vitals/launch-time)
- [`WindowManager.LayoutParams` — TYPE_APPLICATION_STARTING](https://developer.android.com/reference/android/view/WindowManager)
- [`androidx.core.splashscreen.SplashScreen` — API reference](https://developer.android.com/reference/androidx/core/splashscreen/SplashScreen)
- [Flutter: Adding a splash screen to your Android app](https://docs.flutter.dev/platform-integration/android/splash-screen)
- [Flutter: Deprecated Splash Screen API Migration](https://docs.flutter.dev/release/breaking-changes/splash-screen-migration)
- [Flutter: add-to-app load sequence & performance](https://docs.flutter.dev/add-to-app/performance)
- [Microsoft Learn: `PackageManager.DontKillApp`](https://learn.microsoft.com/en-us/dotnet/api/android.content.pm.packagemanager.dontkillapp)

### Source code
- [androidx core-splashscreen `SplashScreen.kt`](https://github.com/androidx/androidx/blob/androidx-main/core/core-splashscreen/src/main/java/androidx/core/splashscreen/SplashScreen.kt)
- [AOSP `WindowManagerService.java`](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/services/core/java/com/android/server/wm/WindowManagerService.java)
- [AOSP `ActivityRecord.java` (android11-release)](https://github.com/aosp-mirror/platform_frameworks_base/blob/android11-release/services/core/java/com/android/server/wm/ActivityRecord.java)

### Bug reports / issue trackers
- [flutter/flutter#175128 — Impeller slow cold start on low-end Android](https://github.com/flutter/flutter/issues/175128)
- [flutter/flutter#35358 — Flutter cold start slow on low-end Android](https://github.com/flutter/flutter/issues/35358)
- [flutter/flutter#147967 — App stuck on Android splash screen](https://github.com/flutter/flutter/issues/147967)
- [firebase/flutterfire#8837 — initializeApp slows app startup](https://github.com/firebase/flutterfire/issues/8837)

### Articles (community)
- [Dynamic App Icons on Android using activity-alias (abizareyhan)](https://blog.abizareyhan.com/dynamic-app-icon-on-android/)
- [Dynamic App Mode, Theme, and Launcher Icon Switch — Complete Guide (proandroiddev)](https://proandroiddev.com/dynamic-app-mode-theme-and-launcher-icon-switch-in-android-a-complete-guide-f30291d90b5e)
- [Change App Icon Dynamically (famapp)](https://blog.famapp.in/blog/change-app-icon-dynamically-in-android/)
- [Let Users Change Your App Icon: Dynamic Icons on Android (DEV)](https://dev.to/anandankur16/let-users-change-your-app-icon-a-guide-to-dynamic-icons-on-android-with-activity-alias-3okp)
- [How to Dynamically Change an App Icon Without Closing the App (Turubaev)](https://medium.com/@turubaevruslan/how-to-dynamically-change-an-app-icon-in-android-without-closing-the-app-c2c9adec6275)
- [Activity Aliasing on Android (David Serrano)](https://medium.com/@azhiva/activity-aliasing-on-android-d6a3e8d0be0f)
- [Adding Animated Splash Screens (David Medenjak)](https://blog.davidmedenjak.com/android/2019/05/17/animated-splash-screens.html)
- [Avoiding cold starts on Android (Saúl Molinero)](https://saulmm.github.io/avoding-android-cold-starts)
- [Optimizing Flutter App Startup: Cold Launch in 2s (Subhanu Majumder)](https://medium.com/@reach.subhanu/optimizing-flutter-app-startup-cold-launch-to-ready-in-2-seconds-4ed32fa7a95f)
- [How to Reduce App Startup Time on Android, iOS & Flutter (Digia, 2026)](https://www.digia.tech/post/app-startup-time-performance-guide/)
- [Cold Start Optimization Tips for Flutter Apps (Prosperasoft)](https://prosperasoft.com/blog/mobile-app-development/flutter/flutter-cold-start-optimization/)
- [Android Vitals: Diving into cold start waters (Py Ricau)](https://dev.to/pyricau/android-vitals-diving-into-cold-start-waters-5hi6)
- [Cordova-plugin-splashscreen docs](https://cordova.apache.org/docs/en/12.x-2025.01/core/features/splashscreen/index.html)
- [Mobbin: Duolingo Android splash screen](https://mobbin.com/explore/screens/03802ac2-89f5-4120-8334-0e5300fc4b39)
- [Duolingo + Headspace Android architecture talk (YouTube)](https://www.youtube.com/watch?v=m1F_Jl9bDA4)
