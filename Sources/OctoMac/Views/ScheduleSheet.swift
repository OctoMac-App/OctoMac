import OctoPrintKit
import SwiftUI

/// Plan when a print happens: see when it would finish if started now, or start it later so it's done by a time
/// that suits you (say, before you get up).
struct ScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: PrinterSession
    let file: FileEntry
    let filament: Color

    enum Mode: String { case finishBy, startAt }

    @AppStorage("schedule.mode") private var mode = Mode.finishBy.rawValue
    @State private var hour = 8
    @State private var minute = 0
    @State private var bedClear = false

    /// Heating up before the first layer isn't in the print time; allow for it.
    static let warmUp: TimeInterval = 5 * 60

    private var duration: TimeInterval { file.expectedPrintTime?.seconds ?? 0 }

    /// The next time it's `hour:minute`, today or tomorrow.
    private var chosen: Date {
        let calendar = Calendar.current
        let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        return today > .now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    private var start: Date { mode == Mode.finishBy.rawValue ? chosen.addingTimeInterval(-duration - Self.warmUp) : chosen }
    private var finish: Date { start.addingTimeInterval(duration + Self.warmUp) }
    private var tooSoon: Bool { start < Date.now.addingTimeInterval(60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Plan this print").font(Typeface.title).foregroundStyle(Palette.paper)
                Text(SlicedName(file.displayName).title).font(Typeface.body).foregroundStyle(Palette.dust).lineLimit(1)
            }

            HStack(spacing: 28) {
                fact("Print time", duration > 0 ? Fmt.duration(duration) : String(localized: "Unknown"))
                fact("If you start now", duration > 0 ? String(localized: "Done at \(Self.time(Date.now.addingTimeInterval(duration + Self.warmUp)))") : "–")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .machined(radius: 12, fill: Palette.graphite)

            HStack(spacing: 12) {
                CapsulePicker(selection: $mode, options: [(Mode.finishBy.rawValue, "Finish by"), (Mode.startAt.rawValue, "Start at")])
                PlateMenu(selection: $hour, options: (0..<24).map { ($0, String(format: "%02d", $0)) })
                    .frame(width: 80)
                Text(verbatim: ":").font(Typeface.number(18)).foregroundStyle(Palette.dust)
                PlateMenu(selection: $minute, options: stride(from: 0, to: 60, by: 5).map { ($0, String(format: "%02d", $0)) })
                    .frame(width: 80)
                Spacer()
            }

            if duration > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    if tooSoon {
                        Label("That's sooner than the print takes. Started now, it would be done at \(Self.time(Date.now.addingTimeInterval(duration + Self.warmUp))).",
                              systemImage: "exclamationmark.circle.fill")
                            .font(Typeface.bodyStrong).foregroundStyle(Palette.warm)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Starts \(Self.day(start)) at \(Self.time(start)), done around \(Self.time(finish)).")
                            .font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
                        Text("Includes about 5 minutes to heat up. OctoMac needs to be open at the start time.")
                            .font(Typeface.caption).foregroundStyle(Palette.faint)
                    }
                }
            } else {
                Text("OctoPrint doesn't know this file's print time yet, so OctoMac can only start it at a set time.")
                    .font(Typeface.caption).foregroundStyle(Palette.warm)
            }

            Toggle(isOn: $bedClear) {
                Text("The bed is clear and ready to print on").font(Typeface.bodyStrong).foregroundStyle(Palette.paper)
            }
            .toggleStyle(.switch)
            .tint(Palette.accent)

            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.plateQuiet).keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    session.schedule(file, start: start, finish: finish)
                    dismiss()
                } label: {
                    Label("Schedule", systemImage: "clock")
                }
                .buttonStyle(.plate(filament))
                .keyboardShortcut(.defaultAction)
                .disabled(!bedClear || tooSoon || (duration == 0 && mode == Mode.finishBy.rawValue))
            }
        }
        .padding(26)
        .frame(width: 520)
        .background(Palette.extrusion)
        .onAppear {
            if mode == Mode.startAt.rawValue {
                // A sensible start: the next quarter hour.
                let next = Date.now.addingTimeInterval(15 * 60)
                hour = Calendar.current.component(.hour, from: next)
                minute = Calendar.current.component(.minute, from: next) / 5 * 5
            }
        }
    }

    private func fact(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Typeface.caption).foregroundStyle(Palette.faint)
            Text(value).font(Typeface.number(18)).foregroundStyle(Palette.paper)
        }
    }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    static func day(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? String(localized: "today") : Calendar.current.isDateInTomorrow(date) ? String(localized: "tomorrow")
            : date.formatted(.dateTime.weekday(.wide))
    }
}

/// The scheduled start, shown where you'd press Print, with a way to call it off.
struct ScheduledBanner: View {
    let session: PrinterSession
    let scheduled: PrinterJournal.Scheduled

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill").foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(scheduled.name) starts \(ScheduleSheet.day(scheduled.start)) at \(ScheduleSheet.time(scheduled.start))")
                    .font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1)
                Text("Done around \(ScheduleSheet.time(scheduled.finish)). Keep OctoMac open.")
                    .font(Typeface.caption).foregroundStyle(Palette.faint)
            }
            Spacer(minLength: 8)
            Button("Cancel") { session.cancelSchedule() }.buttonStyle(.plateQuiet).controlSize(.small)
        }
        .padding(12)
        .machined(radius: 12, fill: Palette.graphite)
    }
}
