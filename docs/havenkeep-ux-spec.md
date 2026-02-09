# HavenKeep — Complete UI/UX Specification (v6)

> **Changes from v5:** Switched tech stack from React Native + Expo to
> **Flutter + Dart + Supabase**. Added full Tech Stack section with Flutter
> packages table. Updated typography to Inter via `google_fonts`. Updated
> Offline Mode with `drift` (SQLite) + `connectivity_plus` implementation
> notes. Updated Platform Notes with Flutter-specific APIs. Also: aligned
> Quick-Add form with bulk-add (3 fields, not 4 — Room auto-assigned from
> category defaults). Redesigned Item Detail screen with collapsible accordion
> sections to reduce scroll fatigue.
>
> **Changes from v4:** Conditional coverage stat (only shows dollar amount
> when 50%+ items have price data, otherwise shows "12 active warranties").
> Added Home Detail screen (7.3) and Archived Items screen (7.4). Added
> chevron + Details link on Needs Attention cards. Added Permission Requests
> section (camera, notifications, location timing). Dashboard summary counts
> are tappable (pre-filter Items tab). Moved Invite Friends to v2+ deferred.
> Spec'd "+ Add Other Item" inline behavior in bulk-add. Added receipt
> multi-item picker note. Added Form Validation section.

---

## Brand Identity

### Visual Direction: Dark & Premium
- **Primary Background:** #0A0E1A (deep dark navy/charcoal)
- **Card/Surface:** #141929 (slightly lighter navy)
- **Elevated Surface:** #1C2237 (cards, modals, bottom sheets)
- **Primary Accent:** #2563EB (bright royal blue — buttons, CTAs, active states)
- **Secondary Accent:** #60A5FA (lighter blue — links, secondary actions)
- **Success/Active:** #10B981 (emerald green — active warranties)
- **Warning/Expiring:** #F59E0B (amber — expiring soon)
- **Danger/Expired:** #EF4444 (red — expired warranties)
- **Text Primary:** #F1F5F9 (near white)
- **Text Secondary:** #94A3B8 (muted slate)
- **Text Tertiary:** #64748B (subtle labels)
- **Border/Divider:** #1E293B (subtle separation)

### Typography
- **Headings:** Inter Bold — 700 weight (via `google_fonts` package, renders natively on both platforms)
- **Body:** Inter Regular — 400 weight
- **Numbers/Data:** Inter Tabular / JetBrains Mono — for dates, countdowns, prices
- **Implementation:** `google_fonts` package with `ThemeData.textTheme` — single definition, both platforms

### Iconography
- Outlined icons, 1.5px stroke weight
- Phosphor Icons or Lucide Icons (consistent, premium feel)
- 24px standard, 20px compact, 32px feature icons

### Spacing System
- Base unit: 4px
- xs: 4px | sm: 8px | md: 16px | lg: 24px | xl: 32px | 2xl: 48px

### Border Radius
- Cards: 16px
- Buttons: 12px
- Input fields: 10px
- Chips/Tags: 20px (pill shaped)
- Avatars/Icons: 50% (circle)

---

## Navigation Architecture

### Bottom Tab Bar (2 tabs + FAB)
```
┌────────────┬──────┬────────────┐
│  🏠 Home    │ [+]  │  📦 Items   │
│            │(FAB) │            │
└────────────┴──────┴────────────┘
```

**Two tabs only:**
1. **Home** — Dashboard overview, warranty summary, needs attention (max 3), tips
2. **Items** — Full list of all tracked items, search, status filter chips

**No Profile tab.** Settings/Profile accessed via gear icon (⚙️) in the
top-right corner of the Home screen header.

**Why 2 tabs, not 3:**
- Home and Items have distinct purposes: glance vs manage
- Profile/Settings is visited rarely — doesn't deserve equal tab billing
- 2 tabs + centered FAB creates a balanced, unambiguous layout
- The FAB is clearly not a tab — it sits between two real tabs

### Floating Action Button (FAB)
- Center-bottom, overlapping the tab bar slightly
- "+" icon → opens "Add Item" bottom sheet
- Primary blue (#2563EB) with subtle glow/shadow
- Available from both Home and Items tabs

### Alert Handling (No Bell Icon, No Notification Inbox)
- "Needs Attention" section on Dashboard handles in-app alerts
- Push notifications are the primary alert mechanism
- Tapping a push notification → goes directly to the relevant Item Detail screen
- No notification bell, no notification inbox screen for v1
- Rationale: push + dashboard "Needs Attention" covers the use case.
  A notification inbox is maintenance overhead with minimal value for v1.

---

## Screen-by-Screen Design

---

### FLOW 1: ONBOARDING (3 screens to first value)

The goal: get the user from open → adding items in under 60 seconds.
Attribution (referral codes) is handled via deep links, not manual entry.

---

#### Screen 1.1: Splash / Loading
```
┌─────────────────────────────┐
│                             │
│                             │
│                             │
│         [HavenKeep          │
│          Logo Icon]         │
│                             │
│         HavenKeep           │
│  Your Warranties. Protected.│
│                             │
│                             │
│        [Loading dots]       │
│                             │
└─────────────────────────────┘
```
- Duration: 1.5s
- Animated logo fade-in + subtle pulse
- Dark background (#0A0E1A)
- Tagline: "Your Warranties. Protected." (specific, clear)

---

#### Screen 1.2: Welcome (Single Screen — No Carousel)

```
┌─────────────────────────────┐
│                             │
│     [Illustration:          │
│      House with shield      │
│      icon, small sparkles]  │
│                             │
│                             │
│     Never forget a          │
│     warranty again          │
│                             │
│     Track every appliance.  │
│     Get reminders before    │
│     they expire. Save money.│
│                             │
│                             │
│   [🍎 Continue with Apple ] │
│                             │
│   [G  Continue with Google] │
│                             │
│   [ 📧 Sign up with Email ] │
│                             │
│     Already have an         │
│     account? Sign in        │
│                             │
└─────────────────────────────┘
```

**Key decisions:**
- No carousel — one screen says it all. Carousels have <15% completion rates.
- Sign-up options are on this screen — no separate sign-up screen
- Apple/Google one-tap = account created in 1 second
- Email option for users who prefer it (expands inline to show email/password/name fields)
- Referral attribution is handled via **deep links**: realtor shares `havenkeep.app/r/JANE-SMITH` → app opens with referral pre-attached, no manual code entry

---

#### Screen 1.3: What Do You Want to Do? (First Action)

```
┌─────────────────────────────┐
│                             │
│  Welcome, Pacome!           │
│                             │
│  What would you like        │
│  to do first?               │
│                             │
│  ┌───────────────────────┐  │
│  │ 🏠 Set up my new home │  │
│  │                       │  │
│  │ Walk through each     │  │
│  │ room and add your     │  │
│  │ appliances in minutes │  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │ 📷 Scan a receipt     │  │
│  │                       │  │
│  │ Snap a photo and      │  │
│  │ we'll extract the     │  │
│  │ details automatically │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │ ✏️ Add an item         │  │
│  │ manually              │  │
│  └───────────────────────┘  │
│                             │
│  [ I'll explore first → ]   │
│                             │
└─────────────────────────────┘
```

**Key decisions:**
- No home setup form here — if they pick "Set up my new home", the bulk-add flow asks for home name inline
- "I'll explore first" → goes to empty dashboard (with empty state CTA)
- This is the last screen before the user is doing something useful
- Total path: Splash → Welcome/Sign-up → First Action = **3 screens**

---

### FLOW 2: NEW HOME BULK-ADD

This flow is designed for the primary use case: a new homeowner
(referred by a realtor or builder) who needs to add 10-20 items fast.

**Navigation behavior:** Back button preserves all room state. User can
navigate freely between completed rooms without losing any data. Each
room's selections and form data persist in memory until the flow is
completed or cancelled. Cancelling triggers a confirmation dialog if
any items have been added: "Discard all items? You've selected {n}
items across {x} rooms." [Keep Going] [Discard]

---

#### Screen 2.1: Name Your Home (Inline — Top of Bulk Add)

```
┌─────────────────────────────┐
│  ✕ Cancel                   │
│                             │
│  Let's walk through         │
│  your home                  │
│                             │
│  What do you call this      │
│  place?                     │
│                             │
│  ┌───────────────────────┐  │
│  │  e.g. "Our House"     │  │
│  └───────────────────────┘  │
│                             │
│  We'll go room by room.     │
│  Tap the appliances you     │
│  have — takes about         │
│  5 minutes.                 │
│                             │
│  [ Start with Kitchen → ]   │
│                             │
└─────────────────────────────┘
```

- Just one field: home name. That's it.
- Address, move-in date, home type → deferred to Profile (edit home later)
- Gets straight to the rooms

---

#### Screen 2.2: Room Setup — Kitchen

```
┌─────────────────────────────┐
│  ← Back          Skip Room  │
│                             │
│  🍳 Kitchen                  │
│  Room 1 of 6                │
│  ━━━░░░░░░░░░░░░░░░░░░░░   │
│                             │
│  Tap what you have:         │
│                             │
│  ┌──────┐ ┌──────┐ ┌──────┐│
│  │  🧊  │ │  🍽️  │ │  🔥  ││
│  │Fridge│ │Dish- │ │Oven/ ││
│  │      │ │washer│ │Range ││
│  │  ☑️  │ │  ☑️  │ │  ☑️  ││
│  └──────┘ └──────┘ └──────┘│
│                             │
│  ┌──────┐ ┌──────┐ ┌──────┐│
│  │  📡  │ │  ♻️  │ │  🌬️  ││
│  │Micro-│ │Garb. │ │Range ││
│  │wave  │ │Disp. │ │Hood  ││
│  │  ☑️  │ │  ☐  │ │  ☐  ││
│  └──────┘ └──────┘ └──────┘│
│                             │
│  [ + Add Other Item ]       │
│                             │
│  ─────────────────────────  │
│                             │
│  SELECTED (4)               │
│                             │
│  Fill in the basics:        │
│                             │
│  ┌───────────────────────┐  │
│  │ 🧊 Refrigerator        │  │
│  │ Brand  [Samsung    ▼]  │  │
│  │ Bought [📅 Jan 2024 ]  │  │
│  │ Warranty [1yr ▼]       │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ 🍽️ Dishwasher          │  │
│  │ Brand  [LG         ▼]  │  │
│  │ Bought [📅 Jan 2024 ]  │  │
│  │ Warranty [1yr ▼]       │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ 🔥 Oven/Range          │  │
│  │ Brand  [GE         ▼]  │  │
│  │ Bought [📅 Jan 2024 ]  │  │
│  │ Warranty [1yr ▼]       │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ 📡 Microwave           │  │
│  │ Brand  [GE         ▼]  │  │
│  │ Bought [📅 Jan 2024 ]  │  │
│  │ Warranty [1yr ▼]       │  │
│  └───────────────────────┘  │
│                             │
│  [ Next Room → ]            │
│                             │
└─────────────────────────────┘
```

**UX notes:**
- Top: visual grid of common appliances — tap to select/deselect
- Bottom: compact inline form per selected item — only 3 fields: Brand, Purchase Date, Warranty Duration
- Brand dropdown has autocomplete with top brands for that category
- Purchase Date defaults to today (user changes if needed)
- Warranty Duration defaults to common duration for that category
- Model number, serial, price, store = NOT required (add later via edit)
- Goal: minimize friction, get items in fast, refine later
- **← Back preserves all state** — user can revisit any completed room
- **"+ Add Other Item"** — tapping opens an inline row at the bottom of the
  appliance grid: a text field "Item name (e.g. Wine Fridge)" + the same
  3-field compact form (Brand, Bought, Warranty). Category is set to "other".
  User can add multiple custom items per room. This covers specialty appliances
  like wine fridges, espresso machines, or anything not in the predefined grid.

---

#### Screen 2.3: Room Setup — Laundry

```
┌─────────────────────────────┐
│  ← Back          Skip Room  │
│                             │
│  👕 Laundry                  │
│  Room 2 of 6                │
│  ━━━━━━░░░░░░░░░░░░░░░░░   │
│                             │
│  Tap what you have:         │
│                             │
│  ┌──────┐ ┌──────┐ ┌──────┐│
│  │  👕  │ │  💨  │ │  🧺  ││
│  │Washer│ │Dryer │ │Combo ││
│  │  ☐  │ │  ☐  │ │  ☐  ││
│  └──────┘ └──────┘ └──────┘│
│                             │
│  [ + Add Other Item ]       │
│                             │
│  (selected items forms      │
│   appear below, same as     │
│   kitchen pattern)          │
│                             │
│  [ Next Room → ]            │
│                             │
└─────────────────────────────┘
```

---

#### Screen 2.4: Room Setup — HVAC / Utility

```
┌─────────────────────────────┐
│  ← Back          Skip Room  │
│                             │
│  ❄️ HVAC / Utility           │
│  Room 3 of 6                │
│  ━━━━━━━━━━░░░░░░░░░░░░░   │
│                             │
│  Tap what you have:         │
│                             │
│  ┌──────┐ ┌──────┐ ┌──────┐│
│  │  ❄️  │ │  🔥  │ │  🚿  ││
│  │ A/C  │ │Furn- │ │Water ││
│  │Unit  │ │ace   │ │Heater││
│  │  ☐  │ │  ☐  │ │  ☐  ││
│  └──────┘ └──────┘ └──────┘│
│                             │
│  ┌──────┐ ┌──────┐         │
│  │  💧  │ │  🌊  │         │
│  │Water │ │Sump  │         │
│  │Softn.│ │Pump  │         │
│  │  ☐  │ │  ☐  │         │
│  └──────┘ └──────┘         │
│                             │
│  Note: HVAC warranties are  │
│  typically 5-10 years.      │
│  We've pre-set 5 years.     │
│                             │
│  [ Next Room → ]            │
│                             │
└─────────────────────────────┘
```

Additional rooms follow the same pattern:
- **Bathroom(s):** Toilet, Faucet, Shower, Exhaust Fan
- **Living Areas:** TV, Smart Home Hub, Fireplace
- **Garage:** Garage Door Opener, Chest Freezer, Power Tools

---

#### Screen 2.5: Bulk-Add Complete

```
┌─────────────────────────────┐
│                             │
│                             │
│         [✓ Animated         │
│          Checkmark with     │
│          house icon]        │
│                             │
│     Home Setup Complete!    │
│                             │
│     You added 14 items      │
│     across 4 rooms          │
│                             │
│     ┌─────────────────┐     │
│     │ 🍳 Kitchen    5  │     │
│     │ 👕 Laundry    2  │     │
│     │ ❄️ HVAC       3  │     │
│     │ 🚿 Bathroom   2  │     │
│     │ 🏠 Living     2  │     │
│     └─────────────────┘     │
│                             │
│  3 warranties expire this   │
│  year. We'll remind you.    │
│                             │
│  You can add receipts,      │
│  model numbers, and more    │
│  details anytime.           │
│                             │
│  [ Go to Dashboard ]        │
│                             │
└─────────────────────────────┘
```

- Animated celebration (Lottie: checkmark + confetti)
- Shows summary of what was added
- Encourages user to enrich data over time (but doesn't force it)

---

### FLOW 3: CORE APP — HOME DASHBOARD

---

#### Screen 3.1: Home Dashboard

```
┌─────────────────────────────┐
│  HavenKeep              ⚙️  │
│                             │
│  Good morning, Pacome       │
│                             │
│  ┌───────────────────────┐  │
│  │  YOUR WARRANTIES       │  │
│  │                        │  │
│  │  ┌────┐ ┌────┐ ┌────┐ │  │
│  │  │ 12 │ │  3 │ │  2 │ │  │
│  │  │Actv│ │Exp.│ │Expd│ │  │
│  │  │ 🟢 │ │ 🟡 │ │ 🔴 │ │  │
│  │  └────┘ └────┘ └────┘ │  │
│  │                        │  │
│  │  $4,230 in coverage    │  │
│  │  protected right now   │  │
│  │  ── OR if < 50% have ──│  │
│  │  ── price data: ───────│  │
│  │  12 active warranties  │  │
│  └───────────────────────┘  │
│                             │
│  ⚠️ NEEDS ATTENTION          │
│  ┌───────────────────────┐  │
│  │ 🟡 Samsung Fridge RF28 ›│  │
│  │    23 days remaining   │  │
│  │    Expires Mar 15      │  │
│  │    [Get Protection]    │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ 🟡 LG Dishwasher       ›│  │
│  │    45 days remaining   │  │
│  │    Expires Apr 2       │  │
│  │    [Get Protection]    │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ 🔴 Bosch Dryer         ›│  │
│  │    Expired 12 days ago │  │
│  │    [Get Protection]    │  │
│  │    [Find Repair]       │  │
│  └───────────────────────┘  │
│                             │
│  [ View all 5 items → ]     │
│  (only shown when > 3       │
│   items need attention)     │
│                             │
│  💡 TIP                      │
│  ┌───────────────────────┐  │
│  │ Add receipts to your   │  │
│  │ items so you have      │  │
│  │ proof of purchase      │  │
│  │ ready for claims.      │  │
│  │              [Dismiss] │  │
│  └───────────────────────┘  │
│                             │
│  ─────────────────────────  │
│  🏠 Home       [+]    📦 Items│
└─────────────────────────────┘
```

**Key design decisions:**
- **No notification bell** — push notifications + "Needs Attention" section cover alerting.
- **⚙️ gear icon** in top-right → navigates to Profile/Settings screen (not a tab)
- **"Needs Attention" capped at 3 cards.** If more items need attention,
  show "View all {n} items →" link that navigates to Items tab pre-filtered
  to "Expiring + Expired". Keeps dashboard glanceable.
- **Unified CTA language:** "Get Protection" on both expiring and expired items.
- **Needs Attention cards have chevron (›)** on the right side to signal they're
  tappable. Tapping the card body → Item Detail. Tapping [Get Protection] → Affiliate
  offer screen. Two distinct tap targets, both visually clear.
- **Summary counts are tappable.** Tapping the "3 Exp." box → Items tab pre-filtered
  to "Expiring". Tapping "2 Expd" → pre-filtered to "Expired". Tapping "12 Actv" →
  pre-filtered to "Active". Subtle scale press animation on tap (same as card press).
- **Coverage stat is conditional:**
  - If 50%+ of active items have a `price` value: show "$4,230 in coverage protected right now"
  - If < 50%: show "12 active warranties" instead (always accurate, no misleading numbers)
  - This prevents showing "$0 in coverage" for users who Quick-Added without prices
- Bottom bar shows 2 tabs: Home and Items

**Dashboard Tip Rotation (contextual):**
- New user, no receipts: "Add receipts to your items for proof of purchase"
- Items with no model number: "Add model numbers to speed up warranty claims"
- Warranty expiring: "Did you know you can extend your {brand} coverage?"
- All items have full data: "You're all set! We'll notify you before anything expires."
- Tips auto-rotate, can be dismissed, max 1 shown at a time

---

#### Screen 3.2: Dashboard — Loading / Skeleton State

```
┌─────────────────────────────┐
│  HavenKeep              ⚙️  │
│                             │
│  Good morning, Pacome       │
│                             │
│  ┌───────────────────────┐  │
│  │  YOUR WARRANTIES       │  │
│  │                        │  │
│  │  ┌────┐ ┌────┐ ┌────┐ │  │
│  │  │ ░░ │ │ ░░ │ │ ░░ │ │  │
│  │  │░░░░│ │░░░░│ │░░░░│ │  │
│  │  │    │ │    │ │    │ │  │
│  │  └────┘ └────┘ └────┘ │  │
│  │                        │  │
│  │  ░░░░░░░░░░░░░░░░░░   │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │ ░░░░░░░░░░░░░░░░░░░  │  │
│  │ ░░░░░░░░░░░░░         │  │
│  │ ░░░░░░░░░░            │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │ ░░░░░░░░░░░░░░░░░░░  │  │
│  │ ░░░░░░░░░░░░░         │  │
│  │ ░░░░░░░░░░            │  │
│  └───────────────────────┘  │
│                             │
│  ─────────────────────────  │
│  🏠 Home       [+]    📦 Items│
└─────────────────────────────┘
```

**Skeleton loading rules:**
- Show on cold app start while data loads from local storage / cloud
- Gray pulsing placeholder blocks (animate opacity 0.3 → 0.7 → 0.3)
- Match the exact layout of the real dashboard so there's no layout shift
- Transition: skeleton → real content with a quick 200ms fade
- If data loads from local cache in < 300ms, skip skeleton entirely
- Same skeleton pattern applies to Items list (Screen 4.1)

---

### FLOW 4: ITEMS LIST & MANAGEMENT

---

#### Screen 4.1: Items List

```
┌─────────────────────────────┐
│  My Items                   │
│                             │
│  ┌───────────────────────┐  │
│  │  🔍 Search items...    │  │
│  └───────────────────────┘  │
│                             │
│  [All] [Active 🟢]          │
│  [Expiring 🟡] [Expired 🔴]  │
│                             │
│  KITCHEN (5)                │
│  ┌───────────────────────┐  │
│  │ [img] Samsung Fridge   │  │
│  │       RF28R7551SR      │  │
│  │       🟡 23 days left  │  │
│  ├───────────────────────┤  │
│  │ [img] LG Dishwasher    │  │
│  │       LDF5545ST        │  │
│  │       🟡 45 days left  │  │
│  ├───────────────────────┤  │
│  │ [img] GE Microwave     │  │
│  │       JVM6175YKFS      │  │
│  │       🟢 2 yrs left    │  │
│  └───────────────────────┘  │
│                             │
│  LAUNDRY (2)                │
│  ┌───────────────────────┐  │
│  │ [img] Bosch Washer     │  │
│  │       WAT28400UC       │  │
│  │       🟢 1.5 yrs left  │  │
│  ├───────────────────────┤  │
│  │ [img] Bosch Dryer      │  │
│  │       WTG86401UC       │  │
│  │       🔴 Expired       │  │
│  └───────────────────────┘  │
│                             │
│  HVAC (3)                   │
│  ┌───────────────────────┐  │
│  │ [img] Carrier AC       │  │
│  │       24ACC636A003     │  │
│  │       🟢 4 yrs left    │  │
│  └───────────────────────┘  │
│                             │
│  GENERAL (1)                │
│  ┌───────────────────────┐  │
│  │ [img] Roof Warranty    │  │
│  │       GAF Timberline   │  │
│  │       🟢 8 yrs left    │  │
│  └───────────────────────┘  │
│                             │
│  ─────────────────────────  │
│  🏠 Home       [+]    📦 Items│
└─────────────────────────────┘
```

**Interactions:**
- Inline search bar (real-time text filter)
- Status filter chips: All / Active / Expiring / Expired
- "View all" link from dashboard arrives here with Expiring+Expired pre-selected
- Room sections are collapsible (tap header)
- Items with no room assigned appear under "GENERAL" section
- Swipe left on item → [Archive] [Delete]
  - **Archive:** Moves item to archived state. Confirmation: "Archive Samsung Fridge? It won't appear in your item list but you can restore it from Profile > Archived Items." [Cancel] [Archive]
  - **Delete:** Destructive. Requires confirmation dialog (see Screen 4.2)
- Tap item → Item Detail

**Loading state:** Same skeleton pattern as dashboard. Gray pulsing rows matching the card layout. Show 5 placeholder rows.

---

#### Screen 4.2: Delete Confirmation Dialog

```
┌─────────────────────────────┐
│                             │
│  (existing screen dimmed)   │
│                             │
│  ┌───────────────────────┐  │
│  │                       │  │
│  │  Delete Samsung Fridge?│  │
│  │                       │  │
│  │  This will permanently │  │
│  │  delete this item and  │  │
│  │  3 attached documents  │  │
│  │  (receipt, warranty    │  │
│  │  card, manual).        │  │
│  │                       │  │
│  │  This cannot be undone.│  │
│  │                       │  │
│  │  [ Cancel ]            │  │
│  │  [ Delete ] (red)      │  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

**Rules:**
- Always shows the item name
- Always counts and displays attached documents that will also be deleted
- "Delete" button is red (#EF4444) to signal destructive action
- If no documents attached: "This will permanently delete this item."
- Same dialog used everywhere delete is available (item detail ⋮ menu, swipe)

---

### FLOW 5: ADD ITEM

---

#### Screen 5.1: Add Item — Method Selection (Bottom Sheet)

```
┌─────────────────────────────┐
│                             │
│  (existing screen dimmed)   │
│                             │
├─────────────────────────────┤
│  ─── (drag handle) ───      │
│                             │
│  Add New Item               │
│                             │
│  QUICK ADD                  │
│  ┌──────┐ ┌──────┐ ┌──────┐│
│  │ 🧊  │ │ 👕  │ │ 💨  ││
│  │Fridge│ │Washer│ │Dryer ││
│  └──────┘ └──────┘ └──────┘│
│  ┌──────┐ ┌──────┐ ┌──────┐│
│  │ 🍽️  │ │ 📡  │ │ 🔥  ││
│  │Dish- │ │Micro-│ │Oven  ││
│  │washer│ │wave  │ │      ││
│  └──────┘ └──────┘ └──────┘│
│  ┌──────┐ ┌──────┐ ┌──────┐│
│  │ ❄️  │ │ 🚿  │ │ ···  ││
│  │HVAC  │ │Water │ │Other ││
│  │      │ │Heat. │ │      ││
│  └──────┘ └──────┘ └──────┘│
│                             │
│  ─── or ───                 │
│                             │
│  ┌───────────────────────┐  │
│  │  📷  Scan Receipt      │  │
│  │  Auto-extract details  │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │  ✏️  Full Manual Entry  │  │
│  │  All fields            │  │
│  └───────────────────────┘  │
│  ┌───────────────────────┐  │
│  │  ┃┃┃  Scan Barcode     │  │
│  │  Look up product info  │  │
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

**Method priority (by expected usage):**
1. **Quick-Add grid** (~80%) — tap an icon, fill 3 fields, done. Covers all common appliances.
2. **Scan Receipt** (~15%) — best value: auto-extracts store, date, item name, price + attaches receipt image.
3. **Full Manual Entry** (~3%) — all fields, for users who want full control upfront.
4. **Scan Barcode** (~2%) — pre-fills brand, name, model from UPC lookup. Most useful for specialty items not in the Quick-Add grid. Positioned last because Quick-Add is faster for common appliances and receipt scan captures more data.

---

#### Screen 5.2: Quick-Add Form

```
┌─────────────────────────────┐
│  ← Add Refrigerator         │
│                             │
│  [🧊 Refrigerator icon]     │
│                             │
│  Brand *                    │
│  ┌───────────────────────┐  │
│  │  Samsung          ▼   │  │
│  │  ─────────────────    │  │
│  │  Samsung              │  │
│  │  LG                   │  │
│  │  GE                   │  │
│  │  Whirlpool            │  │
│  │  Frigidaire           │  │
│  │  KitchenAid           │  │
│  │  Bosch                │  │
│  │  Other...             │  │
│  └───────────────────────┘  │
│                             │
│  Purchase Date *            │
│  ┌───────────────────────┐  │
│  │  📅 January 15, 2024  │  │
│  └───────────────────────┘  │
│                             │
│  Warranty Duration          │
│  ┌────┐                     │
│  │ 1  │ [Years ▼]           │
│  └────┘                     │
│  (default for refrigerators)│
│                             │
│  Saving to: Kitchen         │
│  (auto-assigned · change)   │
│                             │
│  [ Save Item ]              │
│                             │
│  Want to add more details?  │
│  [+ Model, serial, receipt] │
│                             │
└─────────────────────────────┘
```

- **3 fields** — same as bulk-add: Brand, Purchase Date, Warranty Duration
- Room is **auto-assigned** from `category_defaults` (e.g. Refrigerator → Kitchen).
  Shown as a subtle read-only label: "Saving to: Kitchen (change)". Tapping
  "change" opens a room picker. This keeps the form identical in mental model
  to bulk-add: you always fill 3 things. Room is smart, not a question.
- Brand dropdown pre-populated per category
- "Want to add more details?" expands to model, serial, price, store, room override, receipt upload
- **v6 change:** Removed Room as a visible 4th form field. Now auto-assigned
  with optional override. Matches the 3-field pattern in bulk-add (Screen 2.2)
  so the user's mental model stays consistent across all quick entry flows.

---

#### Screen 5.3: Receipt Scan — Camera

```
┌─────────────────────────────┐
│  ✕ Cancel                   │
│                             │
│  ┌───────────────────────┐  │
│  │                       │  │
│  │                       │  │
│  │    CAMERA VIEWFINDER  │  │
│  │                       │  │
│  │   ┌─────────────┐    │  │
│  │   │  Align your │    │  │
│  │   │  receipt    │    │  │
│  │   │  here       │    │  │
│  │   └─────────────┘    │  │
│  │                       │  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
│  🖼️           [◉]        ⚡ │
│  Gallery     Capture    Flash│
│                             │
│  Tip: Hold steady over the  │
│  full receipt for best      │
│  results                    │
└─────────────────────────────┘
```

---

#### Screen 5.4: Receipt Scan — Processing

```
┌─────────────────────────────┐
│                             │
│                             │
│  ┌───────────────────────┐  │
│  │                       │  │
│  │  [Receipt image with  │  │
│  │   animated scanning   │  │
│  │   line moving down]   │  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
│       Reading receipt...    │
│                             │
│  ✓ Store detected           │
│  ✓ Date found               │
│  ○ Extracting items...      │
│  ○ Looking up products      │
│                             │
│                             │
└─────────────────────────────┘
```

---

#### Screen 5.5: Receipt Scan — Results / Confirm

```
┌─────────────────────────────┐
│  ← Review Details           │
│                             │
│  We found this:             │
│                             │
│  Store                      │
│  ┌───────────────────────┐  │
│  │  Best Buy             │  │
│  └───────────────────────┘  │
│                             │
│  Purchase Date              │
│  ┌───────────────────────┐  │
│  │  📅 January 15, 2024  │  │
│  └───────────────────────┘  │
│                             │
│  Item                       │
│  ┌───────────────────────┐  │
│  │  Samsung French Door   │  │
│  │  Refrigerator          │  │
│  └───────────────────────┘  │
│                             │
│  Price                      │
│  ┌───────────────────────┐  │
│  │  $1,299.99            │  │
│  └───────────────────────┘  │
│                             │
│  ⚠️ Verify the details above │
│  and fill in the rest:      │
│                             │
│  Model Number               │
│  ┌───────────────────────┐  │
│  │  RF28R7551SR          │  │
│  └───────────────────────┘  │
│                             │
│  Room                       │
│  [Kitchen ▼]                │
│                             │
│  Warranty Duration          │
│  ┌────┐                     │
│  │ 1  │ [Years ▼]           │
│  └────┘                     │
│                             │
│  Receipt Photo              │
│  [📷 Attached ✓]            │
│                             │
│  [ Save Item ]              │
│                             │
└─────────────────────────────┘
```

**Multi-item receipts (v1 behavior):**
If OCR detects multiple items on a single receipt, show a picker before
the confirm screen:
```
┌───────────────────────┐
│  We found 3 items on   │
│  this receipt:         │
│                        │
│  ☑ Samsung Fridge      │
│    $1,299.99           │
│  ☐ LG Dishwasher       │
│    $649.00             │
│  ☐ GE Microwave        │
│    $249.99             │
│                        │
│  Select one to add.    │
│  (Add others after.)   │
│                        │
│  [ Continue → ]        │
└───────────────────────┘
```
- v1: single selection only → goes to confirm screen for that item
- After saving, "Add Another" on success screen re-opens the picker
  with remaining unchecked items
- v2 enhancement: allow multi-select → batch add all items at once

---

#### Screen 5.6: Manual Entry Form

```
┌─────────────────────────────┐
│  ← Add Item                 │
│                             │
│  Product Photo (optional)   │
│  ┌──────────┐               │
│  │  + 📷    │               │
│  │  Add     │               │
│  │  Photo   │               │
│  └──────────┘               │
│                             │
│  Product Name *             │
│  ┌───────────────────────┐  │
│  │  e.g. Samsung Fridge  │  │
│  └───────────────────────┘  │
│                             │
│  Brand                      │
│  ┌───────────────────────┐  │
│  │  e.g. Samsung         │  │
│  └───────────────────────┘  │
│                             │
│  Model Number               │
│  ┌───────────────────────┐  │
│  │  e.g. RF28R7551SR     │  │
│  └───────────────────────┘  │
│                             │
│  Serial Number (optional)   │
│  ┌───────────────────────┐  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
│  Category                   │
│  [Appliance ▼]              │
│                             │
│  Room (optional)            │
│  [Kitchen ▼] [None]         │
│                             │
│  ── Purchase Info ──        │
│                             │
│  Purchase Date *            │
│  ┌───────────────────────┐  │
│  │  📅 Select date       │  │
│  └───────────────────────┘  │
│                             │
│  Store / Retailer           │
│  ┌───────────────────────┐  │
│  │  e.g. Best Buy        │  │
│  └───────────────────────┘  │
│                             │
│  Price Paid                 │
│  ┌───────────────────────┐  │
│  │  $ 0.00               │  │
│  └───────────────────────┘  │
│                             │
│  ── Warranty Info ──        │
│                             │
│  Warranty Duration *        │
│  ┌────┐                     │
│  │ 1  │ [Years ▼]           │
│  └────┘                     │
│                             │
│  Warranty Type              │
│  [Manufacturer]             │
│  [Extended]                 │
│  [Store]                    │
│                             │
│  Warranty Provider          │
│  ┌───────────────────────┐  │
│  │  e.g. Samsung         │  │
│  └───────────────────────┘  │
│                             │
│  ── Documents ──            │
│                             │
│  [+ Add Receipt Photo]      │
│  [+ Add Warranty Doc]       │
│  [+ Add Manual / PDF]       │
│                             │
│  ── Notes ──                │
│  ┌───────────────────────┐  │
│  │  Any additional notes  │  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
│  [ Save Item ]              │
│                             │
└─────────────────────────────┘
```

**v4 change:** Room field is now optional with a "None" option.
Items like roofing, windows, or flooring don't belong to a specific room.

---

### FLOW 6: ITEM DETAIL

---

#### Screen 6.1: Item Detail — Active/Expiring

```
┌─────────────────────────────┐
│  ←                  ✏️  ⋮   │
│                             │
│  ┌───────────────────────┐  │
│  │                       │  │
│  │   [Product Image]     │  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
│  Samsung French Door        │
│  Refrigerator               │
│  RF28R7551SR                │
│                             │
│  ┌────────────────────────┐ │
│  │  WARRANTY STATUS       │ │
│  │                        │ │
│  │  🟡 Expiring Soon      │ │
│  │                        │ │
│  │  23 days remaining     │ │
│  │  Expires Jan 15, 2025  │ │
│  │                        │ │
│  │  Purchased Jan 15, '24 │ │
│  │  Duration  1 year      │ │
│  │                        │ │
│  │  [🛡️ Get Protection →] │ │
│  └────────────────────────┘ │
│                             │
│  ┌────────────────────────┐ │
│  │ DETAILS                ▾│ │
│  ├────────────────────────┤ │
│  │  Brand      Samsung    │ │
│  │  Model      RF28R..SR  │ │
│  │  Serial     SN12345..  │ │
│  │  Category   Appliance  │ │
│  │  Room       Kitchen    │ │
│  │  Price      $1,299.99  │ │
│  │  Store      Best Buy   │ │
│  │  Warranty   Manufactu. │ │
│  │  Provider   Samsung    │ │
│  └────────────────────────┘ │
│                             │
│  ┌────────────────────────┐ │
│  │ DOCUMENTS (3)          ▾│ │
│  ├────────────────────────┤ │
│  │ 📷 Receipt.jpg         │ │
│  │ 📄 Warranty_Card.pdf   │ │
│  │ 📄 User_Manual.pdf     │ │
│  │ [+ Add Document]       │ │
│  └────────────────────────┘ │
│                             │
│  ┌────────────────────────┐ │
│  │ NEED HELP WITH A       │ │
│  │ CLAIM?                 ▾│ │
│  ├────────────────────────┤ │
│  │ [ 🔍 Search Samsung    │ │
│  │      Warranty Support ] │ │
│  │                        │ │
│  │ [ 📤 Share Claim Info ] │ │
│  │   Copy model, serial,  │ │
│  │   and purchase details  │ │
│  │   to clipboard or share │ │
│  └────────────────────────┘ │
│                             │
│  ┌────────────────────────┐ │
│  │ NOTES                  ▾│ │
│  ├────────────────────────┤ │
│  │ "Ice maker makes weird │ │
│  │  noise sometimes"      │ │
│  │                  [Edit] │ │
│  └────────────────────────┘ │
│                             │
└─────────────────────────────┘
```

**v6 change — Collapsible accordion sections:**
The screen has 5 content blocks (image+name, warranty status, details, documents,
claim help, notes). On a phone that's a lot of scrolling. The redesign keeps the
hero content (image, name, warranty status + CTA) always visible, then uses
**collapsible accordion sections** for everything below it:

- **DETAILS ▾** — collapsed by default for items added via Quick-Add (sparse data).
  Expanded by default for items with 5+ fields populated.
- **DOCUMENTS (3) ▾** — expanded by default (users need quick doc access for claims).
  If 0 documents: shows collapsed with "(0)" count + "Add your first document" prompt.
- **NEED HELP WITH A CLAIM? ▾** — collapsed by default. This is a secondary action
  the user reaches for only when filing a claim.
- **NOTES ▾** — collapsed by default. Expanded if notes exist. If no notes:
  collapsed with "Add a note" prompt.

**Accordion behavior:**
- ▾ chevron rotates to ▴ when expanded
- Smooth height animation (250ms ease-out)
- Tap anywhere on the section header to toggle
- Multiple sections can be open simultaneously
- State persists per item (remembered between visits via local storage)
- The hero section (image + warranty status + Get Protection) is NEVER collapsible —
  it's the reason you opened this screen

**Key changes from v3:**
- **Unified CTA:** "Get Protection" replaces "Extend Warranty" (expiring) and
  "Get Coverage" (expired). Same affiliate screen, same language everywhere.
- **Share Claim Info wording:** Changed "to clipboard or PDF" to "to clipboard or share"
  to avoid confusion with premium PDF export. The claim info share sheet (Screen 6.3)
  can still generate a single-item PDF — this is free. The premium-gated feature is
  bulk inventory export.

**Interactions:**
- ✏️ → Edit Item (Screen 6.4)
- ⋮ → Menu: Share, Archive, Delete
  - Archive → confirmation: "Archive? Won't appear in lists, restorable from Profile."
  - Delete → confirmation dialog (Screen 4.2)
- "Get Protection" → Affiliate offer screen (Screen 8.1)
- "Search {Brand} Support" → in-app browser with pre-filled search
- "Share Claim Info" → Share sheet (Screen 6.3)
- Document tap → full-screen viewer
- Notes [Edit] → inline edit
- Section headers → toggle expand/collapse

---

#### Screen 6.2: Item Detail — Expired State

```
┌─────────────────────────────┐
│  ←                  ✏️  ⋮   │
│                             │
│  [Product Image]            │
│                             │
│  LG Front Load Washer       │
│  WM3900HBA                  │
│                             │
│  ┌────────────────────────┐ │
│  │  WARRANTY STATUS       │ │
│  │                        │ │
│  │  🔴 Expired            │ │
│  │                        │ │
│  │  Expired 341 days ago  │ │
│  │  Coverage ended        │ │
│  │  Mar 5, 2024           │ │
│  │                        │ │
│  │  ┌──────────────────┐  │ │
│  │  │🛡️ Get Protection │  │ │
│  │  │ Protect this     │  │ │
│  │  │ item from $6/mo  │  │ │
│  │  └──────────────────┘  │ │
│  │                        │ │
│  │  ┌──────────────────┐  │ │
│  │  │ 🔧 Find Repair   │  │ │
│  │  │ Top techs near   │  │ │
│  │  │ you              │  │ │
│  │  └──────────────────┘  │ │
│  └────────────────────────┘ │
│                             │
│  (rest same as active —     │
│   accordion sections below) │
│                             │
└─────────────────────────────┘
```

**v4 change:** "Get Coverage" renamed to "Get Protection" — consistent with
expiring state and dashboard cards.

---

#### Screen 6.3: Share Claim Info (Bottom Sheet)

```
┌─────────────────────────────┐
│                             │
│  (existing screen dimmed)   │
│                             │
├─────────────────────────────┤
│  ─── (drag handle) ───      │
│                             │
│  Share Claim Info            │
│                             │
│  ┌───────────────────────┐  │
│  │ Samsung French Door    │  │
│  │ Refrigerator           │  │
│  │                        │  │
│  │ Model:  RF28R7551SR    │  │
│  │ Serial: SN123456789    │  │
│  │ Purchased: Jan 15, '24 │  │
│  │ Warranty expires:      │  │
│  │   Jan 15, '25          │  │
│  │ Store: Best Buy        │  │
│  │ Price: $1,299.99       │  │
│  │                        │  │
│  │ Provider: Samsung      │  │
│  └───────────────────────┘  │
│                             │
│  [ 📋 Copy to Clipboard ]   │
│  [ 📧 Email ]               │
│  [ 📱 Text Message ]        │
│  [ 📄 Save as PDF ]         │
│                             │
│  Receipt photo included     │
│  with email and PDF.        │
│                             │
└─────────────────────────────┘
```

**Important — PDF gating clarification:**
- **"Save as PDF" here is FREE.** This is a single-item claim summary PDF.
  It's part of the core claim support flow. Gating this would punish users
  at the exact moment they need help.
- **What's premium:** "Export Data" in Profile/Settings → full inventory
  export as PDF report or CSV spreadsheet. That's a bulk convenience feature.

---

#### Screen 6.4: Edit Item (Full Screen)

```
┌─────────────────────────────┐
│  ✕ Cancel      Save Changes │
│                             │
│  Edit Item                  │
│                             │
│  Product Photo              │
│  ┌──────────┐               │
│  │ [Current │               │
│  │  photo]  │  [Change]     │
│  └──────────┘               │
│                             │
│  Product Name *             │
│  ┌───────────────────────┐  │
│  │  Samsung French Door   │  │
│  │  Refrigerator          │  │
│  └───────────────────────┘  │
│                             │
│  Brand                      │
│  ┌───────────────────────┐  │
│  │  Samsung              │  │
│  └───────────────────────┘  │
│                             │
│  Model Number               │
│  ┌───────────────────────┐  │
│  │  RF28R7551SR          │  │
│  └───────────────────────┘  │
│                             │
│  Serial Number              │
│  ┌───────────────────────┐  │
│  │  SN123456789          │  │
│  └───────────────────────┘  │
│                             │
│  Category                   │
│  [Refrigerator ▼]           │
│                             │
│  Room (optional)            │
│  [Kitchen ▼]                │
│                             │
│  ── Purchase Info ──        │
│                             │
│  Purchase Date *            │
│  ┌───────────────────────┐  │
│  │  📅 January 15, 2024  │  │
│  └───────────────────────┘  │
│                             │
│  Store / Retailer           │
│  ┌───────────────────────┐  │
│  │  Best Buy             │  │
│  └───────────────────────┘  │
│                             │
│  Price Paid                 │
│  ┌───────────────────────┐  │
│  │  $ 1,299.99           │  │
│  └───────────────────────┘  │
│                             │
│  ── Warranty Info ──        │
│                             │
│  Warranty Duration *        │
│  ┌────┐                     │
│  │ 1  │ [Years ▼]           │
│  └────┘                     │
│                             │
│  Warranty Type              │
│  [Manufacturer ✓]           │
│  [Extended]                 │
│  [Store]                    │
│                             │
│  Warranty Provider          │
│  ┌───────────────────────┐  │
│  │  Samsung              │  │
│  └───────────────────────┘  │
│                             │
│  ── Documents ──            │
│                             │
│  📷 Receipt.jpg        [✕]  │
│  📄 Warranty_Card.pdf  [✕]  │
│  📄 User_Manual.pdf    [✕]  │
│  [+ Add Document]           │
│                             │
│  ── Notes ──                │
│  ┌───────────────────────┐  │
│  │  Ice maker makes weird│  │
│  │  noise sometimes      │  │
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

**Key design decisions:**
- Same layout as Manual Entry form (Screen 5.6) but **pre-filled** with existing data
- "Save Changes" in top-right (enabled only when changes detected)
- "✕ Cancel" in top-left — if changes were made, confirm: "Discard changes?" [Keep Editing] [Discard]
- Documents section shows existing docs with [✕] to remove + [+ Add Document] to add
- Removing a document shows confirmation: "Remove Receipt.jpg?" [Cancel] [Remove]
- This is the screen users land on after Quick-Add to enrich items with model number, serial, etc.
- Full screen, not a modal — scroll-heavy content needs full space

---

### FLOW 7: PROFILE & SETTINGS

Now accessed via ⚙️ gear icon in dashboard header, not a tab.

---

#### Screen 7.1: Profile & Settings

```
┌─────────────────────────────┐
│  ← Settings                 │
│                             │
│  ┌───────────────────────┐  │
│  │  [Avatar]             │  │
│  │  Pacome Domegni       │  │
│  │  pacome@email.com     │  │
│  │  Free Plan · 14/25    │  │
│  │  items used           │  │
│  │  [Upgrade to Premium] │  │
│  └───────────────────────┘  │
│                             │
│  MY HOMES                   │
│  ┌───────────────────────┐  │
│  │ 🏠 Our House           │>│
│  │    14 items tracked    │  │
│  ├───────────────────────┤  │
│  │ + Add Another Property │  │
│  │   (Premium)            │  │
│  └───────────────────────┘  │
│                             │
│  GENERAL                    │
│  ┌───────────────────────┐  │
│  │ 🔔 Notifications       │>│
│  ├───────────────────────┤  │
│  │ 👥 Family Sharing      │>│
│  │    (Premium)           │  │
│  ├───────────────────────┤  │
│  │ 📦 Archived Items      │>│
│  ├───────────────────────┤  │
│  │ 📊 Export Data          │>│
│  │    (Premium)           │  │
│  └───────────────────────┘  │
│                             │
│  REFERRAL                   │
│  ┌───────────────────────┐  │
│  │ 🎁 Referred by:        │  │
│  │    Jane Smith Realty   │  │
│  └───────────────────────┘  │
│                             │
│  SUPPORT                    │
│  ┌───────────────────────┐  │
│  │ ❓ Help Center          │>│
│  ├───────────────────────┤  │
│  │ 💬 Contact Support      │>│
│  ├───────────────────────┤  │
│  │ ⭐ Rate HavenKeep       │>│
│  ├───────────────────────┤  │
│  │ 📜 Terms & Privacy      │>│
│  └───────────────────────┘  │
│                             │
│  App version 1.0.0          │
│                             │
│  [ Sign Out ]               │
│                             │
└─────────────────────────────┘
```

**Changes from v3:**
- Header: "← Settings" with back arrow (navigates back to Dashboard). No tab bar on this screen.
- Added "📦 Archived Items" row under GENERAL — this is where archived items can be viewed and restored
- "📊 Export Data" now explicitly labeled "(Premium)" — this is the bulk export feature
- No bottom tab bar on this screen — it's a pushed screen, not a tab

**Tapping "Our House" → opens Home Detail screen (7.3).**

---

#### Screen 7.2: Notification Preferences (Simplified)

```
┌─────────────────────────────┐
│  ← Notifications            │
│                             │
│  WARRANTY REMINDERS         │
│                             │
│  Remind me before           │
│  warranties expire          │
│  ┌─────────────────[ON ]┐   │
│  └──────────────────────┘   │
│                             │
│  Start reminding me         │
│  ┌───────────────────────┐  │
│  │  30 days before    ▼  │  │
│  │  ────────────────     │  │
│  │  90 days before       │  │
│  │  60 days before       │  │
│  │  30 days before  ✓    │  │
│  │  14 days before       │  │
│  │  7 days before        │  │
│  └───────────────────────┘  │
│                             │
│  Then remind again at       │
│  7 days and 1 day before    │
│  expiry. (Always on)        │
│                             │
│  REMINDER TIME              │
│  ┌───────────────────────┐  │
│  │  🕐 9:00 AM           │  │
│  └───────────────────────┘  │
│                             │
│  OTHER                      │
│                             │
│  Extended warranty offers   │
│  ┌─────────────────[ON ]┐   │
│  └──────────────────────┘   │
│  Show offers when           │
│  warranties are expiring    │
│                             │
│  Tips                       │
│  ┌─────────────────[ON ]┐   │
│  └──────────────────────┘   │
│  Helpful tips on the        │
│  dashboard                  │
│                             │
└─────────────────────────────┘
```

**Design:** 1 master toggle + 1 "start reminding" picker.
7-day and 1-day reminders always fire (non-negotiable).
Much simpler mental model: "yes I want reminders" + "how early"

---

#### Screen 7.3: Home Detail

```
┌─────────────────────────────┐
│  ← Our House                │
│                             │
│  HOME NAME                  │
│  ┌───────────────────────┐  │
│  │  Our House            │  │
│  └───────────────────────┘  │
│                             │
│  ADDRESS                    │
│  ┌───────────────────────┐  │
│  │  123 Main Street      │  │
│  └───────────────────────┘  │
│                             │
│  ┌────────────┐┌──────────┐ │
│  │ City       ││ State    │ │
│  │ Austin     ││ TX    ▼  │ │
│  └────────────┘└──────────┘ │
│                             │
│  ZIP                        │
│  ┌───────────────────────┐  │
│  │  78701               │  │
│  └───────────────────────┘  │
│                             │
│  HOME TYPE                  │
│  [House ▼]                  │
│                             │
│  MOVE-IN DATE               │
│  ┌───────────────────────┐  │
│  │  📅 January 5, 2024   │  │
│  └───────────────────────┘  │
│                             │
│  ─────────────────────────  │
│                             │
│  14 items tracked in this   │
│  home.                      │
│                             │
│  ─────────────────────────  │
│                             │
│  [ Delete Home ] (red text) │
│                             │
└─────────────────────────────┘
```

**Interactions:**
- All fields editable inline — auto-saves on blur (no save button needed,
  lightweight form). Visual confirmation: brief checkmark flash on field.
- These are the fields deferred from onboarding — this is where they live now.
- "Delete Home" → confirmation dialog:
  - If home has items: "Delete Our House? This will also delete 14 items
    and all their documents. This cannot be undone." [Cancel] [Delete Home] (red)
  - If home has no items: "Delete Our House? This cannot be undone."
    [Cancel] [Delete Home] (red)
- Deleting a home returns user to Settings screen.

---

#### Screen 7.4: Archived Items

```
┌─────────────────────────────┐
│  ← Archived Items           │
│                             │
│  ┌───────────────────────┐  │
│  │ [img] Old Microwave    │  │
│  │       GE JVM3160       │  │
│  │       🔴 Expired       │  │
│  │       Archived Dec 1   │  │
│  │              [Restore] │  │
│  ├───────────────────────┤  │
│  │ [img] Window AC Unit   │  │
│  │       LG LW8016ER      │  │
│  │       🔴 Expired       │  │
│  │       Archived Oct 15  │  │
│  │              [Restore] │  │
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

**Interactions:**
- Same card layout as Items list but with archive date and [Restore] button
- No filter chips — simple flat list
- **Restore:** Tapping [Restore] moves item back to active Items list immediately.
  Toast: "Old Microwave restored ✓"
- **Swipe left → [Delete permanently]** → Delete confirmation dialog (Screen 4.2)
  with additional note: "This item is archived. Deleting will permanently remove it."
- **Empty state:** (already spec'd in Empty States section)
- Archived items count toward the free plan 25-item limit (stated clearly in
  the item limit error 10.5: "Tip: You can archive old items to free up space."
  — wait, this is contradictory. Clarification: **archived items do NOT count
  toward the limit.** Archiving genuinely frees up space. This makes the free
  workaround in error 10.5 actually useful.)

---

### FLOW 8: AFFILIATE / MONETIZATION SCREENS

---

#### Screen 8.1: Protection Offer (Unified)

```
┌─────────────────────────────┐
│  ✕ Close                    │
│                             │
│  🛡️ Get Protection           │
│                             │
│  Your Samsung Fridge        │
│  warranty expires in        │
│  23 days                    │
│                             │
│  ┌───────────────────────┐  │
│  │  RECOMMENDED           │  │
│  │                        │  │
│  │  Asurion Complete      │  │
│  │  Protection            │  │
│  │                        │  │
│  │  ✓ Parts & labor       │  │
│  │  ✓ Power surge         │  │
│  │  ✓ No deductible       │  │
│  │  ✓ Transferable        │  │
│  │                        │  │
│  │  $8.99/mo              │  │
│  │  or $89.99/yr          │  │
│  │                        │  │
│  │  [ Get This Plan → ]   │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  OnPoint Basic         │  │
│  │                        │  │
│  │  ✓ Parts & labor       │  │
│  │  ✓ $50 deductible      │  │
│  │                        │  │
│  │  $5.99/mo              │  │
│  │                        │  │
│  │  [ View Details → ]    │  │
│  └───────────────────────┘  │
│                             │
│  Powered by trusted         │
│  warranty providers.        │
│  HavenKeep may earn a      │
│  commission.                │
│                             │
└─────────────────────────────┘
```

**v4 change:** Title changed from "Extend Your Coverage" to "Get Protection" —
consistent with CTA buttons everywhere. Works for both expiring (extend) and
expired (new coverage) items since the affiliate partners serve both cases.

**Context-aware header text:**
- Expiring: "Your Samsung Fridge warranty expires in 23 days"
- Expired: "Your LG Washer warranty expired 341 days ago"
- Same screen, same offers, different header copy.

---

#### Screen 8.2: Find Repair Service

```
┌─────────────────────────────┐
│  ← Find a Repair Tech       │
│                             │
│  For: LG Front Load Washer  │
│  WM3900HBA                  │
│                             │
│  📍 Near: 123 Main St       │
│                             │
│  TOP RATED NEAR YOU         │
│                             │
│  ┌───────────────────────┐  │
│  │ ⭐ 4.8  Mike's         │  │
│  │        Appliance       │  │
│  │        2.3 mi away     │  │
│  │                        │  │
│  │  "LG certified tech"  │  │
│  │  Est: $85-150          │  │
│  │                        │  │
│  │  [ Request Quote ]     │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │ ⭐ 4.6  Pro Appliance  │  │
│  │        Repair          │  │
│  │        4.1 mi away     │  │
│  │                        │  │
│  │  Est: $75-120          │  │
│  │                        │  │
│  │  [ Request Quote ]     │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  🔍 Browse more on     │  │
│  │     Angi / Thumbtack   │  │
│  └───────────────────────┘  │
│                             │
│  Powered by Angi.           │
│  HavenKeep may earn a      │
│  referral fee.              │
│                             │
└─────────────────────────────┘
```

---

#### Screen 8.3: Premium Upgrade

```
┌─────────────────────────────┐
│  ✕ Close                    │
│                             │
│  ┌───────────────────────┐  │
│  │                       │  │
│  │   [Crown/Shield icon] │  │
│  │                       │  │
│  │   HavenKeep Premium   │  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
│  Unlock the full power of   │
│  HavenKeep                  │
│                             │
│  ✓ Unlimited items          │
│    Free plan: 25 items      │
│                             │
│  ✓ Family sharing           │
│    Up to 5 members          │
│                             │
│  ✓ Multiple properties      │
│    Track all your homes     │
│                             │
│  ✓ Export to PDF / CSV      │
│    Full warranty reports    │
│                             │
│  ✓ Priority support         │
│    Get help fast            │
│                             │
│  ┌───────────────────────┐  │
│  │  BEST VALUE            │  │
│  │  $24.99/year           │  │
│  │  Save 30%              │  │
│  │  [ Start Free Trial ]  │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  $2.99/month           │  │
│  │  [ Start Free Trial ]  │  │
│  └───────────────────────┘  │
│                             │
│  7-day free trial.          │
│  Cancel anytime.            │
│                             │
│  Restore Purchase           │
│                             │
└─────────────────────────────┘
```

---

### FLOW 9: SUCCESS / CONFIRMATION STATES

---

#### Screen 9.1: Item Added Successfully

```
┌─────────────────────────────┐
│                             │
│                             │
│                             │
│         [✓ Animated         │
│          Checkmark]         │
│                             │
│      Item Added!            │
│                             │
│  Samsung French Door        │
│  Refrigerator               │
│                             │
│  Warranty expires            │
│  January 15, 2025           │
│                             │
│  We'll remind you before    │
│  it expires.                │
│                             │
│                             │
│  [ View Item ]              │
│                             │
│  [ Add Another ]            │
│                             │
│  [ Go to Dashboard ]        │
│                             │
└─────────────────────────────┘
```

---

### FLOW 10: ERROR STATES

---

#### Error 10.1: Receipt Scan Failed

```
┌─────────────────────────────┐
│                             │
│                             │
│  ┌───────────────────────┐  │
│  │                       │  │
│  │  [Blurry receipt      │  │
│  │   image with red      │  │
│  │   overlay]            │  │
│  │                       │  │
│  └───────────────────────┘  │
│                             │
│  Couldn't read this receipt │
│                             │
│  This can happen if the     │
│  image is blurry, the       │
│  receipt is faded, or the   │
│  lighting is poor.          │
│                             │
│  [ 📷 Try Again ]           │
│                             │
│  [ ✏️ Enter Manually ]       │
│                             │
└─────────────────────────────┘
```

- Always offer manual entry as fallback
- No dead ends

---

#### Error 10.2: Barcode Not Found

```
┌─────────────────────────────┐
│                             │
│  ┌───────────────────────┐  │
│  │  [Barcode image]      │  │
│  └───────────────────────┘  │
│                             │
│  Product not found          │
│                             │
│  We couldn't find this      │
│  barcode in our database.   │
│  This happens with some     │
│  older or specialty items.  │
│                             │
│  [ 🔄 Scan Again ]          │
│                             │
│  [ ✏️ Enter Manually ]       │
│                             │
└─────────────────────────────┘
```

---

#### Error 10.3: Offline — Feature Unavailable

```
┌─────────────────────────────┐
│                             │
│  ┌───────────────────────┐  │
│  │  📡 No Connection      │  │
│  │                        │  │
│  │  Receipt scanning      │  │
│  │  needs an internet     │  │
│  │  connection.           │  │
│  │                        │  │
│  │  You can still add     │  │
│  │  items manually or     │  │
│  │  with Quick-Add.       │  │
│  │                        │  │
│  │  [ ✏️ Add Manually ]    │  │
│  │  [ Quick-Add → ]       │  │
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

- Shown as a bottom sheet overlay, not a full screen block
- Always offers alternatives

---

#### Error 10.4: Sign-Up / Auth Failed

```
┌─────────────────────────────┐
│                             │
│  Something went wrong       │
│                             │
│  We couldn't create your    │
│  account. Please check      │
│  your connection and try    │
│  again.                     │
│                             │
│  Error: {specific_message}  │
│                             │
│  [ Try Again ]              │
│                             │
│  [ Try a Different Method ] │
│                             │
└─────────────────────────────┘
```

- Shows specific error message (email taken, network error, etc.)
- Offers alternative auth method

---

#### Error 10.5: Item Limit Reached (Free Plan)

```
┌─────────────────────────────┐
│                             │
│  You've reached 25 items    │
│                             │
│  The free plan supports     │
│  up to 25 items. Upgrade    │
│  to Premium for unlimited   │
│  tracking.                  │
│                             │
│  [ Upgrade to Premium ]     │
│                             │
│  [ Maybe Later ]            │
│                             │
│  Tip: You can archive old   │
│  items to free up space.    │
│                             │
└─────────────────────────────┘
```

- Offers upgrade but also gives a free workaround (archive)
- Not aggressive — the user already has 25 items, they're invested

---

## Data Models

---

### User
```
user {
  id:               UUID (PK)
  email:            string
  full_name:        string
  avatar_url:       string | null
  auth_provider:    "email" | "google" | "apple"
  plan:             "free" | "premium"
  plan_expires_at:  timestamp | null
  referred_by:      UUID | null → referral_partner.id
  referral_code:    string | null (user's own invite code)
  created_at:       timestamp
  updated_at:       timestamp
}
```

### Home / Property
```
home {
  id:               UUID (PK)
  user_id:          UUID (FK → user.id)
  name:             string ("Our House")
  address:          string | null
  city:             string | null
  state:            string | null
  zip:              string | null
  home_type:        "house" | "condo" | "apartment" | "townhouse" | "other"
  move_in_date:     date | null
  created_at:       timestamp
  updated_at:       timestamp
}
```

### Item
```
item {
  id:               UUID (PK)
  home_id:          UUID (FK → home.id)
  user_id:          UUID (FK → user.id)

  -- Product Info --
  name:             string ("Samsung French Door Refrigerator")
  brand:            string | null ("Samsung")
  model_number:     string | null ("RF28R7551SR")
  serial_number:    string | null
  category:         enum (see below)
  room:             enum | null (see below) -- NULLABLE: not all items belong to a room
  product_image_url: string | null
  barcode:          string | null (UPC code)

  -- Purchase Info --
  purchase_date:    date
  store:            string | null ("Best Buy")
  price:            decimal | null

  -- Warranty Info --
  warranty_months:  integer (duration in months)
  warranty_end_date: date (computed: purchase_date + warranty_months)
  warranty_type:    "manufacturer" | "extended" | "store" | "home_warranty"
  warranty_provider: string | null ("Samsung")
  warranty_status:  computed → "active" | "expiring" | "expired"
                    (expiring = within 90 days of end_date)

  -- Meta --
  notes:            text | null
  is_archived:      boolean (default false)
  added_via:        "quick_add" | "receipt_scan" | "barcode_scan" | "manual" | "bulk_setup"
  created_at:       timestamp
  updated_at:       timestamp
}
```

**v4 change:** `room` is now **nullable**. Items like roofing, windows, flooring,
or furniture don't logically belong to a single room. Items with `room: null`
appear under a "GENERAL" section in the Items list.

**v5 clarification:** `is_archived` items do **NOT** count toward the free plan
25-item limit. Archiving genuinely frees up space. This makes the archive
workaround in error 10.5 actually useful.

### Category Enum
```
category:
  "refrigerator" | "dishwasher" | "washer" | "dryer" |
  "oven_range" | "microwave" | "garbage_disposal" | "range_hood" |
  "hvac" | "water_heater" | "furnace" | "water_softener" | "sump_pump" |
  "tv" | "computer" | "smart_home" |
  "roofing" | "windows" | "doors" | "flooring" |
  "plumbing" | "electrical" |
  "furniture" | "other"
```

### Room Enum
```
room (nullable):
  null | "kitchen" | "bathroom" | "master_bedroom" | "bedroom" |
  "living_room" | "dining_room" | "laundry" |
  "garage" | "basement" | "attic" |
  "outdoor" | "hvac_utility" | "office" | "other"
```

**v4 change:** Room is now explicitly nullable. Removed the need for a "general"
catch-all value — null is cleaner and more honest. In the UI, items with
`room: null` are grouped under "GENERAL" heading.

### Category Defaults
```
category_defaults {
  "refrigerator":     { room: "kitchen",      warranty_months: 12, icon: "🧊" }
  "dishwasher":       { room: "kitchen",      warranty_months: 12, icon: "🍽️" }
  "oven_range":       { room: "kitchen",      warranty_months: 12, icon: "🔥" }
  "microwave":        { room: "kitchen",      warranty_months: 12, icon: "📡" }
  "garbage_disposal": { room: "kitchen",      warranty_months: 12, icon: "♻️" }
  "range_hood":       { room: "kitchen",      warranty_months: 12, icon: "🌬️" }
  "washer":           { room: "laundry",      warranty_months: 12, icon: "👕" }
  "dryer":            { room: "laundry",      warranty_months: 12, icon: "💨" }
  "hvac":             { room: "hvac_utility", warranty_months: 60, icon: "❄️" }
  "furnace":          { room: "hvac_utility", warranty_months: 60, icon: "🔥" }
  "water_heater":     { room: "hvac_utility", warranty_months: 72, icon: "🚿" }
  "water_softener":   { room: "hvac_utility", warranty_months: 60, icon: "💧" }
  "sump_pump":        { room: "basement",     warranty_months: 36, icon: "🌊" }
  "tv":               { room: "living_room",  warranty_months: 12, icon: "📺" }
  "roofing":          { room: null,           warranty_months: 120, icon: "🏠" }
  "windows":          { room: null,           warranty_months: 120, icon: "🪟" }
  "doors":            { room: null,           warranty_months: 60,  icon: "🚪" }
  "flooring":         { room: null,           warranty_months: 60,  icon: "🟫" }
  "furniture":        { room: null,           warranty_months: 12,  icon: "🪑" }
  "plumbing":         { room: null,           warranty_months: 12,  icon: "🔧" }
  "electrical":       { room: null,           warranty_months: 12,  icon: "⚡" }
}
```

**v4 change:** Added defaults for roofing, windows, doors, flooring, furniture,
plumbing, electrical — all with `room: null` since they don't belong to a
single room.

### Brand Suggestions
```
brand_suggestions {
  "refrigerator": ["Samsung", "LG", "GE", "Whirlpool", "Frigidaire", "KitchenAid", "Bosch", "Maytag"]
  "dishwasher":   ["Bosch", "Samsung", "LG", "GE", "Whirlpool", "KitchenAid", "Maytag", "Frigidaire"]
  "washer":       ["Samsung", "LG", "Whirlpool", "Maytag", "GE", "Bosch", "Speed Queen"]
  "dryer":        ["Samsung", "LG", "Whirlpool", "Maytag", "GE", "Bosch", "Speed Queen"]
  "hvac":         ["Carrier", "Trane", "Lennox", "Goodman", "Rheem", "York", "Daikin", "American Standard"]
  "water_heater": ["Rheem", "AO Smith", "Bradford White", "Rinnai", "Navien", "Noritz"]
  "oven_range":   ["GE", "Samsung", "LG", "Whirlpool", "KitchenAid", "Frigidaire", "Bosch", "Wolf"]
  "microwave":    ["GE", "Samsung", "LG", "Whirlpool", "Panasonic", "Frigidaire"]
  "roofing":      ["GAF", "Owens Corning", "CertainTeed", "Tamko", "Atlas"]
  "windows":      ["Andersen", "Pella", "Marvin", "Milgard", "Jeld-Wen"]
  "flooring":     ["Shaw", "Mohawk", "Armstrong", "Pergo", "Bruce"]
}
```

### Document
```
document {
  id:               UUID (PK)
  item_id:          UUID (FK → item.id)
  user_id:          UUID (FK → user.id)
  type:             "receipt" | "warranty_card" | "manual" | "invoice" | "other"
  file_url:         string (Supabase Storage URL)
  file_name:        string
  file_size:        integer (bytes)
  mime_type:        string ("image/jpeg", "application/pdf")
  thumbnail_url:    string | null
  created_at:       timestamp
}
```

### Notification
```
notification {
  id:               UUID (PK)
  user_id:          UUID (FK → user.id)
  item_id:          UUID (FK → item.id) | null
  type:             "warranty_expiring" | "warranty_expired" |
                    "item_added" | "warranty_extended" |
                    "tip" | "system"
  title:            string
  body:             string
  is_read:          boolean (default false)
  action_type:      "view_item" | "get_protection" | "find_repair" | null
  action_data:      jsonb | null
  scheduled_at:     timestamp
  sent_at:          timestamp | null
  created_at:       timestamp
}
```

**v4 change:** `action_type` value changed from "extend_warranty" to
"get_protection" to match unified CTA language.

### Referral Partner
```
referral_partner {
  id:               UUID (PK)
  email:            string
  full_name:        string
  company_name:     string | null
  phone:            string | null
  avatar_url:       string | null
  partner_type:     "realtor" | "builder" | "other"
  referral_code:    string (unique, e.g. "JANE-SMITH-2024")
  stripe_account_id: string | null
  is_active:        boolean (default true)
  created_at:       timestamp
}
```

### Referral
```
referral {
  id:               UUID (PK)
  partner_id:       UUID (FK → referral_partner.id)
  user_id:          UUID (FK → user.id)
  source:           "realtor" | "builder" | "user_invite"
  created_at:       timestamp
}
```

### Affiliate Conversion
```
affiliate_conversion {
  id:               UUID (PK)
  user_id:          UUID (FK → user.id)
  item_id:          UUID (FK → item.id) | null
  partner_id:       UUID | null (FK → referral_partner.id)
  type:             "extended_warranty" | "repair_referral" | "premium_sub"
  provider:         string ("Asurion", "OnPoint", "Angi")
  revenue:          decimal
  commission:       decimal
  partner_commission: decimal
  status:           "pending" | "confirmed" | "paid"
  created_at:       timestamp
}
```

### Notification Preferences
```
notification_preferences {
  user_id:                  UUID (PK, FK → user.id)
  reminders_enabled:        boolean (default true)
  first_reminder_days:      integer (default 30) -- 90, 60, 30, 14, or 7
  reminder_time:            time (default "09:00")
  warranty_offers_enabled:  boolean (default true)
  tips_enabled:             boolean (default true)
  push_enabled:             boolean (default true)
  email_enabled:            boolean (default false)
}
```

### Offline Queue
```
offline_queue {
  id:               UUID (PK)
  user_id:          UUID
  action:           "create_item" | "update_item" | "delete_item" |
                    "create_document" | "update_preferences"
  payload:          jsonb
  status:           "pending" | "synced" | "failed"
  created_at:       timestamp
  synced_at:        timestamp | null
  retry_count:      integer (default 0)
}
```

---

## Screen Flow Map (v5)

```
SPLASH
  │
  ▼
WELCOME + SIGN UP (single screen)
  │
  ├── Apple/Google one-tap ──┐
  └── Email sign-up ─────────┤
                              │
                              ▼
                    WHAT DO YOU WANT TO DO?
                     │          │         │          │
            ┌────────┘          │         │          └──────┐
            ▼                   ▼         ▼                 ▼
     NEW HOME BULK ADD    SCAN RECEIPT  ADD MANUALLY   "I'LL EXPLORE"
     │                    │             │                    │
     ▼                    ▼             ▼                    ▼
     NAME YOUR HOME    OCR FLOW    MANUAL FORM        EMPTY DASHBOARD
     │                    │             │               (with CTA)
     ▼                    ▼             ▼                    │
     KITCHEN ──►       CONFIRM     ITEM ADDED               │
     LAUNDRY ──►       │                │                    │
     HVAC ──►          ▼                │                    │
     ... ──►        ITEM ADDED          │                    │
     (← Back preserves  │              │                    │
      all room state)    │              │                    │
     │                   │              │                    │
     ▼                   │              │                    │
     COMPLETE            │              │                    │
     │                   │              │                    │
     └──────────┬────────┘──────────────┘────────────────────┘
                │
                ▼
         ┌── HOME TAB (Dashboard) ─────── ITEMS TAB ──┐
         │                                             │
         │   ⚙️ → SETTINGS (7.1)                         │
         │   │     │                                   │
         │   │     ├── Notifications (7.2)             │
         │   │     ├── My Homes → Home Detail (7.3)    │
         │   │     │    └── Delete Home → Confirm      │
         │   │     ├── Archived Items (7.4)            │
         │   │     │    └── Restore / Delete perm.     │
         │   │     ├── Family Sharing (Premium)        │
         │   │     ├── Export Data (Premium)            │
         │   │     └── Support / Legal                 │
         │   │                                         │
         │   Summary Card                   Item List  │
         │   Needs Attention (max 3)        (search +  │
         │    └── "View all →"               filter)   │
         │        (pre-filters Items)        │         │
         │   Tip Card                        ▼         │
         │                              ITEM DETAIL    │
         │                               │  │  │  │   │
         │                               │  │  │  └── EDIT ITEM (6.4)
         │                               │  │  └── Docs → Viewer
         │                               │  └── Delete → CONFIRM (4.2)
         │                               │
         │                               ├── Search {Brand} Support
         │                               ├── Share Claim Info (6.3)
         │                               │    └── Copy / Email / Text / PDF (free)
         │                               ├── Get Protection → OFFER (8.1)
         │                               └── Find Repair → REPAIR (8.2)
         │
         └── FAB [+] → ADD ITEM SHEET (5.1)
                        │
                ┌───────┼────────┬────────┐
                │       │        │        │
             Quick    Scan     Manual   Scan
              Add     Rcpt     Entry   Barcode
             (~80%)  (~15%)   (~3%)    (~2%)
                │       │        │        │
                ▼       ▼        ▼        ▼
            QUICK    OCR      FULL    BARCODE
            FORM     FLOW     FORM    LOOKUP
                │       │        │        │
                └───┬───┘────────┘────────┘
                    ▼
               ITEM ADDED (9.1)
               (success)

         PREMIUM UPGRADE (8.3) — modal, triggered from anywhere

ERROR STATES (overlays/dialogs, not separate screens):
  • Receipt scan failed → Retry / Manual entry
  • Barcode not found → Retry / Manual entry
  • Offline + scan → Manual entry / Quick-Add
  • Auth failed → Retry / Alt method
  • Item limit → Upgrade / Archive
  • Delete item → Confirmation dialog (4.2)
  • Delete home → Confirmation dialog (warns about item deletion)
  • Cancel bulk-add with items → Confirmation dialog
  • Cancel edit with changes → Confirmation dialog
  • Remove document → Confirmation dialog

PERMISSION PROMPTS (contextual, never on launch):
  • Camera → first Scan Receipt / Scan Barcode tap
  • Push Notifications → first Item Added success screen
  • Location → first Find Repair tap (fallback: zip code entry)
```

---

## Push Notification Templates

### First Reminder (user-configured: 90/60/30/14/7 days)
**Title:** Heads up — {item_name} warranty expiring
**Body:** Your warranty expires in {days} days ({expiry_date}). Tap to review your options.

### 7 Days Before (always fires)
**Title:** {item_name} warranty expires next week
**Body:** Only 7 days left. Tap to get protection or prepare a claim.

### 1 Day Before (always fires)
**Title:** Last day — {item_name} warranty ends tomorrow
**Body:** Final reminder. Tap to take action before coverage ends.

### On Expiry Day
**Title:** {item_name} warranty has expired
**Body:** Coverage ended today. You can still get protection or find a repair tech.

---

## Offline Mode Design

### Core Principle
Local-first. All data stored on device via `drift` (SQLite), synced to Supabase when connected.

### Works Offline
- View all items, details, documents (cached locally via `drift`)
- Add items (Quick-Add, Manual Entry) — writes to local DB immediately
- Edit existing items
- View warranty countdowns (computed from local `purchase_date` + `warranty_months`)

### Requires Connection
- Receipt OCR (Mindee API via HTTP)
- Barcode lookup (UPC API via HTTP)
- Warranty offers (affiliate API)
- Repair search (Angi API)
- Account creation / sign-in (Supabase Auth)
- Document upload (Supabase Storage)

### Sync Behavior
```
OFFLINE → drift (local SQLite) + offline_queue table
CONNECTION RESTORED → connectivity_plus detects → queue processes in order → Supabase upserts
DONE → SnackBar: "All changes synced ✓"
```

### Implementation Notes
- `drift` handles local DB with typed Dart models matching our data models
- `connectivity_plus` stream triggers sync when connection restores
- Offline queue is a local `drift` table (mirrors the `offline_queue` data model)
- Documents cached via Flutter's cache directory (`path_provider`) for offline viewing
- Supabase Realtime subscription resumes automatically on reconnect

### Visual Indicators
- Top banner: "You're offline. Changes will sync when connected."
- Unsynced items: small cloud ↑ icon until synced
- Never block core features with "no connection" modals

---

## Animations & Micro-Interactions

1. **Receipt Scan** — Blue laser line scanning down the receipt image
2. **Item Added** — Lottie checkmark + confetti
3. **Bulk Add Complete** — Lottie house + checkmark + confetti
4. **Tab Switch** — Subtle crossfade
5. **Card Press** — Scale 0.98 + haptic feedback
6. **FAB Press** — Rotate "+" to "×"
7. **Pull to Refresh** — Shield icon fills up
8. **Swipe to Archive/Delete** — Archive: blue background + archive icon. Delete: red background + trash icon.
9. **Number Counters** — Animated count-up on dashboard
10. **Quick-Add Grid** — Icon scales up + blue border on select
11. **Offline Sync** — Cloud icon with spinning arrow
12. **Status Badge** — Subtle pulse on 🟡 expiring items
13. **Skeleton Loading** — Gray blocks pulsing opacity 0.3 → 0.7 → 0.3, 200ms fade to real content
14. **Accordion Expand/Collapse** — 250ms ease-out height animation, ▾ chevron rotates to ▴

---

## Empty States

### Dashboard — No Items
```
[Illustration: Empty box with sparkles]

Your vault is empty

Add your first item to start
tracking your warranties.

[ + Add Your First Item ]

Just moved in?
[ Set Up Your Home ]
```

### Dashboard — All Clear
```
All clear! No warranties need
your attention right now. ✓
```
(Inline text, not full screen)

### Items List — No Results
```
No items match "{query}"
Try a different search term.
```

### Items List — Empty (no items at all)
```
[Illustration: Empty clipboard]

No items yet

Tap [+] to add your first item,
or set up your home to get
started quickly.
```

### Archived Items — Empty
```
No archived items.

When you archive items, they'll
appear here. You can restore
them anytime.
```

---

## Accessibility

- 44x44pt minimum touch targets
- Status uses icon + label + color (never color alone)
- Dynamic Type / font scaling support
- VoiceOver / TalkBack labels on all elements
- 4.5:1 minimum contrast ratio
- Reduce Motion support (disables Lottie, skeleton pulse, counter animations)
- Quick-Add grid has text labels (not icon-only)
- Delete actions require explicit confirmation (no undo-toast pattern for destructive ops)
- Swipe actions also available via ⋮ menu for users who can't swipe

---

## Tech Stack

### Framework: Flutter + Dart
- **Why Flutter:** Pixel-perfect control over our dark premium UI on both platforms.
  Custom animations (accordions, skeleton loading, Lottie celebrations) are built-in,
  not bolt-on. Single codebase, single render engine — what we design is what ships.
- **Min SDK:** Flutter 3.x, Dart 3.x

### Backend: Supabase
- **Auth:** `supabase_flutter` — Apple, Google, Email sign-in
- **Database:** PostgreSQL via Supabase (Row Level Security for multi-tenant data)
- **Storage:** Supabase Storage — receipt photos, warranty docs, product images
- **Edge Functions:** Deno-based — affiliate API calls, OCR proxy, push notification scheduling
- **Realtime:** Supabase Realtime — family sharing sync (Premium)

### Key Flutter Packages
| Purpose | Package | Notes |
|---|---|---|
| Supabase SDK | `supabase_flutter` | Auth, DB, Storage, Realtime |
| Local Database | `drift` (SQLite) | Typed, reactive, offline-first |
| Local KV Store | `shared_preferences` | Lightweight settings/flags |
| State Management | `riverpod` | Reactive, testable, scalable |
| Navigation | `go_router` | Declarative, deep link support |
| Camera | `camera` | Receipt/barcode capture |
| OCR | Mindee API (via HTTP) | Receipt text extraction (500 free/mo) |
| Barcode | `mobile_scanner` | UPC/EAN barcode scanning |
| Product Lookup | UPCitemdb / Go-UPC API | Barcode → product info |
| Lottie Animations | `lottie` | Success celebrations, scanning animation |
| PDF Generation | `pdf` + `printing` | Single-item claim PDF (free), bulk export (premium) |
| CSV Export | `csv` | Premium bulk inventory export |
| Push Notifications | `firebase_messaging` | FCM for both platforms |
| Local Notifications | `flutter_local_notifications` | Scheduled warranty reminders |
| Deep Links | `app_links` + Firebase Dynamic Links | Realtor/builder referral attribution |
| Image Picker | `image_picker` | Gallery access for receipt/doc upload |
| Connectivity | `connectivity_plus` | Online/offline detection for sync |
| Secure Storage | `flutter_secure_storage` | Auth tokens, sensitive data |
| Haptics | `HapticFeedback` (built-in) | Card press, error feedback |
| Biometric Auth | `local_auth` | Face ID / Touch ID / Fingerprint app lock |

### Web Dashboard (Referral Partners)
- **Next.js** — Realtor/builder dashboard for tracking referrals and commissions
- Separate project, not part of the Flutter app

### Platform Notes

#### iOS
- Cupertino-style bottom sheets via `showModalBottomSheet` with `useSafeArea`
- SF Pro font via `google_fonts` package (maps to system font on iOS)
- `HapticFeedback.mediumImpact()` on card press, `.lightImpact()` on toggles
- Face ID / Touch ID via `local_auth`
- Minimum deployment target: iOS 14+

#### Android
- Predictive back gesture support (Flutter 3.x built-in)
- Separate notification channels via `flutter_local_notifications`: "Warranty Reminders" + "Offers & Tips"
- Biometric lock via `local_auth`
- Material You dynamic color extraction (optional, v2+)
- Minimum API level: 23 (Android 6.0)

---

## Free vs Premium

| Feature | Free | Premium ($2.99/mo · $24.99/yr) |
|---|---|---|
| Items tracked | 25 | Unlimited |
| Manual entry | ✓ | ✓ |
| Quick-Add | ✓ | ✓ |
| Bulk Home Setup | ✓ | ✓ |
| Receipt scanning | ✓ (unlimited) | ✓ |
| Barcode scanning | ✓ | ✓ |
| Push reminders | ✓ | ✓ |
| Cloud sync | ✓ | ✓ |
| Offline mode | ✓ | ✓ |
| Share Claim Info | ✓ (incl. single-item PDF) | ✓ |
| Document storage | 200 MB | 2 GB |
| Family sharing | — | Up to 5 members |
| Multiple properties | — | Unlimited |
| Bulk export (PDF / CSV) | — | ✓ |
| Priority support | — | ✓ |

**Design principle:** Core value is free. Premium gates scale and convenience.
Receipt scanning is free because it feeds the affiliate revenue engine.

**PDF clarification:**
- **Free:** Single-item claim PDF via "Share Claim Info" → "Save as PDF". This is
  part of the core claim support flow. Users need this when filing a claim.
- **Premium:** "Export Data" in Settings → generates a full inventory PDF report
  or CSV spreadsheet with all items, all details. This is a bulk convenience feature.

---

## Referral Attribution (Deep Links)

Realtors/builders share a link, not a code:
```
https://havenkeep.app/r/JANE-SMITH
```

- Opens app (or App Store if not installed)
- Referral partner auto-attached to user's account
- No manual code entry required
- Deep link preserved through App Store install (deferred deep linking via Branch or Firebase Dynamic Links)
- Partner's name shown on a subtle "Referred by Jane Smith Realty" badge in Settings

---

## Permission Requests

Permissions should be asked **in context** — at the moment the user
takes an action that requires the permission. Never on app launch.

### Camera Permission
- **When:** First tap on "Scan Receipt" or "Scan Barcode" (Screen 5.3)
- **Why it works:** User just chose to scan something — camera access is obvious
- **If denied:** Show inline message: "Camera access is needed to scan receipts.
  You can enable it in Settings." + [Open Settings] [Enter Manually] buttons
- **Grant rate expectation:** 90%+ (high context, clear intent)

### Push Notification Permission
- **When:** On the Item Added success screen (Screen 9.1) after the user's
  **first** item is saved. Show a pre-permission prompt before the OS dialog:
  ```
  ┌───────────────────────┐
  │                       │
  │  🔔 Stay protected     │
  │                       │
  │  We'll remind you     │
  │  before your warranty │
  │  expires so you never │
  │  miss a claim.        │
  │                       │
  │  [ Enable Reminders ] │
  │  [ Not Now ]          │
  │                       │
  └───────────────────────┘
  ```
- **"Enable Reminders"** → triggers the OS permission dialog
- **"Not Now"** → dismisses, user can enable later in Settings > Notifications
- **Why it works:** User just added an item and sees "We'll remind you before
  it expires." Maximum motivation to say yes.
- **If OS permission denied:** Reminders silently disabled. Subtle banner in
  Notification Preferences: "Notifications are disabled in your device settings."
  + [Open Settings] button
- **Grant rate expectation:** 70-80% (pre-permission + contextual timing)

### Location Permission
- **When:** First tap on "Find Repair" (Screen 8.2)
- **Why it works:** User wants repair techs "near you" — location is obvious
- **If denied:** Show zip code input field instead of GPS location:
  "Enter your zip code to find repair techs nearby." [Zip field] [Search]
- **Grant rate expectation:** 60-70% (less obvious value than camera/notifications)

### Permission Principles
- Never ask for multiple permissions at once
- Never ask on first launch or onboarding
- Always provide a fallback if permission is denied
- Use pre-permission prompts (our UI) before OS dialogs — lets us re-ask later
  if the user taps "Not Now" (OS permission can only be asked once natively)

---

## Form Validation

### Validation Rules

| Field | Rule | Error Message |
|---|---|---|
| Brand (Quick-Add) | Required | "Select a brand" |
| Brand "Other..." | Must type a name | "Enter the brand name" |
| Purchase Date | Required, not in future | "Select a purchase date" / "Date can't be in the future" |
| Warranty Duration | Required, > 0 | "Enter warranty duration" |
| Product Name (Manual) | Required | "Enter a product name" |
| Email (sign-up) | Valid email format | "Enter a valid email address" |
| Password (sign-up) | Min 8 characters | "Password must be at least 8 characters" |
| Full Name (sign-up) | Required | "Enter your name" |
| Home Name (bulk-add) | Required | "Give your home a name" |

### Validation Behavior
- **On submit:** Validate all fields. If errors exist:
  1. Scroll to the first field with an error
  2. Red border (#EF4444) on the field
  3. Inline error text below the field in red, 12px
  4. Haptic feedback (`HapticFeedback.lightImpact()`) on both platforms
- **On field blur:** Validate that individual field immediately (real-time feedback)
- **On field focus (after error):** Clear the red border and error text as user starts typing
- **Required fields:** Marked with * in the label (already done throughout spec)
- **Disabled save button:** "Save Item" / "Save Changes" button stays visually muted
  (opacity 0.5) until all required fields are filled. Tapping a disabled button
  triggers the validation scroll behavior above.

### Edge Cases
- **Purchase date in the future:** Some users buy appliances before moving in.
  Allow dates up to 30 days in the future with a warning (not an error):
  "This date is in the future — is that correct?" (amber, not red)
- **Warranty duration 0:** Reject — no point tracking a 0-duration warranty
- **Duplicate items:** No validation. Users may have two of the same appliance
  (e.g., two bathrooms with the same faucet)

---

## v2+ Deferred Features

- Service History / Repair Log per item
- Standalone Document Vault screen
- Warranty Health charts and analytics
- Weekly email digest
- Faceted search filters
- Warranty document OCR
- Builder bulk CSV upload / API
- White-label for builders
- Manufacturer warranty database (auto-suggest duration)
- Home maintenance reminders
- In-app chat with providers
- Claim Assistant with curated support contacts per brand
- Notification inbox screen (if push + dashboard proves insufficient)
- Invite Friends referral program (user-to-user referrals, "give 1 mo Premium")
- Multi-item receipt batch add (select all items at once from OCR results)
