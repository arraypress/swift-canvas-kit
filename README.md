# Swift Canvas Kit

The shared canvas engine under the visual kits — model, text, renderer,
exporters, audio. **Headless**: no UI frameworks, no network, no AI. The
whole pipeline — deck → rendered slides → exported files — runs in a unit
test or a command-line tool.

```
deck (Codable value) → SlideRenderer → PNG set / stitched MP4
```

## Who sits on it

[swift-screenshot-kit](../swift-screenshot-kit) (App Store screenshots:
device frames, bezel masks, screenshot sets) and
[swift-slide-kit](../swift-slide-kit) (TikTok / Instagram carousels and
reels: 432 templates, brands, the `reel` CLI). Both were born as one
codebase, forked, and grew apart by hand — the same stereo beat-sync bug
was fixed twice in one day, which is the whole argument for this package.
[swift-design-kit](../swift-design-kit) (cover art, flyers, posters) draws
its words, plates and photographs through the public pieces below rather
than a second text engine.

**Deliberately not here:** templates, template libraries, styles, CLIs.
A template gallery is a product's voice; this is the throat. The kits own
what their decks *say*; this owns how a deck becomes pixels.

## What's in the box

- **Model** — `SlideDeck`/`Slide`/`SlideLayer` as tolerant `Codable`
  values (unit coordinates, point sizes at a 1080-wide reference), the
  full layer vocabulary: text, images (corner, tilt, alpha-mask clip),
  video layers for device screens, chips, lists, rects, stickers, dot
  grids, glyph patterns, the opt-in page indicator.
- **Backgrounds** — solid, gradient, image and video plates with dim,
  scrim (edge-aware), blur, and a **measured scrim**: `adaptiveScrim`
  samples the plate's luminance under the slide's text and darkens by
  what legibility actually costs.
- **Text** — pure CoreText: `**accent**`/`*italic*`/`#hashtag` markup,
  accent weights, hollow and outlined strokes, gradient glyphs, line
  pills, auto-shrink with a one-line rule for single words.
- **Rendering** — one deterministic `SlideRenderer.render` every output
  format calls; the audit (`SlideRenderer.audit`) reports what tolerance
  hides: shrink-floor hits, overflow, unfilled tokens, unreadable images,
  broken grades, invisible contrast, and text under platform chrome
  (`Resources/safe-zones.json`).
- **Public pieces for other compositors** — `TextDrawer.draw` / `layout`
  (style, region, scale → a `TextFit`: the size after auto-shrink, whether
  it fitted, line count, each line's bounds; `TextStyle.maxLines` caps the
  wrap and `keepsWordsWhole` shrinks rather than break a word mid-way), `FontResolver.font`, and the plate helpers on `SlideRenderer`:
  `loadImage` (EXIF orientation, PDF logos), `graded`, `blurred`,
  `drawAspectFilled`, `renderWashes`, `adaptiveWashes`.
- **Export** — numbered PNG sets (with the audit from the same pass) and
  the stitched MP4: transitions, Ken Burns, entrances, narration, music
  bed, synthesized transition SFX, beat-synced cuts. BT.709-tagged, and a
  failed export cleans up after itself.
- **Templates** — the generic `Template`/`TemplateData` fill: `{tokens}`,
  repeat groups, derived tokens, and the fallback engine (a hook borrows
  the topic, a CTA defaults from the brand or leaves the deck) — the
  galleries that USE it live in the kits.
- **Color** — [swift-video-grade](../swift-video-grade) re-exported, so
  `import CanvasKit` is the only import a kit writes; the color layer
  stays its own sharp tool underneath.

## Requirements

- macOS 26+ / iOS 26+ (set by swift-video-grade)
- Swift 6.2

## License

MIT — see [LICENSE](LICENSE).
