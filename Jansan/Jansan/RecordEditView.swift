import SwiftUI
import SwiftData
import JansanCore

/// 保存した記録の「対局日」と「ひとことメモ」を直す画面。
///
/// **点数は触らせない。** 直したいときは読み込んでから入力し直す方が確実で、
/// ここで書き換えられると履歴と表の食い違いが起きる。
struct RecordEditView: View {
    @Bindable var record: SavedGame
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var day: Date = .now
    @State private var hasDate = true
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("日付を入れる", isOn: $hasDate)
                        .accessibilityIdentifier("hasPlayedAt")
                    if hasDate {
                        DatePicker("対局した日", selection: $day, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                            .accessibilityIdentifier("playedAtPicker")
                    }
                } header: {
                    Text("日付")
                } footer: {
                    Text(hasDate
                         ? "・実際に打った日に直すと、期間で集計したときに正しく入ります\n・保存日時（\(record.savedAtLabel)）はそのまま残ります"
                         : "・日付未記入の記録は、集計の「全期間」にだけ入ります\n・CSVから取り込んだ記録は、未記入で入っています")
                }

                Section {
                    TextField("例：田中宅・4人・久々", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityIdentifier("noteField")
                } header: {
                    Text("ひとことメモ")
                } footer: {
                    Text("場所や面子、その日の出来事など。あとで探すときの手がかりになります。")
                }

                Section {
                    LabeledContent("成績", value: record.summaryLine)
                    LabeledContent("形式", value: record.shapeLabel)
                }
            }
            .navigationTitle("記録を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("やめる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.bold()
                }
            }
        }
        .onAppear {
            hasDate = !record.isDateUnknown
            day = hasDate ? record.effectivePlayedAt : .now
            note = record.note
        }
    }

    private func save() {
        record.playedAt = hasDate ? day : PlayedDate.unknown
        record.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        dismiss()
    }
}
