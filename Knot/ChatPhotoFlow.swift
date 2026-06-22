//
//  ChatPhotoFlow.swift
//  Knot
//
//  Custom photo-attachment + camera flow for the chat composer:
//   1. PhotoAttachSheet   — half-height bottom sheet (Take Photo / Choose from Gallery)
//   2. ChatGalleryPicker  — full-screen multi-select Photos grid with order badges
//   3. ChatCameraView     — full-screen AVFoundation camera (photo + video modes)
//
//  All styling matches the app's dark theme + forest-green accent (Color.knotAccent).
//

import SwiftUI
import Combine
import Photos
import AVFoundation
import AVKit

// MARK: - 1. Attach Source Sheet

/// Half-height bottom sheet shown when the composer's photo icon is tapped.
/// Offers "Take Photo" and "Choose from Gallery". The parent presents the
/// matching full-screen flow from the callbacks.
struct PhotoAttachSheet: View {
    var onTakePhoto    : () -> Void
    var onChooseGallery: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Grabber
            Capsule().fill(Color.knotMuted.opacity(0.5))
                .frame(width: 38, height: 5)
                .padding(.top, 10).padding(.bottom, 18)

            VStack(spacing: 4) {
                Text("Add photos")
                    .font(.system(size: 20, weight: .bold)).foregroundColor(.primary)
                Text("Share a moment in this chat")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .padding(.bottom, 22)

            VStack(spacing: 12) {
                sourceRow(icon: "camera.fill", title: "Take Photo",
                          subtitle: "Use the camera") {
                    dismiss(); onTakePhoto()
                }
                sourceRow(icon: "photo.on.rectangle.angled", title: "Choose from Gallery",
                          subtitle: "Pick from your library") {
                    dismiss(); onChooseGallery()
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 12)

            Button(action: { dismiss() }) {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(.primary)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Color.knotWell).cornerRadius(14)
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.knotBackground)
    }

    private func sourceRow(icon: String, title: String, subtitle: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.knotAccent).frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.knotOnAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(.primary)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(Color.knotMuted)
            }
            .padding(14)
            .background(Color.knotSurface)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.knotBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 2. Gallery Picker

/// Loads the user's photo library and exposes assets + thumbnail requests.
@MainActor
final class GalleryModel: ObservableObject {
    @Published var assets: [PHAsset] = []
    @Published var status: PHAuthorizationStatus = .notDetermined

    private let imageManager = PHCachingImageManager()

    func load() {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                Task { @MainActor in
                    self?.status = newStatus
                    if newStatus == .authorized || newStatus == .limited { self?.fetch() }
                }
            }
        } else {
            status = current
            if current == .authorized || current == .limited { fetch() }
        }
    }

    private func fetch() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var fetched: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in fetched.append(asset) }
        assets = fetched
    }

    /// Thumbnail for a grid cell.
    func requestThumbnail(for asset: PHAsset, side: CGFloat,
                          completion: @escaping (UIImage?) -> Void) {
        let scale = UIScreen.main.scale
        let target = CGSize(width: side * scale, height: side * scale)
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = true
        imageManager.requestImage(for: asset, targetSize: target, contentMode: .aspectFill,
                                  options: opts) { img, _ in
            completion(img)
        }
    }

    /// Full-size images for the chosen assets, returned in the given order.
    func requestFullImages(identifiers: [String], completion: @escaping ([UIImage]) -> Void) {
        let byID = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        let chosen = identifiers.compactMap { byID[$0] }
        guard !chosen.isEmpty else { completion([]); return }

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.isSynchronous = false
        // Cap the longest edge so uploads stay reasonable.
        let maxEdge: CGFloat = 2000 * UIScreen.main.scale

        var results = [Int: UIImage]()
        let group = DispatchGroup()
        for (idx, asset) in chosen.enumerated() {
            group.enter()
            let target = CGSize(width: maxEdge, height: maxEdge)
            imageManager.requestImage(for: asset, targetSize: target, contentMode: .aspectFit,
                                      options: opts) { img, info in
                // opportunistic can call twice; only finish on the final (non-degraded) result.
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if degraded { return }
                if let img { results[idx] = img }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let ordered = (0..<chosen.count).compactMap { results[$0] }
            completion(ordered)
        }
    }
}

/// Full-screen multi-select photo grid with numbered selection badges.
struct ChatGalleryPicker: View {
    var onComplete: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = GalleryModel()

    /// Selected asset local identifiers, kept in tap order for the number badges.
    @State private var selected: [String] = []
    @State private var isLoadingResult = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.knotBackground.ignoresSafeArea()

                if model.status == .denied || model.status == .restricted {
                    permissionDenied
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(model.assets, id: \.localIdentifier) { asset in
                                GalleryCell(
                                    asset: asset,
                                    model: model,
                                    selectionIndex: selected.firstIndex(of: asset.localIdentifier)
                                )
                                .onTapGesture { toggle(asset) }
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.immediately)
                }

                if isLoadingResult {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView().tint(.white).scaleEffect(1.3)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selected.isEmpty { confirmBar }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.primary)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Recents").font(.system(size: 16, weight: .semibold)).foregroundColor(.primary)
                        Text("\(selected.count) selected").font(.caption2).foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: confirm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(selected.isEmpty ? Color.knotMuted : Color.knotAccent)
                    }
                    .disabled(selected.isEmpty || isLoadingResult)
                }
            }
            .toolbarBackground(Color.knotSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { model.load() }
    }

    private var confirmBar: some View {
        Button(action: confirm) {
            Text("Add \(selected.count) photo\(selected.count == 1 ? "" : "s")")
                .font(.system(size: 16, weight: .semibold)).foregroundColor(Color.knotOnAccent)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Color.knotAccent).cornerRadius(14)
        }
        .disabled(isLoadingResult)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.knotSurface.ignoresSafeArea(edges: .bottom))
    }

    private var permissionDenied: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundColor(Color.knotMuted)
            Text("Photo access is off").font(.headline).foregroundColor(.primary)
            Text("Enable photo access in Settings to choose from your gallery.")
                .font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .fontWeight(.semibold).foregroundColor(Color.knotAccent)
        }
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if let i = selected.firstIndex(of: id) {
            selected.remove(at: i)
        } else {
            selected.append(id)
        }
    }

    private func confirm() {
        guard !selected.isEmpty, !isLoadingResult else { return }
        isLoadingResult = true
        model.requestFullImages(identifiers: selected) { images in
            isLoadingResult = false
            guard !images.isEmpty else { return }
            onComplete(images)
            dismiss()
        }
    }
}

/// One grid thumbnail with selection chrome.
private struct GalleryCell: View {
    let asset: PHAsset
    @ObservedObject var model: GalleryModel
    let selectionIndex: Int?

    @State private var thumb: UIImage? = nil
    private var isSelected: Bool { selectionIndex != nil }

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                Color.knotSurface
                if let thumb {
                    Image(uiImage: thumb)
                        .resizable().scaledToFill()
                        .frame(width: side, height: side)
                        .clipped()
                        .scaleEffect(isSelected ? 0.88 : 1.0)
                        .animation(.easeOut(duration: 0.15), value: isSelected)
                }
                if isSelected {
                    Color.knotAccent.opacity(0.28)
                }
                // Selection badge
                VStack {
                    HStack {
                        Spacer()
                        if let idx = selectionIndex {
                            ZStack {
                                Circle().fill(Color.knotAccent).frame(width: 24, height: 24)
                                Text("\(idx + 1)")
                                    .font(.system(size: 12, weight: .bold)).foregroundColor(Color.knotOnAccent)
                            }
                        } else {
                            Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                                .frame(width: 24, height: 24)
                        }
                    }
                    Spacer()
                }
                .padding(6)
            }
            .frame(width: side, height: side)
            .clipped()
            .onAppear {
                model.requestThumbnail(for: asset, side: side) { img in
                    if let img { self.thumb = img }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - 3. Camera

enum CameraMode { case photo, video }

/// Owns the AVCaptureSession and drives capture. Video is recorded video-only
/// (no microphone) — the chat sends photos; video mode exists for the UI state.
/// Not @MainActor: AVFoundation work runs on a dedicated session queue; @Published
/// state is always mutated back on the main thread.
final class CameraModel: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published var isConfigured = false
    @Published var flashOn      = false
    @Published var isRecording  = false
    @Published var mode: CameraMode = .photo
    @Published var zoom: CGFloat = 1.0
    @Published var permissionDenied = false

    private let sessionQueue = DispatchQueue(label: "knot.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var photoCompletion: ((UIImage) -> Void)?
    private var currentRecordingURL: URL?
    /// Called (on main) with the recorded clip URL when video recording finishes.
    var onVideoFinished: ((URL) -> Void)?

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    // MARK: Lifecycle

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            requestAudioThenConfigure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.requestAudioThenConfigure() }
                else { self?.onMain { self?.permissionDenied = true } }
            }
        default:
            permissionDenied = true
        }
    }

    /// Best-effort microphone access so recorded video has sound. Recording still
    /// works (video-only) if the user declines, so this never blocks the camera.
    private func requestAudioThenConfigure() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in self?.configureAndRun() }
        } else {
            configureAndRun()
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            // `.high` supports BOTH a photo output and a movie file output. The
            // `.photo` preset is incompatible with AVCaptureMovieFileOutput, which
            // is why video recording silently failed before.
            self.session.sessionPreset = .high

            if let input = self.makeInput(position: self.position) {
                if self.session.canAddInput(input) { self.session.addInput(input) }
                self.videoInput = input
            }
            // Best-effort audio input for video sound.
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
            }
            if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
            if self.session.canAddOutput(self.movieOutput) { self.session.addOutput(self.movieOutput) }

            self.session.commitConfiguration()
            self.session.startRunning()
            self.onMain { self.isConfigured = true }
        }
    }

    private func makeInput(position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return nil }
        return input
    }

    // MARK: Controls

    func toggleFlash() { flashOn.toggle() }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let nextPosition: AVCaptureDevice.Position = (self.position == .back) ? .front : .back
            guard let input = self.makeInput(position: nextPosition) else { return }
            self.session.beginConfiguration()
            if let current = self.videoInput { self.session.removeInput(current) }
            if self.session.canAddInput(input) { self.session.addInput(input) }
            self.videoInput = input
            self.position = nextPosition
            self.session.commitConfiguration()
        }
    }

    /// Cycle 1× → 2× → 1× for a simple zoom pill.
    func cycleZoom() {
        let next: CGFloat = zoom >= 2.0 ? 1.0 : 2.0
        zoom = next
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            try? device.lockForConfiguration()
            device.videoZoomFactor = max(1.0, min(next, device.activeFormat.videoMaxZoomFactor))
            device.unlockForConfiguration()
        }
    }

    func capturePhoto(completion: @escaping (UIImage) -> Void) {
        photoCompletion = completion
        let useFlash = (videoInput?.device.hasFlash == true) && flashOn
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            if useFlash { settings.flashMode = .on }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func startRecording() {
        onMain { self.isRecording = true }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("knot-\(UUID().uuidString).mov")
        currentRecordingURL = url
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    @discardableResult
    func stopRecording() -> URL? {
        onMain { self.isRecording = false }
        let previewURL = currentRecordingURL
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
        return previewURL
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              var image = UIImage(data: data) else { return }
        // Mirror selfies so they match the preview.
        if let cg = image.cgImage, output.connection(with: .video)?.isVideoMirrored == true {
            image = UIImage(cgImage: cg, scale: image.scale, orientation: .leftMirrored)
        }
        let result = image
        onMain {
            self.photoCompletion?(result)
            self.photoCompletion = nil
        }
    }
}

extension CameraModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        // AVCaptureMovieFileOutput frequently reports a non-nil error even on a
        // successful stop — trust AVErrorRecordingSuccessfullyFinishedKey.
        var success = true
        if let nsError = error as NSError? {
            success = (nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
        }
        guard success else { return }
        let finalURL = currentRecordingURL ?? outputFileURL
        currentRecordingURL = nil
        onMain { self.onVideoFinished?(finalURL) }
    }
}

// MARK: - Video poster helper

enum VideoPoster {
    /// First-frame poster image for a recorded clip (used as the message thumbnail).
    static func make(from url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 1200)
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// UIKit preview layer bridged into SwiftUI.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Full-screen camera UI matching the spec.
struct ChatCameraView: View {
    var onCapture: (UIImage) -> Void
    var onVideo  : ((URL) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CameraModel()

    @State private var showFlash = false
    @State private var recSeconds = 0
    @State private var recTimer: Timer? = nil
    @State private var didHandOffVideo = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.isConfigured {
                CameraPreview(session: model.session).ignoresSafeArea()
            }

            // Capture flash
            if showFlash { Color.white.ignoresSafeArea() }

            if model.permissionDenied {
                permissionDenied
            } else {
                controls
            }
        }
        .statusBarHidden(true)
        .onAppear {
            model.onVideoFinished = { url in
                recTimer?.invalidate(); recTimer = nil
                if didHandOffVideo { return }
                onVideo?(url)
                dismiss()
            }
            model.start()
        }
        .onDisappear { model.stop(); recTimer?.invalidate() }
    }

    // MARK: Controls overlay

    private var controls: some View {
        VStack {
            // Top bar
            HStack {
                circleButton(system: "xmark") { dismiss() }
                Spacer()
                // Recording-ready dot
                Circle().fill(model.isRecording ? Color.red : Color.white.opacity(0.8))
                    .frame(width: 8, height: 8)
                Spacer()
                circleButton(system: model.flashOn ? "bolt.fill" : "bolt.slash.fill") {
                    model.toggleFlash()
                }
            }
            .padding(.horizontal, 18).padding(.top, 8)

            if model.isRecording {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 10, height: 10)
                    Text("REC \(timeString(recSeconds))")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.black.opacity(0.5)).clipShape(Capsule())
                .padding(.top, 14)
            }

            Spacer()

            // Bottom controls — shutter centered; zoom + flip pinned trailing.
            VStack(spacing: 22) {
                ZStack {
                    shutterButton
                    HStack {
                        Spacer()
                        HStack(spacing: 14) {
                            zoomPill
                            circleButton(system: "arrow.triangle.2.circlepath", size: 44) {
                                model.flipCamera()
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)

                modeTabs
            }
            .padding(.bottom, 26)
        }
    }

    private var shutterButton: some View {
        Button(action: shutterTapped) {
            ZStack {
                Circle().strokeBorder(Color.white, lineWidth: 5).frame(width: 76, height: 76)
                if model.mode == .photo {
                    Circle().fill(Color.white).frame(width: 60, height: 60)
                } else if model.isRecording {
                    RoundedRectangle(cornerRadius: 6).fill(Color.red).frame(width: 30, height: 30)
                } else {
                    Circle().fill(Color.red).frame(width: 60, height: 60)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var zoomPill: some View {
        Button(action: { model.cycleZoom() }) {
            HStack(spacing: 3) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
                Text("\(model.zoom == 1.0 ? "1" : "2")×").font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.black.opacity(0.4)).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var modeTabs: some View {
        HStack(spacing: 28) {
            modeTab("VIDEO", mode: .video)
            modeTab("PHOTO", mode: .photo)
        }
    }

    private func modeTab(_ title: String, mode: CameraMode) -> some View {
        Button(action: {
            guard !model.isRecording else { return }
            model.mode = mode
        }) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(model.mode == mode ? Color.knotAccent : Color.white.opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    private func circleButton(system: String, size: CGFloat = 44,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.black.opacity(0.4)).frame(width: size, height: size)
                Image(systemName: system).font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }

    private var permissionDenied: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.system(size: 40)).foregroundColor(.white.opacity(0.7))
            Text("Camera access is off").font(.headline).foregroundColor(.white)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .fontWeight(.semibold).foregroundColor(Color.knotAccent)
            Button("Close") { dismiss() }.foregroundColor(.white.opacity(0.8)).padding(.top, 4)
        }
    }

    // MARK: Actions

    private func shutterTapped() {
        switch model.mode {
        case .photo:
            withAnimation(.easeIn(duration: 0.05)) { showFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeOut(duration: 0.15)) { showFlash = false }
            }
            model.capturePhoto { image in
                onCapture(image)
                dismiss()
            }
        case .video:
            if model.isRecording {
                let previewURL = model.stopRecording()
                recTimer?.invalidate(); recTimer = nil
                if let previewURL {
                    didHandOffVideo = true
                    onVideo?(previewURL)
                    dismiss()
                }
            } else {
                recSeconds = 0
                didHandOffVideo = false
                model.startRecording()
                recTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    recSeconds += 1
                }
            }
        }
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - 4. Photo Review (caption + multi-photo)

struct MediaReviewItem: Identifiable {
    let id = UUID()
    var image: UIImage
    var caption: String = ""
}

/// WhatsApp-style review screen shown after capturing/picking photos: full-screen
/// preview of the selected photo, a per-photo caption field, a thumbnail strip to
/// switch/delete photos, a camera button to add more, and Send.
struct MediaReviewView: View {
    let recipientName: String
    @State var items: [MediaReviewItem]
    var onSend: ([MediaReviewItem]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selected = 0
    @State private var showCamera = false
    @FocusState private var captionFocused: Bool

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { captionFocused = false }

            if items.indices.contains(selected) {
                Image(uiImage: items[selected].image)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { captionFocused = false }
            }

            VStack {
                HStack {
                    circleButton("xmark") { dismiss() }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8)

                Spacer()
                bottomBar
            }
        }
        .statusBarHidden(true)
        .fullScreenCover(isPresented: $showCamera) {
            ChatCameraView(onCapture: { img in
                items.append(MediaReviewItem(image: img))
                selected = items.count - 1
            })
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if items.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items.indices, id: \.self) { i in
                            ZStack {
                                Image(uiImage: items[i].image)
                                    .resizable().scaledToFill()
                                    .frame(width: 54, height: 54)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(i == selected ? Color.knotAccent : Color.clear, lineWidth: 2.5))
                                if i == selected {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.45))
                                        .frame(width: 54, height: 54)
                                    Image(systemName: "trash.fill")
                                        .font(.system(size: 18)).foregroundColor(.white)
                                }
                            }
                            .onTapGesture {
                                if i == selected { deleteSelected() } else { selected = i }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            HStack(spacing: 10) {
                Button(action: { showCamera = true }) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18)).foregroundColor(.white)
                }
                TextField("", text: captionBinding,
                          prompt: Text("Add a caption...").foregroundColor(.white.opacity(0.6)))
                    .foregroundColor(.white)
                    .focused($captionFocused)
                    .tint(Color.knotAccent)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
            .padding(.horizontal, 12)

            HStack {
                Text(recipientName)
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.white.opacity(0.12)).clipShape(Capsule())
                Spacer()
                Button(action: send) {
                    ZStack {
                        Circle().fill(Color.knotAccent).frame(width: 52, height: 52)
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 20, weight: .semibold)).foregroundColor(Color.knotOnAccent)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
        .background(
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    private var captionBinding: Binding<String> {
        Binding(
            get: { items.indices.contains(selected) ? items[selected].caption : "" },
            set: { if items.indices.contains(selected) { items[selected].caption = $0 } }
        )
    }

    private func deleteSelected() {
        guard items.indices.contains(selected) else { return }
        items.remove(at: selected)
        if items.isEmpty { dismiss(); return }
        selected = min(selected, items.count - 1)
    }

    private func send() {
        guard !items.isEmpty else { return }
        onSend(items)
        dismiss()
    }

    private func circleButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.black.opacity(0.4)).frame(width: 40, height: 40)
                Image(systemName: system).font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 5. Video Review

/// Preview a freshly-recorded clip, add a caption, and send.
struct VideoReviewView: View {
    let recipientName: String
    let videoURL: URL
    var onSend: (URL, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var caption = ""
    @State private var player: AVPlayer
    @State private var isPlayerReady = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var isPlaying = false
    @State private var timeObserverToken: Any?
    @State private var endObserverToken: NSObjectProtocol?
    @State private var prepareTask: Task<Void, Never>?
    @FocusState private var captionFocused: Bool

    init(recipientName: String, videoURL: URL, onSend: @escaping (URL, String) -> Void) {
        self.recipientName = recipientName
        self.videoURL = videoURL
        self.onSend = onSend
        _player = State(initialValue: AVPlayer())
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { captionFocused = false }
            Group {
                if isPlayerReady {
                    InlineVideoPreview(player: player)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { captionFocused = false }
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(Color.knotAccent)
                            .scaleEffect(1.15)
                        Text("Preparing video…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white.opacity(0.88))
                    }
                }
            }

            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.4)).frame(width: 40, height: 40)
                            Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8)

                Spacer()

                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            Button(action: togglePlayback) {
                                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Color.knotOnAccent)
                                    .frame(width: 34, height: 34)
                                    .background(Color.knotAccent)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!isPlayerReady)
                            .opacity(isPlayerReady ? 1 : 0.55)

                            Slider(
                                value: Binding(
                                    get: { currentTime },
                                    set: { newValue in
                                        currentTime = newValue
                                    }
                                ),
                                in: 0...max(duration, 0.1),
                                onEditingChanged: { editing in
                                    isScrubbing = editing
                                    if !editing {
                                        seek(to: currentTime)
                                    }
                                }
                            )
                            .tint(Color.knotAccent)
                            .disabled(!isPlayerReady)
                        }

                        HStack {
                            Text(timeString(currentTime))
                            Spacer()
                            Text(timeString(duration))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.88))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 12)

                    HStack(spacing: 10) {
                        Image(systemName: "video.fill").foregroundColor(.white.opacity(0.8))
                        TextField("", text: $caption,
                                  prompt: Text("Add a caption...").foregroundColor(.white.opacity(0.6)))
                            .foregroundColor(.white)
                            .tint(Color.knotAccent)
                            .focused($captionFocused)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.black.opacity(0.55)).clipShape(Capsule())
                    .padding(.horizontal, 12)

                    HStack {
                        Text(recipientName)
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Color.white.opacity(0.12)).clipShape(Capsule())
                        Spacer()
                        Button(action: {
                            onSend(videoURL, caption.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        }) {
                            ZStack {
                                Circle().fill(Color.knotAccent).frame(width: 52, height: 52)
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 20, weight: .semibold)).foregroundColor(Color.knotOnAccent)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 12)
            }
        }
        .statusBarHidden(true)
        .onAppear { configurePlayer() }
        .onDisappear { tearDownPlayer() }
    }

    private func configurePlayer() {
        prepareTask?.cancel()
        prepareTask = Task {
            await preparePlayer()
        }
    }

    private func tearDownPlayer() {
        prepareTask?.cancel()
        prepareTask = nil
        player.pause()
        isPlaying = false
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
            endObserverToken = nil
        }
    }

    private func loopAndPlay() {
        player.play()
        isPlaying = true
        if let token = endObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            currentTime = 0
            isPlaying = true
            player.seek(to: .zero); player.play()
        }
    }

    private func seek(to seconds: Double) {
        guard isPlayerReady else { return }
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func togglePlayback() {
        guard isPlayerReady else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    private func preparePlayer() async {
        isPlayerReady = false
        currentTime = 0
        duration = 0

        let asset = AVURLAsset(url: videoURL)

        for _ in 0..<80 {
            guard !Task.isCancelled else { return }

            do {
                let playable = try await asset.load(.isPlayable)
                let loadedDuration = try await asset.load(.duration)
                let seconds = loadedDuration.seconds

                if playable, seconds.isFinite, seconds > 0 {
                    let item = AVPlayerItem(asset: asset)
                    player.replaceCurrentItem(with: item)
                    duration = seconds
                    installTimeObserverIfNeeded()
                    isPlayerReady = true
                    loopAndPlay()
                    return
                }
            } catch {
                // Keep polling briefly while the recording file is finalized.
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        let fallbackItem = AVPlayerItem(url: videoURL)
        player.replaceCurrentItem(with: fallbackItem)
        installTimeObserverIfNeeded()
        isPlayerReady = true
        loopAndPlay()
    }

    private func installTimeObserverIfNeeded() {
        guard timeObserverToken == nil else { return }
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { time in
            guard !isScrubbing else { return }
            currentTime = time.seconds.isFinite ? time.seconds : 0
            if let item = player.currentItem {
                let seconds = item.duration.seconds
                if seconds.isFinite, seconds > 0 {
                    duration = seconds
                }
            }
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let safeSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = safeSeconds / 60
        let remainder = safeSeconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}

private struct InlineVideoPreview: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - 6. Full-screen Video Player (tapping a video bubble)

struct VideoPlayerScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
                .onAppear { player.play() }
                .onDisappear { player.pause() }
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.5)).frame(width: 40, height: 40)
                            Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        }
                    }
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }
        .statusBarHidden(true)
    }
}
