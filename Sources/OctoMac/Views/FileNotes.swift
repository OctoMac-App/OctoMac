import SwiftUI

/// One to five stars. Click a star to rate; click the same star again to clear it.
struct StarRating: View {
    @Binding var rating: Int?
    var size: CGFloat = 13
    var editable = true
    @State private var hovered: Int?

    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(1...5, id: \.self) { star in
                let lit = star <= (hovered ?? rating ?? 0)
                Image(systemName: lit ? "star.fill" : "star")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(lit ? Palette.warm : Palette.faint.opacity(0.6))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard editable else { return }
                        rating = rating == star ? nil : star
                    }
                    .onHover { if editable { hovered = $0 ? star : (hovered == star ? nil : hovered) } }
            }
        }
        .help(editable ? "Rate this print" : "")
    }
}

/// A file's rating and note, for a popover: what worked, what to change next time.
struct NoteEditor: View {
    let session: PrinterSession
    let path: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var note = PrinterJournal.Note()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Typeface.bodyStrong).foregroundStyle(Palette.paper).lineLimit(1)
            StarRating(rating: $note.rating, size: 18)
            TextEditor(text: $note.text)
                .font(Typeface.body)
                .foregroundStyle(Palette.paper)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 110)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.graphite))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.edge, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    if note.text.isEmpty {
                        Text("For next time, e.g. \u{201C}needs a brim\u{201D} or \u{201C}245\u{00B0} worked well\u{201D}")
                            .font(Typeface.body).foregroundStyle(Palette.faint)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                if session.note(for: path) != nil {
                    Button("Clear") {
                        session.setNote(PrinterJournal.Note(), for: path)
                        dismiss()
                    }
                    .buttonStyle(.plateQuiet)
                    .controlSize(.small)
                }
                Spacer()
                Button("Save") {
                    session.setNote(note, for: path)
                    dismiss()
                }
                .buttonStyle(.plate)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Palette.extrusion)
        .presentationBackground(Palette.extrusion)
        .onAppear { note = session.note(for: path) ?? PrinterJournal.Note() }
    }
}

/// A file's rating and note, read-only, with a button to edit them.
struct NoteSummary: View {
    let session: PrinterSession
    let path: String
    let title: String
    @State private var editing = false

    var body: some View {
        let note = session.note(for: path)
        Button { editing = true } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "note.text").foregroundStyle(Palette.faint).frame(width: 16)
                if let note {
                    VStack(alignment: .leading, spacing: 3) {
                        if note.rating != nil { StarRating(rating: .constant(note.rating), size: 11, editable: false) }
                        if !note.text.isEmpty {
                            Text(note.text).font(Typeface.body).foregroundStyle(Palette.dust)
                                .lineLimit(3).multilineTextAlignment(.leading)
                        }
                    }
                } else {
                    Text("Add a rating or note").font(Typeface.body).foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Your rating and note for this file")
        .popover(isPresented: $editing, arrowEdge: .bottom) { NoteEditor(session: session, path: path, title: title) }
    }
}
