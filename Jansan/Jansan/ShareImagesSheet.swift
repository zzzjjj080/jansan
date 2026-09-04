import SwiftUI
import Photos
import JansanCore

/// 3枚の画像を作って、写真アプリへの保存と共有シートに渡す。
///
/// 画像そのものの見た目は `ShareImageView`。ここは材料を集めて `ImageRenderer` に
/// 通すところだけを持つ。
@MainActor
struct ShareImagesSheet: View {
    let title: String
    let subtitle: String
    let latest: [ShareImageView.Row]
    let latestHeaders: [String]
    let totals: [ShareImageView.Row]
    let totalsHeaders: [String]
    let series: [(name: String, color: Color, points: [Int])]
    let decimalMode: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var images: [UIImage] = []
    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable {
        case idle, saving, saved, denied, failed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text("この3枚を送れます。縦長1枚だとトークのプレビューで数字が読めないため、分けてあります。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkDim)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
                            .accessibilityIdentifier("sharePreview\(index)")
                            .accessibilityLabel("\(index + 1)枚目 \(ShareImageView.Kind.allCases[index].caption)")
                    }
                }
                .padding(16)
            }
            .background(Palette.bg)
            .navigationTitle("画像で送る")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { actions }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .task { render() }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if images.isEmpty {
                ProgressView()
            } else {
                ShareLink(items: images.map { Image(uiImage: $0) }) { image in
                    SharePreview("雀算の記録", image: image)
                } label: {
                    Label("共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("shareImages")

                Button {
                    saveToPhotos()
                } label: {
                    Label(saveLabel, systemImage: saveIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(saveState == .saving || saveState == .saved)
                .accessibilityIdentifier("saveToPhotos")

                if saveState == .denied {
                    Text("写真へのアクセスが許可されていません。設定アプリ → 雀算 → 写真 から許可してください。共有からなら保存せずに送れます。")
                        .font(.caption)
                        .foregroundStyle(Palette.negative)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(16)
        .background(.bar)
    }

    private var saveLabel: String {
        switch saveState {
        case .idle, .denied, .failed: "写真に保存"
        case .saving: "保存しています"
        case .saved: "保存しました"
        }
    }

    private var saveIcon: String {
        saveState == .saved ? "checkmark.circle.fill" : "square.and.arrow.down"
    }

    // MARK: - 画像を作る

    private func render() {
        guard images.isEmpty else { return }
        images = ShareImageView.Kind.allCases.compactMap { kind in
            let view = ShareImageView(
                title: title,
                subtitle: subtitle,
                kind: kind,
                rows: kind == .latest ? latest : totals,
                series: series,
                decimalMode: decimalMode,
                headers: kind == .latest ? latestHeaders : totalsHeaders
            )
            let renderer = ImageRenderer(content: view)
            // 等倍だと文字がぼやける。2倍で900x1200 → 1800x2400
            renderer.scale = 2
            return renderer.uiImage
        }
    }

    // MARK: - 写真に保存

    private func saveToPhotos() {
        saveState = .saving
        let toSave = images
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in saveState = .denied }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                for image in toSave {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            } completionHandler: { success, _ in
                Task { @MainActor in saveState = success ? .saved : .failed }
            }
        }
    }
}
