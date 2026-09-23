# VCarve Cabinet Gadget — Product & Business Plan

> Plan for building and selling a **parametric cabinet-builder plugin (Vectric
> Gadget)** for VCarve Pro / Aspire / Cut2D Pro.
> Goals from the owner: **UNIVERSAL** (works for any shop) · **EDITABLE**
> (users can customize everything) · **FAMILIAR** (easy for VCarve users).
> Planning document only — no code written yet.
>
> **Status: Phase 0 COMPLETE (2026-09-23)** — team, market, pricing and name
> all locked. Product name: **Najjar Pro** (نجّار). See §11.

---

## 1. Executive summary

We build a commercial Vectric Gadget — "the cabinet builder that adapts to
your shop". The user types cabinet dimensions and options; the gadget
generates every panel with all machining (cut outlines, shelf-pin rows,
connector drilling, hinge cups, drawer-slide holes, LED grooves, cabinet
marks, labels) on **named layers**, plus a **BOM**, and can even apply
**toolpath templates and post G-code** automatically.

- **Platform:** Vectric's official Gadget system (Lua add-ins that run inside
  Aspire, VCarve Pro and Cut2D Pro; they can create geometry *and* toolpaths).
- **Proof the market pays:** Klemar CNC sells exactly this type of system for
  the Hebrew market; GKWare sells Cab Maker for SketchUUp (~$60 class);
  Fusion cabinet generators sell on Etsy; Jimandi's "Easy" gadget line has
  1,000–3,500 downloads per gadget.
- **Our edge:** fully **user-editable** hardware/rules library (open data
  files, not hard-coded), **Arabic + Hebrew + English** UI (Arabic is an
  untouched market), batch project mode, and an optional **nesting
  companion** (this repo).

---

## 2. Platform facts (verified)

| Fact | Detail |
|---|---|
| What gadgets are | Lua scripts that run inside Aspire, VCarve Pro, Cut2D Pro |
| What they can do | Create/edit **geometry and toolpaths**, layers, dialogs with inputs; preinstalled Vectric gadgets already do "apply toolpath templates to every sheet of a nested job + auto post-process and save machine files" |
| SDK | Free download: gadgets.vectric.com → V12 gadget SDK; docs + sample gadgets (samples ship in source form) |
| Vectric support | **None** for third-party developers — docs and forum only. Budget for self-reliance |
| Install | `Gadgets → Install New Gadget…` — distribution is just a file; no app-store gatekeeper, no approval needed to sell |
| Version support | Decide a minimum (competitors target 11–12). Old versions keep working via Lua compatibility; new Vectric releases need re-testing |
| Trial versions of Vectric apps | Have gadgets disabled — irrelevant for us, but explains why every customer owns a license |
| Localization precedent | Jimandi ships a **Hebrew-menu** gadget — non-Latin UI text works; Arabic must be verified early (spike, §9) |

---

## 3. Market scan

| Player | Platform | Price model | Strengths | Weaknesses we exploit |
|---|---|---|---|---|
| **Klemar Smart Cabinet Builder** | VCarve (Hebrew market) | Commercial, promoted on FB | Full feature set; local market presence | Hebrew-only marketing; not openly editable |
| **Jimandi "Easy Cabinet Maker"** (v18.5) + suite (Drawer, Euro Hinge, System 32, MDF Door) | Vectric 11–12 | Free download (donation-style) | Mature, multi-language, drawings+toolpaths+BOM, face-frame & euro | Free = limited dev pace; hardware options fixed; no nesting; no Arabic; generic "endless options" UX can overwhelm |
| **GKWare Cab Maker** | SketchUp | Paid (~$60 class) | Rich styles, help images per parameter | SketchUp side only — no CAM/toolpath integration |
| **Fusion 360 generators** (Etsy) | Fusion | Cheap one-off | 3D + auto Excel cutlist | No VCarve workflow; hobbyist grade |
| **Pyth​agoras / Cabinet Vision / IMOS** | Standalone CAD/CAM | $$$$ enterprise | Everything | Price and complexity overkill for small shops |

**Positioning statement:**
> For small-to-medium cabinet shops that already own VCarve Pro or Aspire,
> our gadget turns cabinet design into 2 minutes of typing — and unlike free
> gadgets, it adapts to *your* construction method, *your* hardware, and
> *your* language, with paid support and updates.

---

## 4. The three pillars → concrete design

### 4.1 UNIVERSAL — works in any shop

- **All cabinet types:** base, wall, tall, vanity, closet, bookcase; euro
  (frameless) at first, face-frame as an option later.
- **All construction methods** as parameters: top/bottom between sides vs.
  on top of sides; grooved vs. nailed-on back; adjustable vs. fixed shelves;
  toe-kick/plinth or legs.
- **Units:** mm and inch, switchable (US market uses inches).
- **Any material thickness:** per-part override (18 mm sides, 9 mm back…).
- **Hardware library covers systems, not brands:** system-32 shelf pins,
  Cabineo 8/12, confirmat, minifix, cup hinges (35 mm), undermount and
  side-mount slides, LED channel — each a data file users can duplicate and
  edit (§4.2).
- **Batch mode (v2):** a whole kitchen — a list of cabinets — generated in
  one run, with one combined BOM.

### 4.2 EDITABLE — the shop adapts it, not the reverse

Three editable layers, no coding required:

1. **Hardware library — open data files** (`hardware/*.json` in the gadget
   folder): drill diameters, depths, spacing, edge distances, hinge drilling
   patterns. User opens the file (or a built-in editor) and adds their own
   hardware model. *Adding a new hinge brand must never need a code update.*
2. **Cabinet templates** (`templates/*.json`): a shop saves its standard
   cabinet (dimensions, construction method, hardware choices, default
   reveals) and reuses/shares it. Community templates = free marketing.
3. **Defaults & rules:** every dialog field has a "save as my default"
   button; advanced users can override rule values (system-32 first column
   position, drawer gap, hinge count thresholds) in a visible settings file.

Also editable output: layer names/colors configurable to match the shop's
existing toolpath workflow.

### 4.3 FAMILIAR — zero learning curve for VCarve users

- **Native wizard UX:** multi-page dialog exactly like known gadgets
  (dimensions → construction → zones → hardware → output). Every field has a
  tooltip; every page has a context help image (the GKWare trick that users
  love).
- **VCarve vocabulary only:** layers, toolpath templates, sheet, job size —
  never CAD jargon.
- **One-click results:** "Create" draws everything on the familiar layer set
  (`CUT`, `DRILL5_SHELF`, `DRILL_CABINEO`, `DRILL_HINGE`, `DRILL_SLIDE`,
  `LED_GROOVE`, `ETCH` — same convention as our ArtCAM plan). "Create +
  toolpaths" additionally applies the user's toolpath templates per layer and
  can post the G-code, like Vectric's own nesting gadget does.
- **Languages:** English, Hebrew, Arabic UI (RTL) — language files are plain
  JSON; community translations welcome.
- **Teaching content:** short YouTube video per feature page; printable PDF
  cheat-sheet. Video is how gadgets sell (the Jimandi model).

---

## 5. Feature roadmap

| Version | Scope |
|---|---|
| **v0.1 spike (internal)** | SDK installed; "hello cabinet": one box → 6 panels on layers from hardcoded values; verify dialog Arabic/Hebrew text + toolpath API on VCarve Pro & Aspire |
| **v0.5 MVP** | Euro base/wall cabinet: sides/bottom/top/back(grooved+nailed)/shelves/dividers; system-32 + Cabineo + hinge drilling; labels, BOM CSV; mm+inch; EN UI; save/load template |
| **v1.0 LAUNCH** | Zones (shelf rows, drawer stacks), doors & drawer fronts with reveal math, drawer boxes; hardware library as editable JSON with built-in editor; HE + AR UI; toolpath-template automation; trial/licensing; website + docs + videos |
| **v1.x** | Face-frame option; more hardware packs (confirmat, minifix, slides types); batch project mode; part labels with QR codes |
| **v2.0** | Nesting companion (export DXF to this repo's optimizer → nested sheets back into VCarve); auto post-process per sheet; SketchUp/DXF round-trip |

---

## 6. Technical architecture

```
┌───────────────────────── Gadget (Lua) ─────────────────────────┐
│ ui.lua        wizard pages, tooltips, help images, i18n        │
│ spec.lua      load/validate/save cabinet spec + templates      │
│ rules.lua     construction rules → dimensioned panel list      │
│ hardware.lua  load hardware/*.json, place drilling patterns    │
│ geometry.lua  panels → contours, circles, grooves, text labels │
│ layers.lua    configurable layer scheme, drawing into the job  │
│ toolpaths.lua apply user toolpath templates per layer (+post)  │
│ bom.lua       BOM CSV + cut list + labels                      │
│ license.lua   key check / activation                           │
└────────────────────────────────────────────────────────────────┘
         │ data files (user-editable)
         ▼
   hardware/*.json · templates/*.json · lang/*.json · settings.json
```

- **Deterministic core:** same spec → same geometry, golden-file tests in
  CI (the discipline already used in this repo).
- **Cross-check oracle:** the spec schema and rules are mirrored in this
  repo's Python engine plan (`docs/cabinet-builder-plan.md`) — we can
  generate expected part lists in Python and diff against the Lua output in
  tests. One brain, two implementations, zero silent math errors.
- **Version matrix:** test on VCarve Pro + Aspire, versions 11/12 minimum;
  keep a cheap old-version machine or VM.
- **Distribution:** packaged gadget file from our site; e-mail delivery +
  account portal for updates.

---

## 7. Licensing & copy protection (realistic view)

- Gadgets are Lua and **can always be inspected** by a determined user.
  Over-engineering DRM kills development time.
- Recommended scheme:
  1. Per-customer **license key** (name + order number hashed) stored in the
     gadget folder; nag layer + feature caps without it.
  2. Ship core logic as **compiled Lua bytecode** (luac) with a plain-text
     config layer — stops casual copying only, and that's enough.
  3. Real protection = **value, not locks**: frequent updates, template
     library, support, and community behind a paid account.
- Trial: full features but marks output with a "DEMO" etch layer and limits
  projects to 1 cabinet.

## 8. Business model — one-time license + paid packs (DECIDED)

**Base product:** one-time license per seat — **$59–89** (intro **$49–79**),
including 12 months of updates + support. Minor/bugfix updates free forever.
Site-license discount from 3 seats. Regional MENA pricing adjusted to market.

**Paid packs (the growth engine after v1.0):**

| Pack | Price idea | Content |
|---|---|---|
| Hardware Pack | $9–19 | curated brand drilling patterns (Blum / Hettich hinges & slides, Lamello Cabineo, minifix…) |
| Style Pack | $15–29 | face-frame, shaker / raised-panel door styles, closet systems |
| Template Pack | $9–19 | ready-made kitchen / wardrobe / closet template collections |
| **Nesting Companion** | $39–59 | DXF → nesting optimizer → nested sheets back into VCarve — our unique moat; no competitor has this |
| Custom rules | per shop | commissioning a big shop's construction method as a private pack |

| Item | Recommendation |
|---|---|
| Why not free/donation | The free Jimandi suite covers the basics; paid must mean: editable hardware library, AR/HE languages, support, updates, nesting companion |
| Payment | Stripe/PayPal + local options for MENA customers |
| Channels | Product website (najjarpro.com); YouTube tutorial series (Arabic + Hebrew + English — Arabic CNC content is a wide-open niche); Vectric forum gadget section (announce releases, follow rules); Facebook CNC/cabinet groups; local CNC dealers as resellers |
| Support | E-mail + WhatsApp; docs PDF per language; 15-minute onboarding video |

---

## 9. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Arabic/RTL text in gadget dialogs unverified | Week-1 spike; fallback = EN UI + Arabic PDF manual + Arabic video (still a market first) |
| Free competitor (Jimandi) | Compete on editability, languages, support, nesting — not on "it exists" |
| Vectric API changes in v13+ | Version matrix in CI; Lua core isolated from API layer for quick patches |
| Piracy | Light DRM + account-gated updates (§7); price fairly |
| Solo-developer bus factor | Document everything; keep the Python oracle in this repo as reference implementation |
| Vectric policy shift (no approval process today) | Stay on good forum terms; keep customers' e-mails (our own distribution list) |

---

## 10. Immediate next steps (Phase 0 → kickoff)

1. ~~Decide team~~ — **DECIDED**: owner + coding agent, built together step
   by step (agent writes the code, owner tests on real cabinets).
2. **Start the headless Lua core immediately** — `spec.lua`, `rules.lua`,
   `hardware.lua`, `geometry.lua` are pure Lua and unit-testable *without*
   VCarve installed; only the thin Vectric API layer needs the real program.
   Development does not wait for the license.
3. Owner purchases **VCarve Pro** (recommended over Aspire — same gadget API,
   lower price; Aspire only matters if we ever add 3D) — needed by
   integration week.
4. Download the **V12 Gadget SDK** from gadgets.vectric.com and study the
   sample gadgets (they ship as readable source).
5. **Spike week** (once the license is in): dialog with AR/HE/EN labels →
   one cabinet → panels on layers → one toolpath template applied. This
   validates every remaining unknown.
6. Lock the **spec schema v1** (reuse `docs/cabinet-builder-plan.md` §5).
7. ~~Name + domain~~ — **DECIDED: Najjar Pro**. Register `najjarpro.com`
   (whois-confirm first), open the YouTube channel early, trilingual
   (`#NajjarPro`).

## 11. Decisions log (Phase 0 — locked 2026-09-23)

| # | Question | Decision |
|---|---|---|
| 1 | Developer | **Owner + coding agent** — built together, step by step |
| 2 | First market | **Both** — trilingual (EN / HE / AR) from day one; local MENA beta first, global launch at v1.0 |
| 3 | Vectric license | Not yet — owner will purchase **VCarve Pro** (recommended; same gadget API as Aspire). Headless core development starts immediately regardless |
| 4 | Pricing | **One-time license + paid packs** (§8) |
| 5 | Product name | **Najjar Pro** (نجّار) — locked 2026-09-23 · tagline: "Every shop has a carpenter. Now it has Najjar Pro." |

### 11.1 Name shortlist (proposed)

Conflict check 2026-09: **CabForge** (CabForge Systems), **CabBuilder**
(cabbuildersoftware.com) and **CabWriter** (SketchUp) are taken — dropped.

| Candidate | Meaning / story | EN / HE / AR | Status |
|---|---|---|---|
| **Najjar Pro** (نجار) | "the carpenter" — by carpenters, for carpenters; surname-brand like Ferrari | ✅ نجّار / נג'אר / "Najjar" | ⭐ agent's recommendation — final clearance pending |
| **Khazana Builder** (خزانة) | literally "cabinet" + hidden meaning "treasure" | ✅ warm locally, exotic globally | clear in the CNC niche; common word elsewhere |
| **MillCab** | mill (CNC) + cabinet — instantly understood | ✅ EN-first, transliterates fine | likely clear — verify |
| **PanelForge** | "forged panels" — CNC power feel | ✅ EN-first | verify proximity to CabForge Systems |
| **CabMind** | "you plan, it thinks" — the smart angle | ✅ | verify |

### 11.2 Round 2 (more options requested 2026-09-23)

| Candidate | Meaning / story | EN / HE / AR | Status |
|---|---|---|---|
| **Kerf** | the width of the cut — pure CNC vocabulary; sharp, short, professional | ✅ | no conflict found in our niche — verify |
| **Dado** | the groove that holds the back panel — warm joinery word, friendly sound | ✅ | no conflict found — verify |
| **Benna** (بنى) | Arabic "he built" (root b-n-y) — brandable like a friendly name | ✅ بنى / בֶּנָּה | verify |
| **Hirfa** (حرفة) | "the craft / trade" in Arabic — the whole philosophy in one word | ✅ | verify |
| **NagarPro** (נגר) | Hebrew "carpenter" — cognate of Najjar (same Semitic root *n-g-r*): one name that bridges both languages | ✅ | verify |
| **CabnetIQ** | cabinet + IQ — modern, techy, SaaS-feel | ✅ | verify |

Dropped after conflict check: **Tenon** (TenonCam — nested-based cabinet
manufacturing system, same niche).

Final gate before committing a name: domain availability, Vectric gadget
listing search, quick trademark check.

### 11.3 Name strategy analysis — search & trending (owner asked: "which is best and most familiar in search and will trend?")

Discovery for a Vectric gadget happens on **YouTube, Facebook groups and the
Vectric forum** — not Google. So a name must be: (1) sayable out loud in a
video, (2) typeable correctly after only *hearing* it, (3) ownable as a
search string once content exists, (4) instantly meaningful, (5) work in
EN/HE/AR.

| Name | Owns its search results | Instant meaning | Sayable & typeable | EN/HE/AR | Total /20 |
|---|---|---|---|---|---|
| **Najjar Pro** | 4 — "Najjar" alone is a crowded surname, but "Najjar Pro" is an ownable compound | 5 locally, 3 globally | 5 — heard once, spelled right | 5 — نجّار / נג'אר / Najjar | **17+** |
| **CabnetIQ** | 5 — unique string, zero competition | 4 — decodes as cabinet+IQ | 3 — heard as "cabinet IQ"?? spelling risk | 4 | 16 |
| **Kerf** | 2 — dictionary word + KerfCase compete forever | 5 for CNC people | 5 | 3 | 15 |
| MillCab | 4 | 4 | 4 | 3 | 15 |
| Khazana Builder | 3 — "khazana" is a common word (jewelry etc.) | 4 locally | 4 | 4 | 15 |

**Verdict: 🥇 Najjar Pro · 🥈 CabnetIQ · 🥉 Kerf**

Why Najjar Pro trends best: it carries a **story** ("the cabinet app called
The Carpenter") — stories get repeated, words don't. In the local market the
name itself is the marketing (برنامج النجار); globally it's an exotic but
easy surname-brand (the Ferrari effect). CabnetIQ is the safer pure-SEO play
but loses warmth and has a spelling-when-heard problem. Kerf is the most
familiar word to CNC people but can never be *owned* in search.

Domain check 2026-09-23: `najjarpro.com` and `cabnetiq.com` both show
nothing hosted — likely available; confirm with whois before purchase.
Marketing kit for the winner: `#NajjarPro` hashtag, tagline
"Every shop has a carpenter. Now it has Najjar Pro." / Arabic:
"كل ورشة عندها نجّار — هلق كمان عندها Najjar Pro".
