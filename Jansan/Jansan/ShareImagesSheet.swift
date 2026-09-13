import SwiftUI
import Photos
import JansanCore

/// 集計を画像にして、写真アプリへの保存と共有シートに渡す。
///
/// **画面と同じ部品をそのまま画像にする**（普通にスクリーンショットを撮ったのと同じ見た目）。
/// 以前は画像用に別の図（題名・期間の見出しつき）を描いていたが、画面と見た目が違い、
/// 全部の画像の上に同じ題名が載って邪魔だった（本人の指示で外した）。
///
/// **縦長1枚にはしない。** トークのプレビューで縮小されて数字が読めないので、部品ごとに分ける
@MainActor
struct ShareImagesSheet: View {
    struct Page {
        let caption: String
        let content: AnyView
    }

    let pages: [Page]
    /// いま画面に出ている明るさ。画像も同じにする（ダークモードで見ているならダークの画像）
    let colorScheme: ColorScheme

    /// 画面と同じ幅で描き、3倍で書き出す。スクリーンショットと同じ細かさになる
    static let pageWidth: CGFloat = 402

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
                    Text("画面と同じ見た目の\(pages.count)枚です。縦長1枚だとトークのプレビューで数字が読めないため、分けてあります。")
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
                            .accessibilityLabel("\(index + 1)枚目 \(pages[index].caption)")
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
        images = pages.compactMap { page in
            let view = page.content
                .padding(16)
                .frame(width: Self.pageWidth, alignment: .topLeading)
                .background(Palette.bg)
                .fontDesign(.rounded)
                .environment(\.colorScheme, colorScheme)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: Self.pageWidth, height: nil)
            renderer.scale = 3
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
