// SPDX-License-Identifier: MIT
import SwiftUI

struct FilterBarView: View {
    let availableModels: [String]
    @Binding var dateRange: DateInterval
    @Binding var selectedModels: Set<String>
    var isLoading: Bool = false

    @State private var activePreset: Preset? = .sevenDays
    @State private var showCustomPicker = false
    @State private var showModelPicker = false
    @State private var customStart = Date()
    @State private var customEnd = Date()

    private enum Preset: LocalizedStringKey, CaseIterable {
        case today = "Today"
        case sevenDays = "7 Days"
        case thirtyDays = "30 Days"
        case thisMonth = "This Month"

        func dateInterval() -> DateInterval {
            let now = Date()
            let cal = Calendar.current
            switch self {
            case .today:
                return DateInterval(start: cal.startOfDay(for: now), end: now)
            case .sevenDays:
                return DateInterval(
                    start: cal.startOfDay(for: now.addingTimeInterval(-7 * 24 * 3600)), end: now)
            case .thirtyDays:
                return DateInterval(
                    start: cal.startOfDay(for: now.addingTimeInterval(-30 * 24 * 3600)), end: now)
            case .thisMonth:
                let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
                return DateInterval(start: start, end: now)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .opacity(isLoading ? 1 : 0)
                Picker("", selection: $activePreset) {
                    ForEach(Preset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(Optional(preset))
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: activePreset) { _, preset in
                    if let preset { dateRange = preset.dateInterval() }
                }
                customButton
            }
            HStack(spacing: 6) {
                Text("Model:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    showModelPicker = true
                } label: {
                    if selectedModels.isEmpty {
                        Text("All Models")
                    } else {
                        Text(selectedModels.sorted().joined(separator: ", "))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showModelPicker) { modelPicker }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var customButton: some View {
        if activePreset == nil {
            Button {
                customStart = dateRange.start
                customEnd = dateRange.end
                showCustomPicker = true
            } label: {
                Label("Custom", systemImage: "calendar")
            }
            .buttonStyle(.borderedProminent)
            .popover(isPresented: $showCustomPicker) { customDatePicker }
        } else {
            Button {
                customStart = dateRange.start
                customEnd = dateRange.end
                showCustomPicker = true
            } label: {
                Label("Custom", systemImage: "calendar")
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showCustomPicker) { customDatePicker }
        }
    }

    private var customDatePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Range").font(.headline)
            DatePicker("Start", selection: $customStart, displayedComponents: .date)
            DatePicker("End",   selection: $customEnd,   in: customStart..., displayedComponents: .date)
            HStack {
                Spacer()
                Button("Apply") {
                    let cal = Calendar.current
                    dateRange = DateInterval(
                        start: cal.startOfDay(for: customStart),
                        end:   cal.startOfDay(for: customEnd).addingTimeInterval(86399))
                    activePreset = nil
                    showCustomPicker = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(customEnd < customStart)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Filter by Model").font(.headline).padding(.bottom, 4)
            if availableModels.isEmpty {
                Text("No models in range")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(availableModels, id: \.self) { model in
                    Toggle(model, isOn: Binding(
                        get: { selectedModels.contains(model) },
                        set: { if $0 { selectedModels.insert(model) } else { selectedModels.remove(model) } }
                    ))
                    .toggleStyle(.checkbox)
                }
                if !selectedModels.isEmpty {
                    Divider()
                    Button("Clear") { selectedModels.removeAll() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(minWidth: 220)
    }
}
