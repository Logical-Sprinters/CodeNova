# design/

`tokens.json` is the whole design system: Executive Precision.

| Group | Values |
|---|---|
| colour | navy `#142C3B` primary, teal `#22A895` accent, deep teal `#177F73`, ink `#20313A`, surface `#F7F9FA` |
| status | the five finding colours, plus approved `#1E7B4F` and void `#8A94A0` |
| type | Manrope, one family, five sizes |
| space | 4 / 8 / 16 / 24 / 32 |
| shape | 12 px radius, 14 px cards, **52 px touch target** |
| layout | rail breakpoint 720 px, max content width 900 px |

`frontend/lib/app/theme.dart` mirrors this file. The mirroring is manual and deliberate:
one JSON file that nothing reads is documentation, not a system, and a build step that
generates Dart would be a second thing that can fail.

**The rule:** no colour literal outside `theme.dart`. If a colour is needed somewhere else,
it is added here first and then there.

`assets/fonts/Manrope-Variable.ttf` is bundled rather than fetched at runtime. A font fetch
is a blank-looking screen on conference wifi, and a brand-governance tool that renders in the
wrong typeface is a disappointing joke.
