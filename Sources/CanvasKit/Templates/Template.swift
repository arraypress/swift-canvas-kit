//
//  Template.swift
//  CanvasKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

/// A deck with `{tokens}` in its text, plus the rule for turning one slide
/// into many.
///
/// This is the whole "AI layer" contract: SlideKit never talks to a model.
/// Anything that can produce a `TemplateData` — an LLM, a CSV, the Band9
/// generator, a human — can fill a template. The library's job ends at
/// substituting strings and expanding the repeating slide.
public struct Template: Codable, Equatable, Sendable {

    /// Template name, for galleries and CLIs.
    public var name: String

    /// The deck skeleton. Slide text may contain `{tokens}`; exactly one
    /// slide may be marked as repeating via `repeatSlideID`.
    public var deck: SlideDeck

    /// The `id` of the slide that expands once per item in the data. `nil`
    /// for fixed-shape templates (a quote card has no list).
    public var repeatSlideID: String?

    /// A GROUP of slide ids expanded together per item, in order — the
    /// question→reveal shape, where every item is two swipes. Takes
    /// precedence over `repeatSlideID` when set.
    public var repeatSlideIDs: [String]?

    /// The template's default plate grade — applied by `backed(by:)` when
    /// the caller's media doesn't carry its own. Curated per style so a
    /// photo dropped into `blush` fades like film and one dropped into
    /// `headline` goes newsprint, with nobody touching a slider.
    public var look: VideoGrade?

    public init(name: String, deck: SlideDeck, repeatSlideID: String? = nil, repeatSlideIDs: [String]? = nil, look: VideoGrade? = nil) {
        self.name = name
        self.deck = deck
        self.repeatSlideID = repeatSlideID
        self.repeatSlideIDs = repeatSlideIDs
        self.look = look
    }

    /// Read a template from JSON on disk.
    /// Write the template as readable, stable JSON — sorted keys so diffs
    /// mean something. `load(from:)` of the result is the identical
    /// template; the built-in library ships this way (see
    /// `TemplateLibrary.exportAll(to:)`), which is what keeps the JSON
    /// authoring format provably complete rather than aspirational.
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }

    /// This template carrying the caller's identity — name, handle, logo —
    /// while keeping the template's own palette and type. Built-in templates
    /// ship with empty identity; this is how they become *yours*.
    public func branded(name: String, handle: String, logoPath: String? = nil) -> Template {
        var result = self
        result.deck.brand.name = name
        result.deck.brand.handle = handle
        result.deck.brand.logoPath = logoPath
        result.deck.brand.showsFooter = !name.isEmpty || !handle.isEmpty
        return result
    }

    /// This template over the caller's photo or footage: the deck background
    /// becomes `media`, graded with the template's look unless the media
    /// already carries its own grade. Per-slide media belongs in the data —
    /// a background path may contain `{tokens}` like any text.
    public func backed(by media: Background) -> Template {
        var result = self
        result.deck.background = media.adoptingLook(look)
        return result
    }

    // MARK: - Filling

    /// Tokens the library invents — nobody supplies these and no contract
    /// lists them as inputs.
    public static let derivedTokens: Set<String> = ["n", "nn", "count", "initial", "checklist"]

    /// Tokens with a fallback path, so their absence never ships a brace:
    /// `hook` borrows the topic, `cta`/`ctaButton` default from the brand,
    /// and the purely-decorative slots (`ctaDetail`, `verdict`, `context`)
    /// simply vanish. One list, read by both the fill fallbacks and the
    /// machine-readable contract, so the two cannot disagree about what
    /// "optional" means.
    public static let optionalTokens: Set<String> = [
        "hook", "cta", "ctaButton", "ctaDetail", "verdict", "context"
    ]

    /// The decorative slots among ``optionalTokens``: absent, they render
    /// as nothing rather than as a default.
    static let vanishingTokens: Set<String> = ["ctaDetail", "verdict", "context"]

    /// What ``fillReporting(with:)`` did on the caller's behalf.
    ///
    /// An agent feeding JSON reads these next to the render warnings: the
    /// deck is post-ready either way, but a defaulted CTA is something the
    /// caller may want to supply properly next run.
    public struct FillNote: Equatable, Sendable, CustomStringConvertible {

        public enum Kind: Equatable, Sendable {
            /// `{hook}` was absent; the topic stood in.
            case hookDefaulted(to: String)
            /// `{cta}` was absent; the brand supplied the close.
            case ctaDefaulted(to: String)
            /// `{ctaButton}` was absent; a sensible label stood in.
            case buttonDefaulted(to: String)
            /// No CTA content and no brand to default from — the CTA slide
            /// left the deck rather than ship braces.
            case ctaDropped
        }

        public let kind: Kind

        public var description: String {
            switch kind {
            case .hookDefaulted(let topic):
                return "no {hook} given — the topic “\(topic)” is the hook"
            case .ctaDefaulted(let text):
                return "no {cta} given — defaulted from the brand: “\(text)”"
            case .buttonDefaulted(let label):
                return "no {ctaButton} given — defaulted to “\(label)”"
            case .ctaDropped:
                return "no {cta} and no brand to default from — the CTA slide was dropped"
            }
        }
    }

    /// Produce a concrete deck: deck-level tokens fill from `data.values`,
    /// and the repeating slide is expanded once per row in `data.items`,
    /// each row's tokens applied to its copy.
    ///
    /// Derived tokens exist without anyone providing them: `{n}` (1-based
    /// item number), `{nn}` (zero-padded, the "01" idiom), `{count}`
    /// (total items), `{initial}` (the item's first letter, the drop-cap
    /// idiom) and `{checklist}` (every item as a ✓-ticked row — the
    /// one-slide summary).
    public func fill(with data: TemplateData) -> SlideDeck {
        fillReporting(with: data).deck
    }

    /// The same fill, with the fallback decisions reported.
    ///
    /// A finished slide never shows a brace. Content from an agent often
    /// stops at the items — no hook line, no CTA copy — and a tool whose
    /// output needs hand-fixing afterwards has not finished its job. So the
    /// gaps that CAN be filled sensibly are, the one slide that cannot be
    /// leaves the deck, and every such decision comes back as a note.
    public func fillReporting(with data: TemplateData) -> (deck: SlideDeck, notes: [FillNote]) {
        var result = deck
        var slides: [Slide] = []
        var notes: [FillNote] = []

        /// `{count}` is a deck-wide fact, not a per-item one — hook slides say
        /// "the {count} things…" before any item exists.
        var deckTokens = data.values
        deckTokens["count"] = "\(data.items.count)"
        /// `{checklist}` — every item as a ticked row, for the one-slide
        /// summary a checklist post exists to be screenshotted from.
        if !data.items.isEmpty {
            deckTokens["checklist"] = data.items
                .compactMap { $0["task"] ?? $0["title"] ?? $0["tip"] }
                .map { "✓  \($0)" }
                .joined(separator: "\n")
        }

        /// The hook fallback: the topic IS the natural hook, worn plainly.
        if deckTokens["hook"] == nil, let topic = deckTokens["topic"], !topic.isEmpty {
            deckTokens["hook"] = topic
            notes.append(FillNote(kind: .hookDefaulted(to: topic)))
        }

        /// The CTA fallbacks: the brand supplies the close when the content
        /// does not — and when neither exists, the CTA slide goes rather
        /// than shipping braces on the last thing anybody swipes to.
        var dropCTASlides = false
        if deckTokens["cta"] == nil {
            let brand = deck.brand
            if !brand.handle.isEmpty {
                let text = "Follow \(brand.handle) for more"
                deckTokens["cta"] = text
                notes.append(FillNote(kind: .ctaDefaulted(to: text)))
            } else if !brand.name.isEmpty {
                let text = "More from \(brand.name)"
                deckTokens["cta"] = text
                notes.append(FillNote(kind: .ctaDefaulted(to: text)))
            } else if deck.slides.contains(where: { $0.role == "cta" }) {
                dropCTASlides = true
                notes.append(FillNote(kind: .ctaDropped))
            }
        }
        if deckTokens["ctaButton"] == nil, deckTokens["cta"] != nil {
            let label = deck.brand.handle.isEmpty ? "Save this" : "Follow"
            deckTokens["ctaButton"] = label
            notes.append(FillNote(kind: .buttonDefaulted(to: label)))
        }

        /// The decorative slots vanish instead of bracing — an empty text
        /// layer draws nothing, which is what "optional" should look like.
        for token in Self.vanishingTokens where deckTokens[token] == nil {
            deckTokens[token] = ""
        }

        /// One rule for both spellings: `repeatSlideID` is a group of one.
        /// The old code expanded groups only past `count > 1`, so a
        /// single-member `repeatSlideIDs` fell through both branches and
        /// rendered once — a listicle with one slide where ten were asked.
        let group = repeatSlideIDs ?? repeatSlideID.map { [$0] } ?? []

        for slide in deck.slides {
            if dropCTASlides, slide.role == "cta" { continue }
            if !group.isEmpty, group.contains(slide.id) {
                /// The whole group expands per item, emitted where its
                /// FIRST member sits; later members were already emitted.
                guard slide.id == group.first else { continue }
                let members = group.compactMap { id in deck.slides.first { $0.id == id } }
                for (index, item) in data.items.enumerated() {
                    var tokens = deckTokens.merging(item) { _, item in item }
                    tokens["n"] = "\(index + 1)"
                    tokens["nn"] = String(format: "%02d", index + 1)
                    /// `{initial}` — the item's first letter, for the
                    /// dictionary drop-cap idiom. Derived from the first of
                    /// word/title/tip the item provides.
                    if let lead = item["word"] ?? item["title"] ?? item["tip"],
                       let first = lead.first(where: \.isLetter) {
                        tokens["initial"] = String(first).uppercased()
                    }
                    for member in members {
                        var copy = member
                        copy.id = "\(member.id)-\(index + 1)"
                        copy.layers = member.layers.map { $0.substituting(tokens) }
                        copy.background = member.background?.substituting(tokens, look: look)
                        slides.append(copy)
                    }
                }
                continue
            }
            var copy = slide
            copy.layers = slide.layers.map { $0.substituting(deckTokens) }
            copy.background = slide.background?.substituting(deckTokens, look: look)
            slides.append(copy)
        }

        result.slides = slides
        result.background = deck.background.map { $0.substituting(deckTokens, look: look) }
        return (result, notes)
    }
}

/// What fills a template: deck-wide values and the per-slide rows.
///
/// Kept deliberately dumb — a dictionary and an array of dictionaries — so it
/// decodes from anything: an LLM's structured output, a parsed CSV, a seed
/// file.
public struct TemplateData: Codable, Equatable, Sendable {

    /// Deck-wide tokens: `{topic}`, `{date}`, whatever the template names.
    public var values: [String: String]

    /// One dictionary per repetition of the repeating slide.
    public var items: [[String: String]]

    public init(values: [String: String] = [:], items: [[String: String]] = []) {
        self.values = values
        self.items = items
    }
}

extension SlideLayer {

    /// This layer with `{tokens}` replaced in every text it carries.
    func substituting(_ tokens: [String: String]) -> SlideLayer {
        switch self {
        case .text(let text, let style, let region, let verticalAlignment):
            return .text(
                text: text.substituting(tokens),
                style: style,
                region: region,
                verticalAlignment: verticalAlignment
            )
        case .chip(let text, let region, let size, let alignment, let color):
            return .chip(text: text.substituting(tokens), region: region, size: size, alignment: alignment, color: color)
        case .sticker(let text, let region, let rotationDegrees):
            return .sticker(text: text.substituting(tokens), region: region, rotationDegrees: rotationDegrees)
        case .image(let path, let region, let cornerRadius, let scaling, let rotationDegrees, let maskPath):
            /// Media is data too: `{photo}` in an image path fills exactly
            /// like `{title}` in a headline.
            return .image(path: path.substituting(tokens), region: region, cornerRadius: cornerRadius,
                          scaling: scaling, rotationDegrees: rotationDegrees, maskPath: maskPath)
        case .video(let path, let region, let cornerRadius, let scaling, let maskPath):
            return .video(path: path.substituting(tokens), region: region, cornerRadius: cornerRadius,
                          scaling: scaling, maskPath: maskPath)
        case .list(let items, let style, let region, let marker, let spacing):
            /// Entries fill like anything else, so a template can carry a
            /// ranked list whose places and names arrive as data.
            return .list(
                items: items.map {
                    ListItem(title: $0.title?.substituting(tokens),
                             body: $0.body.substituting(tokens))
                },
                style: style, region: region, marker: marker, spacing: spacing
            )
        case .pageIndicator, .rect, .dots, .pattern:
            return self
        }
    }
}

extension Background {

    /// Backgrounds carry paths, and paths carry tokens — a repeating slide
    /// with `.image(path: "{photo}")` becomes a travel carousel from data
    /// alone. A media background that fills from a token also adopts the
    /// template's look, so per-item photos are art-directed like everything
    /// else; an explicit grade always wins.
    func substituting(_ tokens: [String: String], look: VideoGrade?) -> Background {
        switch self {
        case .solid, .linearGradient:
            return self
        case .image(let path, let dim, let scrim, let grade, let edge, let blur, let adaptive):
            return .image(path: path.substituting(tokens), dim: dim, scrim: scrim, grade: grade ?? look, scrimEdge: edge, blur: blur, adaptiveScrim: adaptive)
        case .video(let path, let dim, let scrim, let grade, let edge, let blur, let adaptive):
            return .video(path: path.substituting(tokens), dim: dim, scrim: scrim, grade: grade ?? look, scrimEdge: edge, blur: blur, adaptiveScrim: adaptive)
        }
    }

    /// This background wearing `look` unless it already has a grade of its
    /// own — the caller's explicit choice always beats the template default.
    func adoptingLook(_ look: VideoGrade?) -> Background {
        switch self {
        case .solid, .linearGradient:
            return self
        case .image(let path, let dim, let scrim, let grade, let edge, let blur, let adaptive):
            return .image(path: path, dim: dim, scrim: scrim, grade: grade ?? look, scrimEdge: edge, blur: blur, adaptiveScrim: adaptive)
        case .video(let path, let dim, let scrim, let grade, let edge, let blur, let adaptive):
            return .video(path: path, dim: dim, scrim: scrim, grade: grade ?? look, scrimEdge: edge, blur: blur, adaptiveScrim: adaptive)
        }
    }
}

extension String {

    /// Replace `{key}` occurrences. Unknown tokens stay in place — visible in
    /// the output, because a template author needs to *see* the token they
    /// misspelled, not silently publish a blank.
    ///
    /// One pass, left to right, and substituted text is never rescanned.
    /// The old per-key `replacingOccurrences` loop walked the dictionary in
    /// hash order, so a *value* that happened to contain `{count}` was
    /// filled on some runs and kept on others — the same deck rendering
    /// differently between invocations, which no deck may do.
    func substituting(_ tokens: [String: String]) -> String {
        guard contains("{") else { return self }

        var result = ""
        result.reserveCapacity(count)
        var remaining = Substring(self)

        while let open = remaining.firstIndex(of: "{") {
            result += remaining[..<open]
            let afterOpen = remaining[remaining.index(after: open)...]
            guard let close = afterOpen.firstIndex(of: "}") else {
                result += remaining[open...]
                return result
            }
            let key = String(afterOpen[..<close])
            result += tokens[key] ?? "{\(key)}"
            remaining = afterOpen[afterOpen.index(after: close)...]
        }
        result += remaining
        return result
    }
}
