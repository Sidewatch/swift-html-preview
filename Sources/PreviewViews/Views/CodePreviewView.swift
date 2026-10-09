//
//  CodePreviewView.swift
//  PreviewViews
//
//  Source text, read-only, highlighted the way the editor highlights it, with a line-number gutter.
//
//  Created by David Sherlock on 10/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import AppKit
import AppKitViews
import CodeLanguage
import CodeHighlighting
import FoundationExtensions

/// Source text, read-only, in the editor's font and the theme's colours, highlighted by the editor's
/// own tiers (a tree-sitter grammar where one exists, else an embedded-language splitter, else the
/// regex tables) with line numbers in a gutter. The Quick Look preview of a source file. Only the
/// first `highlightCap` characters are coloured and only the first `CodePreviewCap.lineCap` lines are
/// laid out (TextKit builds every glyph before the first draw), so a long file stays quick to show.
public final class CodePreviewView: NSView {
    /// How many characters are coloured; the rest show in the plain foreground.
    public static let highlightCap = 256 * 1024

    /// The text view, for the harness (read its attributes, its gutter).
    public let textView: NSTextView
    /// The scroll view around it, which carries the gutter as its vertical ruler.
    public let scrollView = NSScrollView()
    /// The gutter.
    public let gutter: LineNumberGutter
    private let note = NSTextField(labelWithString: "")

    /// `text` as `language`; `note` (the file was cut short, say) shows in a strip above, joined
    /// with the line-cap note when the text runs past `CodePreviewCap.lineCap` lines.
    public init(text: String, language: Language, note: String? = nil) {
        let shownText = CodePreviewCap.cut(text)
        let note = Self.joinedNote(note, lines: shownText)
        let text = shownText.text
        let storage = NSTextStorage(string: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layout.addTextContainer(container)
        textView = NSTextView(frame: .zero, textContainer: container)
        gutter = LineNumberGutter(textView: textView, text: text)
        super.init(frame: .zero)
        let palette = PreviewViews.palette
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.backgroundColor = palette.background
        textView.textColor = palette.foreground
        textView.insertionPointColor = palette.cursor
        textView.selectedTextAttributes = [.backgroundColor: palette.selection]
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttributes([.font: palette.editorFont, .foregroundColor: palette.foreground], range: full)
        let colored = NSRange(location: 0, length: min(storage.length, Self.highlightCap))
        Self.highlighter(for: language).highlight(storage, in: colored)
        storage.endEditing()

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = palette.background
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        gutter.clientView = textView
        // The numbers follow the text as it scrolls.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            gutter, selector: #selector(LineNumberGutter.textScrolled), name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)

        let shown = note != nil
        self.note.stringValue = note ?? ""
        self.note.font = palette.uiFontSmall
        self.note.textColor = palette.statusText
        self.note.isHidden = !shown
        for v in [scrollView, self.note] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            self.note.topAnchor.constraint(equalTo: topAnchor, constant: shown ? 6 : 0),
            self.note.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            scrollView.topAnchor.constraint(equalTo: shown ? self.note.bottomAnchor : topAnchor, constant: shown ? 6 : 0),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        wantsLayer = true
        layer?.backgroundColor = palette.background.cgColor
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError() }

    /// The note strip's text, for a test.
    public var noteForTesting: String { note.stringValue }

    /// `note` and, when the text was cut at the line cap, the count of what was left out.
    static func joinedNote(_ note: String?, lines: (text: String, totalLines: Int, cut: Bool)) -> String? {
        guard lines.cut else { return note }
        let cap = String(
            localized: "Showing the first \(CodePreviewCap.lineCap.grouped) of \(lines.totalLines.grouped) lines.", bundle: .module,
            comment: "Quick Look code preview: a very long file shows only its first lines; both values are line counts.")
        return [note, cap].compactMap { $0 }.joined(separator: " ")
    }

    /// The editor's tier for `language`: its grammar, its region splitter, or its regex tables —
    /// the choice `HighlightedHTML.render` makes, painting attributes instead of HTML.
    static func highlighter(for language: Language) -> CodeHighlighter {
        if let tree = TreeSitterHighlighter(language: language) { return tree }
        if let component = EmbeddedMarkupHighlighter(language: language, colors: HighlightTheme.colors) { return component }
        return SyntaxHighlighter(language: language, colors: HighlightTheme.colors)
    }

    /// The distinct foreground colours in the first `limit` characters — for the harness.
    public func distinctColorsForTesting(limit: Int = 4_000) -> Int {
        guard let storage = textView.textStorage else { return 0 }
        var colors = Set<String>()
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: min(limit, storage.length))) { value, _, _ in
            if let c = (value as? NSColor)?.usingColorSpace(.sRGB) {
                colors.insert(String(format: "%.2f %.2f %.2f", c.redComponent, c.greenComponent, c.blueComponent))
            }
        }
        return colors.count
    }
}

/// The code preview's gutter: each line's number beside it, in the theme's gutter colours.
public final class LineNumberGutter: NSRulerView {
    private weak var codeView: NSTextView?
    /// Where each line starts (UTF-16 offsets), found once — the text never changes.
    private let lineStarts: [Int]

    init(textView: NSTextView, text: String) {
        codeView = textView
        var starts = [0]
        let utf16 = text.utf16
        var offset = 0
        for unit in utf16 {
            offset += 1
            if unit == 0x0A { starts.append(offset) }
        }
        lineStarts = starts
        super.init(scrollView: nil, orientation: .verticalRuler)
        let digits = max(3, String(starts.count).count)
        ruleThickness = CGFloat(digits) * 8 + 16
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }

    /// How many lines the gutter numbers.
    public var lineCount: Int { lineStarts.count }

    @objc func textScrolled() { needsDisplay = true }

    public override func drawHashMarksAndLabels(in rect: NSRect) {
        let palette = PreviewViews.palette
        palette.gutterBackground.setFill()
        bounds.fill()
        guard let tv = codeView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let font = NSFont.monoDigits(max(9, palette.editorFont.pointSize - 1))
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: palette.gutterText]
        let visible = tv.visibleRect
        let glyphs = lm.glyphRange(forBoundingRect: visible, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // The first line at or before the visible text, by binary search over the line starts.
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= chars.location { lo = mid } else { hi = mid - 1 }
        }
        let length = tv.textStorage?.length ?? 0
        var line = lo
        while line < lineStarts.count {
            let start = lineStarts[line]
            if start > NSMaxRange(chars) || (start >= length && line > 0) { break }
            let glyph = lm.glyphIndexForCharacter(at: min(start, max(0, length - 1)))
            var fragment = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            fragment.origin.y += tv.textContainerInset.height
            let y = convert(NSPoint(x: 0, y: fragment.minY), from: tv).y
            let label = "\(line + 1)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(
                at: NSPoint(x: ruleThickness - size.width - 8, y: y + (fragment.height - size.height) / 2), withAttributes: attrs)
            line += 1
        }
    }
}
