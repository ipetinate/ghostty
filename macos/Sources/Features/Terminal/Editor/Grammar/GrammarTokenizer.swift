import Foundation

/// Colours one line of a document against a TextMate grammar.
///
/// **One line at a time, with the state carried across.** ``tokenize(_:state:)``
/// takes the state the line above ended in and returns the spans of this
/// line plus the state this line ends in. Nothing here knows what a document
/// is, keeps a cache, or reads a file: a caller walks the lines, keeps the
/// outgoing states, and stops re-tokenizing as soon as a state repeats.
///
/// **Offsets are UTF-8 byte offsets into the line.** They stay bytes the
/// whole way down, because that is what Oniguruma searches, and converting
/// per match would cost more than the tokenizing does. Turning a span into
/// an `NSRange` is the caller's job and happens once, when it paints.
///
/// **Not thread-safe, one per thread.** It owns compiled patterns, and an
/// ``OnigRegex`` writes its match into a buffer it owns, so two threads
/// sharing one tokenizer would overwrite each other's captures. The
/// ``GrammarStore`` behind it is shared and holds no cache, which is what
/// makes a second tokenizer cheap.
///
/// **Bounded on purpose.** A grammar arrives from an extension somebody else
/// wrote. Every loop here has a ceiling — how many rules a position is tried
/// against, how many times a line may iterate, how deep the region stack
/// goes, how far a capture may recurse — so a grammar that is pathological
/// rather than merely slow colours a line wrong instead of hanging the
/// editor. ``OnigRegex`` caps backtracking for the same reason.
final class GrammarTokenizer {
    /// A run of bytes and the scopes covering it, innermost last.
    struct Span: Equatable {
        let range: Range<Int>
        let scopes: [String]

        /// The innermost scope, which is what a theme usually looks at
        /// first.
        var scope: String { scopes.last ?? "" }
    }

    struct Result: Equatable {
        let spans: [Span]
        let state: TokenizerState
    }

    /// The ceilings. Every one of them exists because the grammar is not
    /// ours.
    struct Limits {
        /// Rules a single position may be tried against, after includes are
        /// expanded.
        var candidates = 1024

        /// Times the scanner may go round on one line.
        var iterations = 4096

        /// Open regions. A grammar that pushes without popping stops here.
        var depth = 64

        /// How far a capture's own `patterns` may nest.
        var captureDepth = 3

        /// Compiled patterns kept before the cache is dropped whole.
        var compiledPatterns = 8192

        static let standard = Limits()
    }

    /// The grammar the document is in. `$base` resolves to this one.
    let base: Grammar

    private let store: GrammarStore
    private let limits: Limits

    /// Every injection this document could take, resolved once. The scope
    /// stack decides which of them are in play at a position; which of them
    /// exist at all is a fact about the store and cannot change under a
    /// tokenizer.
    private let injections: [ResolvedInjection]

    private var compiled: [String: PatternSlot] = [:]
    private var expansions: [ObjectIdentifier: [ResolvedRule]] = [:]
    private var nextSlotID = 0

    init?(store: GrammarStore, scopeName: String, limits: Limits = .standard) {
        guard let base = store.grammar(scope: scopeName) else { return nil }
        self.store = store
        self.base = base
        self.limits = limits
        self.injections = store.injections(forRootScope: base.scopeName)
    }

    init(store: GrammarStore, grammar: Grammar, limits: Limits = .standard) {
        self.store = store
        self.base = grammar
        self.limits = limits
        self.injections = store.injections(forRootScope: grammar.scopeName)
    }

    /// The state a document starts in: nothing open, the grammar's own
    /// scope under everything.
    var initialState: TokenizerState {
        .initial(scopeName: base.scopeName)
    }

    func tokenize(_ text: String, state: TokenizerState) -> Result {
        tokenize(Array(text.utf8), state: state)
    }

    func tokenize(_ line: [UInt8], state: TokenizerState) -> Result {
        var result = Result(spans: [], state: state)
        line.withUnsafeBytes { bytes in
            let run = Run(
                line: line,
                bytes: bytes,
                state: state,
                rootRules: topLevelRules(of: base),
                budget: limits.iterations,
                depth: 0,
                allowsDocumentAnchor: state.atDocumentStart)
            scan(run)
            var outgoing = run.state
            outgoing.atDocumentStart = false
            result = Result(spans: run.spans, state: outgoing)
        }
        return result
    }
}

// MARK: - The scan

private extension GrammarTokenizer {
    func scan(_ run: Run) {
        if !run.state.frames.isEmpty {
            applyWhileRules(run)
        }
        refreshCandidates(run)

        while run.iterations < run.budget, !run.stopped {
            run.iterations += 1
            guard run.position <= run.line.count else { break }
            guard let hit = bestMatch(run) else { break }

            let before = run.position
            apply(hit, run)
            if run.stopped { break }

            if run.position > before {
                run.stagnation = 0
                run.suppressed.removeAll(keepingCapacity: true)
                continue
            }

            run.stagnation += 1
            guard run.stagnation > max(16, run.candidates.count) else { continue }
            guard advanceOneCharacter(run) else { break }
        }

        let scopes = run.state.frames.last?.contentScopes ?? run.state.root
        emit(run, from: run.position, to: run.line.count, scopes: scopes)
        run.position = run.line.count
        for index in run.state.frames.indices {
            run.state.frames[index].carried = true
            run.state.frames[index].emptyEntry = -1
        }
    }

    /// A `while` region continues onto this line only while its pattern
    /// still matches at the top of it. The first one that fails takes every
    /// region inside it with it.
    func applyWhileRules(_ run: Run) {
        var index = 0
        while index < run.state.frames.count {
            let frame = run.state.frames[index]
            guard frame.isWhile, frame.carried, let pattern = frame.closing else {
                index += 1
                continue
            }
            guard let regex = regex(
                    of: slot(for: pattern),
                    allowContinuation: true,
                    allowDocumentStart: run.allowsDocumentAnchor),
                  regex.search(run.bytes, from: run.position),
                  let whole = regex.range(of: 0) else {
                run.state.frames.removeSubrange(index...)
                return
            }

            let outer = index > 0 ? run.state.frames[index - 1].contentScopes : run.state.root
            emit(run, from: run.position, to: whole.lowerBound, scopes: outer)
            run.position = whole.lowerBound
            emitCaptures(
                Emission(
                    captures: frame.rule.whileCaptures,
                    groups: groups(of: regex),
                    base: frame.nameScopes,
                    grammar: frame.grammar),
                run)
            run.position = max(run.position, whole.upperBound)
            run.anchor = run.position
            index += 1
        }
    }

    func bestMatch(_ run: Run) -> Hit? {
        var winner: Int?
        var earliest = Int.max
        let filtered = !run.suppressed.isEmpty

        for index in run.candidates.indices {
            if filtered, run.suppressed.contains(index) { continue }
            guard let start = matchStart(of: run.candidates[index], run: run) else { continue }
            guard start < earliest else { continue }
            earliest = start
            winner = index
            if start == run.position { break }
        }

        guard let winner else { return nil }
        let candidate = run.candidates[winner]
        guard let regex = regex(
                of: candidate.slot,
                allowContinuation: run.position == run.anchor,
                allowDocumentStart: run.allowsDocumentAnchor),
              regex.search(run.bytes, from: run.position),
              let whole = regex.range(of: 0) else { return nil }
        return Hit(index: winner, candidate: candidate, range: whole, groups: groups(of: regex))
    }

    /// Where a candidate's next match starts, or nil when it has none left
    /// on this line.
    ///
    /// Memoized, and that is what makes the scanner affordable. A grammar
    /// the size of Elixir's offers over a hundred rules at the top level,
    /// and searching all of them at every token would be a hundred searches
    /// per token. A search from `p` reports the *leftmost* match at or after
    /// `p`, so a match already found at `s` is still the answer for any
    /// later position up to `s`, and a pattern that found nothing from `p`
    /// finds nothing from anywhere after it either. Only the rules the
    /// cursor has walked past are searched again.
    ///
    /// A pattern with `\G` is never memoized: what it matches depends on
    /// where the search started, which is the whole point of it.
    func matchStart(of candidate: Candidate, run: Run) -> Int? {
        let slot = candidate.slot
        let memoizable = !slot.hasContinuationAnchor

        if memoizable, let cached = run.matchCache[slot.id], cached.from <= run.position {
            guard let start = cached.start else { return nil }
            if start >= run.position { return start }
        }

        let allowContinuation = run.position == run.anchor
        guard let regex = regex(
                of: slot,
                allowContinuation: allowContinuation,
                allowDocumentStart: run.allowsDocumentAnchor),
              regex.search(run.bytes, from: run.position),
              let whole = regex.range(of: 0) else {
            if memoizable {
                run.matchCache[slot.id] = CachedMatch(from: run.position, start: nil)
            }
            return nil
        }

        if memoizable {
            run.matchCache[slot.id] = CachedMatch(from: run.position, start: whole.lowerBound)
        }
        return whole.lowerBound
    }

    func apply(_ hit: Hit, _ run: Run) {
        let contentScopes = run.state.frames.last?.contentScopes ?? run.state.root
        emit(run, from: run.position, to: hit.range.lowerBound, scopes: contentScopes)
        run.position = max(run.position, hit.range.lowerBound)

        switch hit.candidate.source {
        case .end:
            closeRegion(hit, run)
        case .rule(let resolved):
            switch resolved.rule.kind {
            case .match:
                applyMatch(hit, resolved, run)
            case .beginEnd, .beginWhile:
                openRegion(hit, resolved, run)
            case .include, .group:
                run.suppressed.insert(hit.index)
            }
        }
    }

    /// Paints a `match` rule where it landed.
    ///
    /// A rule that matches nothing is taken out of the running until the
    /// cursor moves, or it would be picked again at the same offset for
    /// ever. Letting the rules behind it have the offset instead is closer
    /// to what the grammar meant than skipping a character.
    func applyMatch(_ hit: Hit, _ resolved: ResolvedRule, _ run: Run) {
        let contentScopes = run.state.frames.last?.contentScopes ?? run.state.root
        let name = Self.substitute(resolved.rule.name, groups: hit.groups, line: run.line)
        emitCaptures(
            Emission(
                captures: resolved.rule.captures,
                groups: hit.groups,
                base: contentScopes.pushing(name),
                grammar: resolved.grammar),
            run)
        run.position = max(run.position, hit.range.upperBound)
        if hit.range.isEmpty {
            run.suppressed.insert(hit.index)
        }
    }

    func openRegion(_ hit: Hit, _ resolved: ResolvedRule, _ run: Run) {
        guard run.state.frames.count < limits.depth else {
            run.suppressed.insert(hit.index)
            return
        }

        let rule = resolved.rule
        let contentScopes = run.state.frames.last?.contentScopes ?? run.state.root
        let nameScopes = contentScopes.pushing(Self.substitute(rule.name, groups: hit.groups, line: run.line))

        emitCaptures(
            Emission(captures: rule.beginCaptures, groups: hit.groups, base: nameScopes, grammar: resolved.grammar),
            run)

        let bodyScopes = nameScopes.pushing(Self.substitute(rule.contentName, groups: hit.groups, line: run.line))
        let isWhile: Bool
        let closing: String
        switch rule.kind {
        case .beginWhile(_, let continuation):
            isWhile = true
            closing = continuation
        case .beginEnd(_, let end):
            isWhile = false
            closing = end
        default:
            return
        }

        run.state.frames.append(
            TokenizerState.Frame(
                rule: rule,
                grammar: resolved.grammar,
                closing: Self.resolveBackReferences(closing, groups: hit.groups, line: run.line),
                isWhile: isWhile,
                nameScopes: nameScopes,
                contentScopes: bodyScopes,
                carried: false,
                emptyEntry: hit.range.isEmpty ? hit.range.upperBound : -1))

        run.position = max(run.position, hit.range.upperBound)
        run.anchor = run.position
        refreshCandidates(run)
    }

    /// Closes the open region on its `end` match.
    ///
    /// A zero-width `end` is ordinary and closes the region where it
    /// matched. HTML's attributes are written that way: `setup` in
    /// `<script setup lang="ts">` opens a region whose end is
    /// `(?=\s*+[^=\s])`, which matches empty the moment the name is read,
    /// because an attribute with no value ends where it began. Refusing
    /// that left the region open for the rest of the file — the whole script
    /// block of every Vue component with `<script setup>` came out as HTML
    /// attribute names, and so did the file after it.
    ///
    /// What must still be refused is narrower: a region whose `begin` was
    /// *also* zero-width at the same offset, which would push and pop there
    /// for ever. That one is abandoned, and the rest of the line goes out
    /// under what was around it.
    func closeRegion(_ hit: Hit, _ run: Run) {
        guard let frame = run.state.frames.last else { return }
        if hit.range.isEmpty, hit.range.lowerBound == frame.emptyEntry {
            run.state.frames.removeLast()
            run.stopped = true
            return
        }

        emitCaptures(
            Emission(
                captures: frame.rule.endCaptures,
                groups: hit.groups,
                base: frame.nameScopes,
                grammar: frame.grammar),
            run)
        run.state.frames.removeLast()
        run.position = max(run.position, hit.range.upperBound)
        refreshCandidates(run)
    }

    /// The last resort, when a grammar pushes and pops at one position
    /// without ever consuming anything. One character goes out under the
    /// scopes in force and the scan carries on past it.
    func advanceOneCharacter(_ run: Run) -> Bool {
        guard run.position < run.line.count else { return false }
        let scopes = run.state.frames.last?.contentScopes ?? run.state.root
        var next = run.position + 1
        while next < run.line.count, run.line[next] & 0xC0 == 0x80 { next += 1 }
        emit(run, from: run.position, to: next, scopes: scopes)
        run.position = next
        run.stagnation = 0
        run.suppressed.removeAll(keepingCapacity: true)
        return true
    }
}

// MARK: - Spans

private extension GrammarTokenizer {
    func emit(_ run: Run, from lower: Int, to upper: Int, scopes: ScopeStack) {
        guard lower < upper else { return }
        if run.lastStack === scopes, let last = run.spans.last, last.range.upperBound == lower {
            run.spans[run.spans.count - 1] = Span(range: last.range.lowerBound..<upper, scopes: last.scopes)
            return
        }
        run.spans.append(Span(range: lower..<upper, scopes: scopes.names))
        run.lastStack = scopes
    }

    /// Paints one match, giving each named group the scope the grammar
    /// asked for.
    ///
    /// Group zero is the whole match, and the groups nest: a group that
    /// starts inside one still open is painted over it. A group that took
    /// part in no match is skipped rather than treated as empty at zero,
    /// which is the difference between `(a)|(b)` colouring one alternative
    /// and colouring the start of the line.
    func emitCaptures(_ emission: Emission, _ run: Run) {
        guard let whole = emission.groups.first ?? nil else { return }
        guard !emission.captures.isEmpty else {
            emit(run, from: whole.lowerBound, to: whole.upperBound, scopes: emission.base)
            return
        }

        var open: [(end: Int, scopes: ScopeStack)] = [(whole.upperBound, emission.base)]
        var cursor = whole.lowerBound
        var consumed = whole.lowerBound

        for group in emission.groups.indices {
            guard let range = emission.groups[group], let capture = emission.captures[group] else { continue }
            guard range.lowerBound >= whole.lowerBound, range.upperBound <= whole.upperBound else { continue }
            guard range.lowerBound >= consumed else { continue }

            while open.count > 1, range.lowerBound >= open[open.count - 1].end {
                let top = open.removeLast()
                emit(run, from: cursor, to: top.end, scopes: top.scopes)
                cursor = max(cursor, top.end)
            }

            emit(run, from: cursor, to: range.lowerBound, scopes: open[open.count - 1].scopes)
            cursor = max(cursor, range.lowerBound)

            let name = Self.substitute(capture.name, groups: emission.groups, line: run.line)
            let scopes = open[open.count - 1].scopes.pushing(name)

            if capture.patterns.isEmpty {
                open.append((range.upperBound, scopes))
                continue
            }

            emitCaptureRegion(capture, range: range, scopes: scopes, grammar: emission.grammar, run: run)
            cursor = max(cursor, range.upperBound)
            consumed = range.upperBound
        }

        while let top = open.last {
            emit(run, from: cursor, to: top.end, scopes: top.scopes)
            cursor = max(cursor, top.end)
            open.removeLast()
        }
    }

    /// Runs a capture's own `patterns` over the group's bytes.
    ///
    /// The group is tokenized on its own, as a slice, which is what the
    /// reference implementation does and what the format's own wording
    /// implies. The consequence is worth knowing: `^`, `\G` and lookbehind
    /// inside those patterns see the group and not the line around it.
    func emitCaptureRegion(
        _ capture: GrammarCapture,
        range: Range<Int>,
        scopes: ScopeStack,
        grammar: Grammar,
        run: Run
    ) {
        guard run.depth < limits.captureDepth, !range.isEmpty else {
            emit(run, from: range.lowerBound, to: range.upperBound, scopes: scopes)
            return
        }

        let slice = Array(run.line[range])
        var spans: [Span] = []
        slice.withUnsafeBytes { bytes in
            let nested = Run(
                line: slice,
                bytes: bytes,
                state: TokenizerState(root: scopes, frames: []),
                rootRules: expand(capture.patterns, in: grammar),
                budget: max(64, run.budget / 8),
                depth: run.depth + 1,
                allowsDocumentAnchor: run.allowsDocumentAnchor && range.lowerBound == 0)
            scan(nested)
            spans = nested.spans
        }

        for span in spans {
            let lower = range.lowerBound + span.range.lowerBound
            let upper = range.lowerBound + span.range.upperBound
            guard lower < upper else { continue }
            run.spans.append(Span(range: lower..<upper, scopes: span.scopes))
            run.lastStack = nil
        }
    }
}

// MARK: - Candidates

private extension GrammarTokenizer {
    func refreshCandidates(_ run: Run) {
        run.candidates = candidates(for: run)
        run.suppressed.removeAll(keepingCapacity: true)
    }

    /// What the scanner tries at the current position, in the order ties are
    /// broken.
    ///
    /// An `L:` injection goes ahead of everything, because that is what the
    /// prefix asks for. The open region's own `end` comes next — TextMate
    /// closes a region in preference to matching inside it, unless the rule
    /// set `applyEndPatternLast`. Then the region's child rules, then the
    /// injections that did not ask to go first.
    func candidates(for run: Run) -> [Candidate] {
        let top = run.state.frames.last
        let scopes = (top?.contentScopes ?? run.state.root).names
        let inner = top.map { expansion(of: $0.rule, in: $0.grammar) } ?? run.rootRules

        var result: [Candidate] = []
        let injected = activeInjections(matching: scopes)

        append(injected, priority: .before, to: &result)
        let end = endCandidate(of: top)
        if let end, !(top?.rule.applyEndPatternLast ?? false) { result.append(end) }
        for resolved in inner {
            guard result.count < limits.candidates else { break }
            guard let pattern = resolved.rule.entryPattern else { continue }
            result.append(candidate(pattern: pattern, source: .rule(resolved)))
        }
        append(injected, priority: .normal, to: &result)
        append(injected, priority: .after, to: &result)
        if let end, top?.rule.applyEndPatternLast ?? false { result.append(end) }
        return result
    }

    func endCandidate(of frame: TokenizerState.Frame?) -> Candidate? {
        guard let frame, !frame.isWhile, let pattern = frame.closing else { return nil }
        return candidate(pattern: pattern, source: .end)
    }

    func append(_ injected: [ResolvedInjection], priority: ScopeSelector.Priority, to result: inout [Candidate]) {
        for injection in injected where injection.selector.priority == priority {
            for resolved in expansion(of: injection.rule, in: injection.grammar) {
                guard result.count < limits.candidates else { return }
                guard let pattern = resolved.rule.entryPattern else { continue }
                result.append(candidate(pattern: pattern, source: .rule(resolved)))
            }
        }
    }

    /// The injections whose selector matches the stack in force here.
    ///
    /// Re-asked every time the stack changes, which is what makes an
    /// injection follow the region it was written for: PHP's `<?php` rule
    /// applies in the HTML shell and inside a tag's attributes, and its
    /// selector says so by excluding `meta.embedded` — so the rule leaves
    /// as soon as it has taken the document into PHP, and cannot open a
    /// second embedded block inside the first.
    func activeInjections(matching scopes: [String]) -> [ResolvedInjection] {
        guard !injections.isEmpty else { return [] }
        return injections.filter { $0.selector.matches(scopes) }
    }

    func candidate(pattern: String, source: Candidate.Source) -> Candidate {
        Candidate(source: source, slot: slot(for: pattern))
    }

    /// One level of a rule's children, expanded and kept. Keyed on the
    /// rule's identity, which is why ``GrammarRule`` is a class.
    func expansion(of rule: GrammarRule, in grammar: Grammar) -> [ResolvedRule] {
        let key = ObjectIdentifier(rule)
        if let cached = expansions[key] { return cached }
        let expanded = expand(rule.patterns, in: grammar)
        expansions[key] = expanded
        return expanded
    }

    func topLevelRules(of grammar: Grammar) -> [ResolvedRule] {
        let key = ObjectIdentifier(grammar)
        if let cached = expansions[key] { return cached }
        let expanded = expand(grammar.patterns, in: grammar)
        expansions[key] = expanded
        return expanded
    }

    /// Flattens one level of a pattern list: an `include` is replaced by
    /// what it points at, and a rule carrying only `patterns` by its
    /// children. Deeper levels are expanded when the scanner descends into
    /// them, so a grammar that includes itself costs nothing until it does.
    func expand(_ rules: [GrammarRule], in grammar: Grammar) -> [ResolvedRule] {
        var output: [ResolvedRule] = []
        var visited: Set<ObjectIdentifier> = []
        append(rules, in: grammar, to: &output, visited: &visited)
        return output
    }

    func append(
        _ rules: [GrammarRule],
        in grammar: Grammar,
        to output: inout [ResolvedRule],
        visited: inout Set<ObjectIdentifier>
    ) {
        for rule in rules {
            guard output.count < limits.candidates else { return }
            switch rule.kind {
            case .include(let reference):
                guard visited.insert(ObjectIdentifier(rule)).inserted else { continue }
                guard let target = store.resolve(include: reference, from: grammar, base: base) else { continue }
                append(target.rules, in: target.grammar, to: &output, visited: &visited)
            case .group:
                guard visited.insert(ObjectIdentifier(rule)).inserted else { continue }
                append(rule.patterns, in: grammar, to: &output, visited: &visited)
            case .match, .beginEnd, .beginWhile:
                output.append(ResolvedRule(rule: rule, grammar: grammar))
            }
        }
    }
}

// MARK: - Patterns

private extension GrammarTokenizer {
    /// The compiled form of one pattern, found once and then held by
    /// reference.
    ///
    /// A reference and not a dictionary lookup, because the lookup was the
    /// cost. The scanner tries every rule of the enclosing region at every
    /// position, a grammar the size of Elixir's offers over a hundred of
    /// them, and their patterns are hundreds of characters long — so keying
    /// the hot path on the pattern text meant hashing those characters a
    /// hundred times per token. A ``Candidate`` carries the slot instead,
    /// and the text is hashed once, when the candidate list is built.
    /// **Both anchors are resolved per search, and neither means to
    /// Oniguruma what it means to TextMate.**
    ///
    /// Oniguruma reads `\G` as "where this search started" and `\A` as "the
    /// start of the buffer", and this scanner hands it one line as the
    /// buffer and starts a search at every token. TextMate means something
    /// narrower by each: `\G` holds only where the enclosing `begin` or
    /// `while` match ended, which is how a continuation rule refuses to
    /// re-enter mid-line, and `\A` holds only on the document's first line.
    /// A pattern with either is compiled a second time with that anchor made
    /// unmatchable, and the variant is chosen per search.
    ///
    /// `\A` cost a `.md` file with TOML frontmatter its whole colouring:
    /// `markdown.toml.frontmatter.codeblock` opens on `\A\+{3}\s*$`, so the
    /// closing `+++` opened the block a second time and the rest of the
    /// document came out as TOML.
    final class PatternSlot {
        let id: Int
        let source: String
        let hasContinuationAnchor: Bool
        let hasDocumentAnchor: Bool

        private var variants: [OnigRegex?]
        private var built: [Bool]

        init(id: Int, source: String) {
            self.id = id
            self.source = source
            self.hasContinuationAnchor = GrammarTokenizer.hasContinuationAnchor(source)
            self.hasDocumentAnchor = GrammarTokenizer.hasDocumentAnchor(source)
            self.variants = [nil, nil, nil, nil]
            self.built = [false, false, false, false]
            _ = regex(allowContinuation: true, allowDocumentStart: true)
        }

        /// The pattern with the anchors the caller does not allow made
        /// unmatchable, compiled on first need and then held.
        func regex(allowContinuation: Bool, allowDocumentStart: Bool) -> OnigRegex? {
            let continuation = allowContinuation || !hasContinuationAnchor
            let documentStart = allowDocumentStart || !hasDocumentAnchor
            let index = (continuation ? 1 : 0) | (documentStart ? 2 : 0)
            if built[index] { return variants[index] }
            let pattern = continuation && documentStart
                ? source
                : GrammarTokenizer.withoutAnchors(
                    source,
                    continuation: continuation,
                    documentStart: documentStart)
            variants[index] = OnigRegex(pattern: pattern)
            built[index] = true
            return variants[index]
        }
    }

    func regex(of slot: PatternSlot, allowContinuation: Bool, allowDocumentStart: Bool) -> OnigRegex? {
        slot.regex(allowContinuation: allowContinuation, allowDocumentStart: allowDocumentStart)
    }

    func slot(for pattern: String) -> PatternSlot {
        if let entry = compiled[pattern] { return entry }
        if compiled.count >= limits.compiledPatterns { compiled.removeAll(keepingCapacity: true) }
        nextSlotID += 1
        let entry = PatternSlot(id: nextSlotID, source: pattern)
        compiled[pattern] = entry
        return entry
    }

    func groups(of regex: OnigRegex) -> [Range<Int>?] {
        guard regex.captureCount > 1 else { return [regex.range(of: 0)] }
        return (0..<regex.captureCount).map { regex.range(of: $0) }
    }
}

// MARK: - Text substitution

extension GrammarTokenizer {
    /// Fills `$1`-style references in a scope name from the match that
    /// produced it. `${1:/downcase}` and `${1:/upcase}` are honoured; any
    /// other transform is ignored and the raw capture used.
    static func substitute(_ template: String?, groups: [Range<Int>?], line: [UInt8]) -> String? {
        guard let template else { return nil }
        guard template.contains("$") else { return template }

        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            guard template[index] == "$" else {
                result.append(template[index])
                index = template.index(after: index)
                continue
            }

            var cursor = template.index(after: index)
            var braced = false
            if cursor < template.endIndex, template[cursor] == "{" {
                braced = true
                cursor = template.index(after: cursor)
            }

            var digits = ""
            while cursor < template.endIndex, isDigit(template[cursor]) {
                digits.append(template[cursor])
                cursor = template.index(after: cursor)
            }

            var transform = ""
            if braced, !digits.isEmpty {
                if cursor < template.endIndex, template[cursor] == ":" {
                    cursor = template.index(after: cursor)
                    while cursor < template.endIndex, template[cursor] != "}" {
                        transform.append(template[cursor])
                        cursor = template.index(after: cursor)
                    }
                }
                guard cursor < template.endIndex, template[cursor] == "}" else {
                    result.append("$")
                    index = template.index(after: index)
                    continue
                }
                cursor = template.index(after: cursor)
            }

            guard !digits.isEmpty else {
                result.append("$")
                index = template.index(after: index)
                continue
            }

            result += transformed(text(of: Int(digits) ?? -1, groups: groups, line: line), by: transform)
            index = cursor
        }
        return result
    }

    /// Substitutes a backreference in an `end` or `while` pattern with what
    /// the `begin` match captured, escaped so it is matched as text.
    ///
    /// This is why the engine needs Oniguruma rather than a compiled table
    /// of languages. Lua's `--[==[` closes on `]==]` and on no other run of
    /// equals signs, and the only way a grammar can say that is to write
    /// `\1` in the `end` and have it mean what `begin` found.
    static func resolveBackReferences(_ pattern: String, groups: [Range<Int>?], line: [UInt8]) -> String {
        guard pattern.contains("\\") else { return pattern }

        var result = ""
        var index = pattern.startIndex
        while index < pattern.endIndex {
            guard pattern[index] == "\\" else {
                result.append(pattern[index])
                index = pattern.index(after: index)
                continue
            }

            var cursor = pattern.index(after: index)
            guard cursor < pattern.endIndex else {
                result.append("\\")
                break
            }
            guard isDigit(pattern[cursor]) else {
                result.append("\\")
                result.append(pattern[cursor])
                index = pattern.index(after: cursor)
                continue
            }

            var digits = ""
            while cursor < pattern.endIndex, isDigit(pattern[cursor]) {
                digits.append(pattern[cursor])
                cursor = pattern.index(after: cursor)
            }
            result += escaped(text(of: Int(digits) ?? -1, groups: groups, line: line))
            index = cursor
        }
        return result
    }

    static func hasContinuationAnchor(_ pattern: String) -> Bool {
        contains(pattern, anchor: "G")
    }

    static func hasDocumentAnchor(_ pattern: String) -> Bool {
        contains(pattern, anchor: "A")
    }

    /// The same pattern with the disallowed anchors replaced by a codepoint
    /// no text contains, so the pattern compiles and never matches there.
    static func withoutAnchors(_ pattern: String, continuation: Bool, documentStart: Bool) -> String {
        var result = ""
        var index = pattern.startIndex
        while index < pattern.endIndex {
            guard pattern[index] == "\\" else {
                result.append(pattern[index])
                index = pattern.index(after: index)
                continue
            }
            let after = pattern.index(after: index)
            guard after < pattern.endIndex else {
                result.append("\\")
                break
            }
            let refused = (!continuation && pattern[after] == "G") || (!documentStart && pattern[after] == "A")
            if refused {
                result += "\\x{FFFF}"
            } else {
                result.append("\\")
                result.append(pattern[after])
            }
            index = pattern.index(after: after)
        }
        return result
    }

    private static func contains(_ pattern: String, anchor: Character) -> Bool {
        var index = pattern.startIndex
        while index < pattern.endIndex {
            guard pattern[index] == "\\" else {
                index = pattern.index(after: index)
                continue
            }
            let after = pattern.index(after: index)
            guard after < pattern.endIndex else { return false }
            if pattern[after] == anchor { return true }
            index = pattern.index(after: after)
        }
        return false
    }

    private static func text(of group: Int, groups: [Range<Int>?], line: [UInt8]) -> String {
        guard group >= 0, group < groups.count, let range = groups[group] else { return "" }
        guard range.lowerBound >= 0, range.upperBound <= line.count else { return "" }
        return String(bytes: line[range], encoding: .utf8) ?? ""
    }

    private static func transformed(_ text: String, by transform: String) -> String {
        switch transform {
        case "/downcase": return text.lowercased()
        case "/upcase": return text.uppercased()
        default: return text
        }
    }

    private static let metacharacters = Set("\\^$.|?*+()[]{}")

    private static func escaped(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            if metacharacters.contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    private static func isDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }
}

// MARK: - Per-line working state

private extension GrammarTokenizer {
    struct Candidate {
        enum Source {
            case end
            case rule(ResolvedRule)
        }

        let source: Source
        let slot: PatternSlot
    }

    struct Hit {
        let index: Int
        let candidate: Candidate
        let range: Range<Int>
        let groups: [Range<Int>?]
    }

    struct CachedMatch {
        let from: Int
        let start: Int?
    }

    struct Emission {
        let captures: [Int: GrammarCapture]
        let groups: [Range<Int>?]
        let base: ScopeStack
        let grammar: Grammar
    }

    /// Everything that changes while one line is scanned.
    ///
    /// A class so the scan can be written as small methods without an
    /// `inout` on every one of them, and so the line's bytes can be carried
    /// alongside. It never outlives the `withUnsafeBytes` call that made it.
    final class Run {
        let line: [UInt8]
        let bytes: UnsafeRawBufferPointer
        let budget: Int
        let depth: Int

        /// Whether `\A` holds anywhere on this line, which it does only on
        /// the document's first.
        let allowsDocumentAnchor: Bool

        var state: TokenizerState
        var rootRules: [ResolvedRule]
        var candidates: [Candidate] = []
        var spans: [Span] = []
        var lastStack: ScopeStack?
        var matchCache: [Int: CachedMatch] = [:]
        var suppressed: Set<Int> = []
        var position = 0
        var anchor = -1
        var iterations = 0
        var stagnation = 0
        var stopped = false

        init(
            line: [UInt8],
            bytes: UnsafeRawBufferPointer,
            state: TokenizerState,
            rootRules: [ResolvedRule],
            budget: Int,
            depth: Int,
            allowsDocumentAnchor: Bool
        ) {
            self.line = line
            self.bytes = bytes
            self.state = state
            self.rootRules = rootRules
            self.budget = budget
            self.depth = depth
            self.allowsDocumentAnchor = allowsDocumentAnchor
        }
    }
}
