# frontend/ — the Flutter app

One codebase, phone and laptop. No separate web app: the layout switches at 720 px
(bottom navigation below it, a `NavigationRail` above it) and nothing else in the
app knows which form factor it is running in.

```
lib/
├── main.dart                  entry point: theme + SignInScreen
├── app/
│   ├── theme.dart             ★ Executive Precision, from ../../design/tokens.json
│   └── shell.dart             the responsive frame + navigation
├── core/
│   ├── api.dart               one HTTP client, resolves the base URL by platform
│   ├── models.dart            hand-written models; no code generation
│   ├── session.dart           who is signed in (no token, by design)
│   └── widgets.dart           AsyncBody, EmptyState, StatusChip, HashLabel, dates
└── features/
    ├── sign_in/               pick an identity — the prototype's honest login
    ├── home/                  every content item with its approval state
    ├── check/                 submit copy (pre-filled with the demo sentence)
    ├── findings/              ★ the product: spans, five statuses, three repairs
    ├── review/                the queue a reviewer can act on
    ├── audit/                 the append-only ledger, including SYSTEM voids
    └── guidelines/            every rule version and whether it is live today
```

## Two rules for this folder

1. **No colour literals outside `app/theme.dart`.** Every colour comes from
   `design/tokens.json`, via `Bg`. If a new colour is needed it is added there first.
2. **No number on screen that does not come from an API field.** If there is no field,
   render a dash or an empty state. This is the rule that keeps the app honest.

## One dependency

`http`. That is the whole list. State management is a `ChangeNotifier` with a single
global session; routing is `Navigator`; models are hand-written. Every package added is
a build that can fail on a machine this project does not control.

## Run

```bash
flutter pub get
flutter run -d chrome                       # fastest
flutter run                                 # an emulator or a plugged-in phone
flutter run --dart-define=API_BASE=http://192.168.1.20:8000   # a real phone
```

An Android emulator needs no configuration: `core/api.dart` resolves `10.0.2.2`
automatically, because that is the address of the host machine from inside the emulator
and `localhost` never is.

The `android/` and `web/` folders are generated scaffolding (`flutter create`), committed
so a clone runs without an extra step. `lib/` is never generated.

## Test

```bash
flutter analyze      # must be clean
flutter test         # asserts the status vocabulary and which statuses block approval
```
