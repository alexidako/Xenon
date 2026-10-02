import SwiftUI

struct QuizView: View {
    enum Phase { case setup, question, results }

    @State private var phase: Phase = .setup
    @State private var kinds: Set<QuizKind> = Set(QuizKind.allCases)
    @State private var range = 36
    @State private var length = 10
    @State private var practiceWeak = false

    @State private var rng = SeededRNG(seed: UInt64(ProcessInfo.processInfo.environment["XENON_QUIZ_SEED"] ?? "") ?? UInt64.random(in: 0..<UInt64.max))
    @State private var engine = QuizEngine(upTo: 36, kinds: QuizKind.allCases)
    @State private var question: QuizQuestion?
    @State private var asked = 0
    @State private var score = 0
    @State private var streak = 0
    @State private var bestStreak = 0
    @State private var answered: Int?              // chosen option (or clicked element) after answering
    @State private var clickedZ: Int?
    @State private var missed: [(q: QuizQuestion, given: String)] = []
    @State private var tick = 0
    private let stats = QuizStats.shared

    var body: some View {
        Group {
            switch phase {
            case .setup: setup
            case .question: questionView
            case .results: results
            }
        }
        .navigationTitle("Quiz")
        .onAppear { demoIfRequested() }
    }

    // MARK: setup

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Quiz").font(.largeTitle.bold())
                GroupBox("Question types") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(QuizKind.allCases) { k in
                            Toggle(tr(k.rawValue), isOn: Binding(get: { kinds.contains(k) }, set: { on in if on { kinds.insert(k) } else if kinds.count > 1 { kinds.remove(k) } }))
                        }
                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("Which elements?") {
                    Picker("", selection: $range) {
                        Text("First 20 (H–Ca)").tag(20); Text("First 36 (H–Kr)").tag(36); Text("First 54 (H–Xe)").tag(54); Text("All 118").tag(118)
                    }.pickerStyle(.segmented).labelsHidden().padding(8)
                }
                HStack {
                    Picker("Questions", selection: $length) { Text("5").tag(5); Text("10").tag(10); Text("20").tag(20) }.frame(width: 190)
                    Toggle("Practise my weak spots", isOn: $practiceWeak).help("Elements you miss come up more often")
                }
                Button { start() } label: { Text("Start quiz").frame(minWidth: 120) }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)

                weakSpotsPanel
            }
            .padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var weakSpotsPanel: some View {
        let weak = stats.weakSpots.prefix(6)
        GroupBox("Your weak spots") {
            VStack(alignment: .leading, spacing: 6) {
                if weak.isEmpty {
                    Text("Nothing yet. Elements you get wrong will show up here.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(weak), id: \.z) { w in
                        let e = ElementStore.all[w.z - 1]
                        HStack {
                            Text(e.symbol).font(.headline).frame(width: 36)
                            Text(e.name)
                            Spacer()
                            Text(tr("missed {missed} of {seen}", ["missed": w.missed, "seen": w.seen])).foregroundStyle(.secondary).font(.callout)
                        }
                    }
                    Button("Clear history", role: .destructive) { stats.reset(); tick += 1 }.buttonStyle(.link)
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(tick)
    }

    // MARK: question

    private var questionView: some View {
        VStack(spacing: 0) {
            HStack {
                ProgressView(value: Double(asked - (answered == nil ? 1 : 0)), total: Double(length)).frame(width: 220)
                Text(tr("Question {n} of {total}", ["n": asked, "total": length])).foregroundStyle(.secondary)
                Spacer()
                Label("\(score)", systemImage: "checkmark.circle").foregroundStyle(.green)
                Label("\(streak)", systemImage: "flame").foregroundStyle(.orange).help("Current streak")
                Button("Quit") { phase = .results }.buttonStyle(.link)
            }.padding(14)
            Divider()
            if let q = question {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(q.prompt).font(.system(size: 26, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        if q.kind == .findOnTable { tableChooser(q) } else { optionGrid(q) }
                        if let a = answered { feedback(q, a) }
                    }
                    .padding(28).frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func optionGrid(_ q: QuizQuestion) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, text in
                Button { answer(i, text) } label: {
                    HStack {
                        Text("\(i + 1)").font(.callout.monospaced()).foregroundStyle(.secondary)
                        Text(text).font(.title3).frame(maxWidth: .infinity, alignment: .leading)
                        if let a = answered { Image(systemName: i == q.correct ? "checkmark.circle.fill" : (i == a ? "xmark.circle.fill" : "circle")).foregroundStyle(i == q.correct ? .green : (i == a ? .red : .clear)) }
                    }
                    .padding(14)
                    .background(background(for: i, q), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.35)))
                }
                .buttonStyle(.plain).disabled(answered != nil)
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
            }
        }
    }

    private func background(for i: Int, _ q: QuizQuestion) -> Color {
        guard let a = answered else { return Color.secondary.opacity(0.10) }
        if i == q.correct { return Color.green.opacity(0.25) }
        return i == a ? Color.red.opacity(0.25) : Color.secondary.opacity(0.06)
    }

    private func tableChooser(_ q: QuizQuestion) -> some View {
        let cell: CGFloat = 36, gap: CGFloat = 3
        let shown = ElementStore.all.filter { $0.z <= range }
        let rows = (shown.map { $0.gridPosition.row }.max() ?? 0) + 1
        let extra: CGFloat = rows > 8 ? 12 : 0
        return ZStack(alignment: .topLeading) {
            ForEach(ElementStore.all.filter { $0.z <= range }) { e in
                let p = e.gridPosition
                let state: Color = answered == nil ? Color.secondary.opacity(0.18)
                    : (e.z == q.answerZ ? Color.green.opacity(0.7) : (e.z == clickedZ ? Color.red.opacity(0.7) : Color.secondary.opacity(0.10)))
                RoundedRectangle(cornerRadius: 4).fill(state).frame(width: cell, height: cell)
                    .overlay(Text(answered == nil ? "" : e.symbol).font(.system(size: 12, weight: .semibold)))
                    .offset(x: CGFloat(p.col) * (cell + gap), y: CGFloat(p.row) * (cell + gap) + (p.row >= 8 ? 12 : 0))
                    .onTapGesture { if answered == nil { clickedZ = e.z; answer(e.z == q.answerZ ? 0 : 1, e.name) } }
            }
        }
        .frame(width: 18 * (cell + gap), height: CGFloat(rows) * (cell + gap) + extra, alignment: .topLeading)
        .overlay(alignment: .top) {
            if answered == nil { Text("Click the element").font(.callout).foregroundStyle(.secondary).offset(y: -22) }
        }
        .padding(.top, 20)
    }

    private func feedback(_ q: QuizQuestion, _ a: Int) -> some View {
        let right = q.kind == .findOnTable ? clickedZ == q.answerZ : a == q.correct
        return VStack(alignment: .leading, spacing: 12) {
            Label(right ? tr("Correct") : tr("Not quite"), systemImage: right ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.title2.bold()).foregroundStyle(right ? Color.green : Color.red)
            Text(q.explanation).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button { next() } label: { Text(asked >= length ? "See results" : "Next").frame(minWidth: 90) }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background((right ? Color.green : Color.red).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: results

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Results").font(.largeTitle.bold())
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(score)").font(.system(size: 64, weight: .bold)).foregroundStyle(score * 10 >= asked * 8 ? Color.green : Color.primary)
                    Text(tr("out of {total}", ["total": max(asked - (answered == nil && phase == .results && question != nil && asked > score + missed.count ? 1 : 0), score + missed.count)])).font(.title2).foregroundStyle(.secondary)
                }
                Text(tr("Best streak: {n}", ["n": bestStreak])).foregroundStyle(.secondary)
                if !missed.isEmpty {
                    GroupBox("Review what you missed") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(missed.enumerated()), id: \.offset) { _, m in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(m.q.prompt).font(.headline)
                                    Text(tr("You answered: {given}", ["given": tr(m.given)])).foregroundStyle(.red)
                                    Text(m.q.explanation).foregroundStyle(.secondary)
                                }
                            }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Label("Perfect round", systemImage: "star.fill").foregroundStyle(.yellow).font(.title3)
                }
                HStack {
                    Button("Play again") { start() }.buttonStyle(.borderedProminent)
                    Button("Change settings") { phase = .setup }
                }
            }.padding(24).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    // MARK: flow

    private func start() {
        engine = QuizEngine(upTo: range, kinds: QuizKind.allCases.filter { kinds.contains($0) }, stats: stats, weighted: practiceWeak)
        asked = 0; score = 0; streak = 0; bestStreak = 0; missed = []; answered = nil; clickedZ = nil
        phase = .question
        next()
    }

    private func next() {
        if asked >= length { phase = .results; return }
        answered = nil; clickedZ = nil
        question = engine.next(using: &rng)
        asked += 1
    }

    private func answer(_ index: Int, _ text: String) {
        guard let q = question, answered == nil else { return }
        answered = index
        let right = q.kind == .findOnTable ? (clickedZ == q.answerZ) : index == q.correct
        stats.record(z: q.z, correct: right)
        if right { score += 1; streak += 1; bestStreak = max(bestStreak, streak) } else { streak = 0; missed.append((q, q.kind == .findOnTable ? text : text)) }
    }

    /// Test hook: XENON_QUIZ_PHASE = question | answered | wrong | results | table
    private func demoIfRequested() {
        guard let p = ProcessInfo.processInfo.environment["XENON_QUIZ_PHASE"], phase == .setup else { return }
        if let k = ProcessInfo.processInfo.environment["XENON_QUIZ_KIND"], let kind = QuizKind(rawValue: k) { kinds = [kind] }
        start()
        switch p {
        case "answered": if let q = question { answer(q.correct, q.options.indices.contains(q.correct) ? q.options[q.correct] : "") }
        case "wrong":
            if let q = question {
                if q.kind == .findOnTable { clickedZ = q.answerZ == 1 ? 2 : 1; answer(1, "wrong") }
                else { let i = (q.correct + 1) % q.options.count; answer(i, q.options[i]) }
            }
        case "results":
            for n in 0..<length {
                guard let q = question else { break }
                if q.kind == .findOnTable { clickedZ = n % 3 == 0 ? (q.answerZ == 1 ? 2 : 1) : q.answerZ; answer(n % 3 == 0 ? 1 : 0, "x") }
                else { let i = n % 3 == 0 ? (q.correct + 1) % q.options.count : q.correct; answer(i, q.options[i]) }
                next()
            }
        default: break
        }
    }
}
