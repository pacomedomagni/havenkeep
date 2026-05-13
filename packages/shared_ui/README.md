# HavenKeep design system

The shared UI primitives + tokens that every screen in the mobile app
builds from. The design language is **dark indigo / violet on near-black
with gold accent**, calibrated against the Cron / Notion Calendar
visual aesthetic — sharp depth, glass-like layering, software-craftsman
restraint.

This package is the **single source of truth**. If you can't build
something with the primitives below, *add a primitive here first* — do
not hand-roll one in the feature.

---

## Tokens

All tokens live in [`lib/src/theme.dart`](lib/src/theme.dart):

| Class             | What it is                                                              |
|-------------------|--------------------------------------------------------------------------|
| `HavenColors`     | Surface ladder (4 tiers), accents (indigo/violet/gold), status, text.   |
| `HavenSpacing`    | 4 / 8 / 16 / 24 / 32 / 48 px grid. Always use these, never literals.    |
| `HavenRadius`     | `pill` 8 · `input` 10 · `button` 12 · `card` 16 · `chip` 20 · `micro` 4. |
| `HavenElevation`  | `shadowFor(level)` · `sheen()` · `glow(color)`.                          |
| `HavenGradients`  | `brand` · `brandSoft` · `brandVertical`.                                 |
| `HavenIconSize`   | 16 / 20 / 24 / 32 px.                                                    |
| `HavenText`       | Named text roles: `hero` `stat` `displayLarge/Medium` `titleLarge/Medium` `body` `bodySecondary` `meta` `caption` `overline` `badge`. |
| `HavenMotion`     | `fast` 180 · `medium` 240 · `slow` 320 · `celebration` 640 ms. Curves.   |
| `HavenTheme.dark` | The `ThemeData` consumed by `MaterialApp(theme:)`.                       |

---

## Primitives

Every primitive uses the tokens above and shares the same press feedback,
haptics, and motion vocabulary.

### Layout

| Widget                  | Use for                                                                   |
|-------------------------|---------------------------------------------------------------------------|
| `HavenCard`             | Any surface that's visually elevated. Variants: `.surface`, `.elevated`, `.flat`, `.highlight`. Built-in press scale + ripple. |
| `HavenListItem`         | List rows (items, claims, gifts, notifications). Slots: leading, title, subtitle, supplementary, trailing, accent stripe. `entryIndex:` adds a 40 ms staggered entrance. |
| `HavenAppBar`           | Standard top bar. `.large()` variant for tab-root screens.                |
| `HavenSheet`            | Bottom sheet for ephemeral menu choices (sort, theme picker, etc.). Pushed routes are for screens with depth. |
| `SectionHeader`         | Section labels. Default = small-caps; `.display()` = big title + subtitle. |
| `HavenAccordion`        | Collapsible inline section.                                                |

### Inputs

| Widget                       | Use for                                                |
|------------------------------|---------------------------------------------------------|
| `HavenButton`                | Every button. Variants: `primary`, `secondary`, `tertiary`, `destructive`, `ghost`. Sizes: `sm`, `md`, `lg`. |
| `BrandAutocompleteField`     | Brand-name input with autocomplete suggestions.        |
| `RoomPicker`                 | Pick a `ItemRoom`.                                     |
| `WarrantyDurationPicker`     | Pick warranty length in months.                        |

### Feedback

| Widget                  | Use for                                                                |
|-------------------------|--------------------------------------------------------------------------|
| `HavenSuccessFlourish`  | The success moment — gold disc + checkmark draw-in + halo + haptic. Use on item-added, gift-activated, premium-upgrade, claim-filed screens. |
| `HavenSnackbar`         | Transient toast. `showHavenSnackBar(context, message: ...)`.            |
| `HavenSkeleton`         | `SkeletonLine`, `SkeletonBox`, `SkeletonCard` for loading placeholders. |
| `HavenEmptyState`       | Empty-state surface. Icon + title + body + optional CTAs. Animates in.  |
| `HavenStatRing`         | Animated progress ring (warranty health %).                              |
| `WarrantyStatusBadge`   | Pill badge for `WarrantyStatus`.                                         |
| `ItemLimitBanner`       | Free-plan limit nudge.                                                   |
| `showHavenConfirmDialog`| Branded confirmation prompt.                                             |

### Behavior

| Helper             | Purpose                                                                |
|--------------------|--------------------------------------------------------------------------|
| `HavenHaptics`     | One taxonomy: `tap`, `select`, `confirm`, `celebrate`, `warn`. Use these instead of raw `HapticFeedback`. |
| `HavenHeroTag`     | Canonical hero-tag generators (`item(id)`, `claim(id)`, `gift(id)`, `stat(name)`) so hero animations don't silently break. |

---

## Rules

**Five forbidden patterns** in feature code (enforced by
[`apps/mobile/scripts/lint-design.sh`](../../apps/mobile/scripts/lint-design.sh)
on every commit):

1. **No inline `TextStyle(fontSize: …)`** — use `HavenText.*` roles.
2. **No hex `Color(0xFF…)`** in features — use `HavenColors.*` tokens. New colors must be added to `theme.dart` first.
3. **No raw `ElevatedButton` / `FilledButton` / `OutlinedButton`** — use `HavenButton`. Material's `TextButton` is allowed in narrow cases (legacy widget overlays), but prefer `HavenButton.tertiary`.
4. **No `fullscreenDialog: true`** routes — use a pushed route so iOS swipe-back / Android predictive-back work.
5. **No raw `showModalBottomSheet`** — use `HavenSheet.show()`. The one exception is `log_maintenance_screen` which needs `DraggableScrollableSheet` for a multi-field form sheet.

If a violation is genuinely unavoidable, add
`// design-lint-ignore-next-line` on the line before, with a comment
explaining why.

To see all outstanding violations across the codebase (audit mode):

```sh
bash apps/mobile/scripts/lint-design.sh --full
```

That output is the running Phase 1.5 punch list — when you're touching a
file with violations, migrate them as part of your change instead of
leaving them.

---

## How to add a new primitive

Discover a missing primitive? Don't hand-roll it in a feature — add it
here:

1. Create `lib/src/haven_<name>.dart`.
2. Use only tokens from `theme.dart`; no new hardcoded colors / spacing.
3. Document the use case in the file's class doc (1–3 paragraphs).
4. Export it from `lib/shared_ui.dart`.
5. Run `dart analyze` from the package directory — must be clean.
6. Update this README's primitive table.
