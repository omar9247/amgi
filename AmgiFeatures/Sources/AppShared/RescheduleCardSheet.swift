//
//  RescheduleCardSheet.swift
//  AppShared
//
//  Created by Amgi Contributors.
//

public import SwiftUI
public import AnkiKit
import Theme
import Foundation

/// Full reschedule sheet replacing the bare due-date alert.
/// Supports quick day presets, a calendar date picker, custom day/range specs
/// (`5`, `3-7`), and Anki's interval-reset (`!`) toggle.
@MainActor
public struct RescheduleCardSheet: View {
    public let cardIds: [CardID]
    public let onReschedule: (_ daysSpec: String) async -> String?

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var daysInput: String = "1"
    @State private var selectedDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var resetInterval: Bool = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private static let presets: [(label: String, days: Int)] = [
        ("Today", 0),
        ("Tomorrow", 1),
        ("3 days", 3),
        ("7 days", 7),
        ("14 days", 14),
        ("30 days", 30),
    ]

    public init(
        cardIds: [CardID],
        onReschedule: @escaping (_ daysSpec: String) async -> String?
    ) {
        self.cardIds = cardIds
        self.onReschedule = onReschedule
    }

    public var body: some View {
        NavigationStack {
            Form {
                presetsSection
                calendarSection
                customSpecSection
                optionsSection
            }
            .navigationTitle(cardIds.count > 1 ? "Reschedule \(cardIds.count) Cards" : "Reschedule Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reschedule") {
                        Task { await submit() }
                    }
                    .disabled(resolvedSpec == nil || isSubmitting)
                }
            }
            .alert(
                "Couldn't Reschedule",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
        }
    }

    private var presetsSection: some View {
        Section("Quick Presets") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: AmgiSpacing.sm)], spacing: AmgiSpacing.sm) {
                ForEach(Self.presets, id: \.days) { preset in
                    let isSelected = trimmedDaysInput == "\(preset.days)"
                    Button {
                        applyPresetDays(preset.days)
                    } label: {
                        Text(preset.label)
                            .amgiFont(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AmgiSpacing.sm)
                            .background(
                                isSelected ? palette.accent : palette.background,
                                in: RoundedRectangle(cornerRadius: AmgiRadius.control, style: .continuous)
                            )
                            .foregroundStyle(isSelected ? .white : palette.textPrimary)
                            .overlay {
                                RoundedRectangle(cornerRadius: AmgiRadius.control, style: .continuous)
                                    .strokeBorder(isSelected ? palette.accent : palette.separator, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.pressScale)
                }
            }
            .padding(.vertical, AmgiSpacing.xs)
        }
    }

    private var calendarSection: some View {
        Section("Pick Date") {
            DatePicker(
                "Target Due Date",
                selection: $selectedDate,
                in: Calendar.current.startOfDay(for: .now)...,
                displayedComponents: .date
            )
            .onChange(of: selectedDate) { _, newDate in
                let calendar = Calendar.current
                let startToday = calendar.startOfDay(for: .now)
                let startTarget = calendar.startOfDay(for: newDate)
                let diff = calendar.dateComponents([.day], from: startToday, to: startTarget).day ?? 0
                let clamped = max(0, diff)
                if trimmedDaysInput != "\(clamped)" {
                    daysInput = "\(clamped)"
                }
            }
        }
    }

    private var customSpecSection: some View {
        Section {
            HStack {
                Text("Days or Range")
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                TextField("e.g. 5 or 3-7", text: $daysInput)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: daysInput) { _, newValue in
                        syncCalendar(from: newValue)
                    }
            }
        } header: {
            Text("Custom Schedule")
        } footer: {
            Text(previewFooter)
                .foregroundStyle(resolvedSpec == nil ? palette.danger : palette.textSecondary)
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle("Reset interval to match due date", isOn: $resetInterval)
        } footer: {
            Text("When enabled (adds `!`), the card's review interval is updated to the new delay so future scheduling stays consistent.")
        }
    }

    private var trimmedDaysInput: String {
        daysInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedBounds: (minDays: Int, maxDays: Int, explicitBang: Bool)? {
        var raw = trimmedDaysInput
        guard !raw.isEmpty else { return nil }
        let explicitBang = raw.hasSuffix("!")
        if explicitBang { raw.removeLast() }
        guard !raw.isEmpty else { return nil }

        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 1, let single = Int(parts[0]), single >= 0, single <= 36500 {
            return (single, single, explicitBang)
        }
        if parts.count == 2,
           let low = Int(parts[0]),
           let high = Int(parts[1]),
           low >= 0,
           high >= low,
           high <= 36500 {
            return (low, high, explicitBang)
        }
        return nil
    }

    private var resolvedSpec: String? {
        guard let bounds = parsedBounds else { return nil }
        let base = bounds.minDays == bounds.maxDays
            ? "\(bounds.minDays)"
            : "\(bounds.minDays)-\(bounds.maxDays)"
        return (resetInterval || bounds.explicitBang) ? "\(base)!" : base
    }

    private var previewFooter: String {
        guard let bounds = parsedBounds else {
            return "Enter 0 for today, a positive number of days, or a range like 3-7."
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let intervalNote = resetInterval || bounds.explicitBang
            ? " · Interval will be reset."
            : " · Interval unchanged."

        if bounds.minDays == bounds.maxDays {
            let target = calendar.date(byAdding: .day, value: bounds.minDays, to: today) ?? today
            let when = bounds.minDays == 0 ? "today" : (bounds.minDays == 1 ? "tomorrow" : "in \(bounds.minDays) days")
            return "Due \(when) (\(formatter.string(from: target)))\(intervalNote)"
        } else {
            let minDate = calendar.date(byAdding: .day, value: bounds.minDays, to: today) ?? today
            let maxDate = calendar.date(byAdding: .day, value: bounds.maxDays, to: today) ?? today
            return "Randomly due between \(formatter.string(from: minDate)) and \(formatter.string(from: maxDate))\(intervalNote)"
        }
    }

    private func applyPresetDays(_ days: Int) {
        daysInput = "\(days)"
        syncCalendar(from: daysInput)
    }

    private func syncCalendar(from spec: String) {
        let cleaned = spec.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "!", with: "")
        guard let days = Int(cleaned), days >= 0, days <= 36500 else { return }
        let today = Calendar.current.startOfDay(for: .now)
        if let date = Calendar.current.date(byAdding: .day, value: days, to: today) {
            selectedDate = date
        }
    }

    private func submit() async {
        guard let spec = resolvedSpec else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        if let err = await onReschedule(spec) {
            errorMessage = err
        } else {
            dismiss()
        }
    }
}
