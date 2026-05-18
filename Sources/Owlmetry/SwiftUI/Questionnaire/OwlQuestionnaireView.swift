#if canImport(SwiftUI) && !os(watchOS)
import SwiftUI

/// A SwiftUI form that renders an `OwlQuestionnaire` and submits the
/// completed answers via `Owl.submitQuestionnaireResponse`. Manual
/// presentation:
///
/// ```swift
/// .sheet(isPresented: $show) {
///     NavigationStack {
///         OwlQuestionnaireView(
///             questionnaire: spec,
///             onSubmitted: { _ in show = false },
///             onCancel: { show = false }
///         )
///     }
/// }
/// ```
///
/// For auto-trigger gated on launch / foreground / install-age conditions use
/// the `.owlQuestionnaire(slug:trigger:...)` view modifier instead.
public struct OwlQuestionnaireView: View {
    private let questionnaire: OwlQuestionnaire
    private let strings: OwlQuestionnaireStrings
    private let onSubmitted: ((OwlQuestionnaireReceipt) -> Void)?
    private let onCancel: (() -> Void)?
    private let onDismissed: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var textAnswers: [String: String] = [:]
    @State private var singleAnswers: [String: String] = [:]
    @State private var multiAnswers: [String: Set<String>] = [:]
    @State private var ratingAnswers: [String: Int] = [:]
    @State private var npsAnswers: [String: Int] = [:]

    @State private var isSubmitting = false
    @State private var submitted: OwlQuestionnaireReceipt?
    @State private var errorMessage: String?
    @State private var showSuccessAlert = false
    @State private var showDismissConfirm = false
    @State private var triedSubmit = false

    public init(
        questionnaire: OwlQuestionnaire,
        strings: OwlQuestionnaireStrings = .default,
        onSubmitted: ((OwlQuestionnaireReceipt) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onDismissed: (() -> Void)? = nil
    ) {
        self.questionnaire = questionnaire
        self.strings = strings
        self.onSubmitted = onSubmitted
        self.onCancel = onCancel
        self.onDismissed = onDismissed
    }

    public var body: some View {
        Form {
            if let description = questionnaire.description, !description.isEmpty {
                Section { Text(description).font(.subheadline).foregroundStyle(.secondary) }
            }
            ForEach(questionnaire.schema.questions, id: \.id) { question in
                questionSection(question)
            }
            Section {
                Button(role: .destructive) {
                    showDismissConfirm = true
                } label: {
                    Text(strings.doNotShowAgain)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(isSubmitting)
            }
        }
        .toolbar {
            if submitted == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onCancel?(); dismiss() } label: { Text(strings.skipButton) }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Group {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Button {
                                Task { await submit() }
                            } label: {
                                Text(strings.submitButton).fontWeight(.semibold)
                            }
                            .disabled(!hasAllRequired)
                        }
                    }
                }
            }
        }
        .alert(Text(strings.errorTitle), isPresented: errorAlertBinding, actions: {
            Button(role: .cancel) { errorMessage = nil } label: { Text("OK") }
        }, message: {
            if let errorMessage { Text(errorMessage) } else { EmptyView() }
        })
        .alert(Text(strings.successTitle), isPresented: $showSuccessAlert, actions: {
            Button(role: .cancel) {
                if let receipt = submitted { onSubmitted?(receipt) }
                dismiss()
            } label: { Text("OK") }
        }, message: { Text(strings.successBody) })
        .confirmationDialog(
            Text(strings.doNotShowAgainConfirmTitle),
            isPresented: $showDismissConfirm,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await dismissGlobally() }
            } label: { Text(strings.doNotShowAgainConfirmAction) }
            Button(role: .cancel) {} label: { Text(strings.doNotShowAgainCancel) }
        } message: {
            Text(strings.doNotShowAgainConfirmMessage)
        }
    }

    // MARK: - Per-question rendering

    @ViewBuilder
    private func questionSection(_ question: OwlQuestionnaireQuestion) -> some View {
        Section {
            switch question {
            case .text(let q): textQuestionView(q)
            case .singleChoice(let q): singleChoiceView(q)
            case .multiChoice(let q): multiChoiceView(q)
            case .rating(let q): ratingView(q)
            case .nps(let q): npsView(q)
            }
            if triedSubmit, question.required, !isAnswered(question) {
                Text(strings.errorRequiredMissing)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(question.title)
                if question.required {
                    Text("•").foregroundStyle(.red)
                        .accessibilityLabel(Text(strings.requiredLabel))
                }
            }
        } footer: {
            if let subtitle = question.subtitle, !subtitle.isEmpty {
                Text(subtitle)
            }
        }
    }

    @ViewBuilder
    private func textQuestionView(_ q: OwlQuestionnaireTextQuestion) -> some View {
        let binding = Binding<String>(
            get: { textAnswers[q.id] ?? "" },
            set: { textAnswers[q.id] = $0 }
        )
        if q.multiline {
            TextEditor(text: binding)
                .frame(minHeight: 100)
                .accessibilityLabel(Text(q.title))
        } else {
            let field = TextField(q.placeholder ?? "", text: binding)
                .accessibilityLabel(Text(q.title))
            #if os(iOS) || os(tvOS) || os(visionOS)
            field.textInputAutocapitalization(.sentences)
            #else
            field
            #endif
        }
    }

    @ViewBuilder
    private func singleChoiceView(_ q: OwlQuestionnaireSingleChoiceQuestion) -> some View {
        ForEach(q.options) { option in
            Button {
                singleAnswers[q.id] = option.id
            } label: {
                HStack {
                    Text(option.label).foregroundStyle(.primary)
                    Spacer()
                    if singleAnswers[q.id] == option.id {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func multiChoiceView(_ q: OwlQuestionnaireMultiChoiceQuestion) -> some View {
        ForEach(q.options) { option in
            let isOn = Binding<Bool>(
                get: { multiAnswers[q.id]?.contains(option.id) ?? false },
                set: { newValue in
                    var current = multiAnswers[q.id] ?? []
                    if newValue { current.insert(option.id) } else { current.remove(option.id) }
                    multiAnswers[q.id] = current
                }
            )
            Toggle(option.label, isOn: isOn)
        }
    }

    @ViewBuilder
    private func ratingView(_ q: OwlQuestionnaireRatingQuestion) -> some View {
        HStack(spacing: 12) {
            ForEach(1...q.scale, id: \.self) { value in
                Button {
                    ratingAnswers[q.id] = value
                } label: {
                    let filled = (ratingAnswers[q.id] ?? 0) >= value
                    Image(systemName: filled ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(filled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(value)"))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func npsView(_ q: OwlQuestionnaireNpsQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0...10, id: \.self) { value in
                        Button { npsAnswers[q.id] = value } label: {
                            Text("\(value)")
                                .font(.callout.weight(.medium))
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle().fill(
                                        npsAnswers[q.id] == value
                                            ? Color.accentColor.opacity(0.9)
                                            : Color.secondary.opacity(0.12)
                                    )
                                )
                                .foregroundStyle(npsAnswers[q.id] == value ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("\(value)"))
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text(strings.npsLowLabel)
                Spacer()
                Text(strings.npsHighLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - State

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func isAnswered(_ question: OwlQuestionnaireQuestion) -> Bool {
        switch question {
        case .text(let q):
            let v = textAnswers[q.id] ?? ""
            return !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .singleChoice(let q):
            return singleAnswers[q.id] != nil
        case .multiChoice(let q):
            return !(multiAnswers[q.id]?.isEmpty ?? true)
        case .rating(let q):
            return ratingAnswers[q.id] != nil
        case .nps(let q):
            return npsAnswers[q.id] != nil
        }
    }

    private var hasAllRequired: Bool {
        for q in questionnaire.schema.questions where q.required {
            if !isAnswered(q) { return false }
        }
        return true
    }

    private func collectAnswers() -> [String: OwlQuestionnaireAnswerValue] {
        var out: [String: OwlQuestionnaireAnswerValue] = [:]
        for q in questionnaire.schema.questions {
            switch q {
            case .text(let tq):
                let raw = (textAnswers[tq.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !raw.isEmpty { out[tq.id] = .text(raw) }
            case .singleChoice(let sq):
                if let v = singleAnswers[sq.id] { out[sq.id] = .choice(v) }
            case .multiChoice(let mq):
                if let set = multiAnswers[mq.id], !set.isEmpty {
                    out[mq.id] = .choices(Array(set))
                }
            case .rating(let rq):
                if let v = ratingAnswers[rq.id] { out[rq.id] = .rating(v) }
            case .nps(let nq):
                if let v = npsAnswers[nq.id] { out[nq.id] = .nps(v) }
            }
        }
        return out
    }

    @MainActor
    private func submit() async {
        triedSubmit = true
        guard hasAllRequired else {
            errorMessage = String(localized: strings.errorRequiredMissing)
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let receipt = try await Owl.submitQuestionnaireResponse(
                slug: questionnaire.slug,
                answers: collectAnswers()
            )
            submitted = receipt
            showSuccessAlert = true
        } catch let err as OwlQuestionnaireError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func dismissGlobally() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await Owl.dismissQuestionnaires()
            onDismissed?()
            dismiss()
        } catch let err as OwlQuestionnaireError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
