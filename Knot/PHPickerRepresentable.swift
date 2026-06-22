import SwiftUI
import PhotosUI

// MARK: - Multi-Image Picker  (replaces PhotosPicker where binding is unreliable)
/// Wraps PHPickerViewController so images are delivered via a direct callback
/// rather than through a SwiftUI binding — more reliable on physical devices.
struct MultiImagePicker: UIViewControllerRepresentable {
    var maxSelectionCount: Int = 6
    var onImagesSelected: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImagesSelected: onImagesSelected) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit   = maxSelectionCount
        config.selection        = .ordered
        config.filter           = .images
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    /// Keep the coordinator's callback fresh so it always sees the latest SwiftUI state.
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        context.coordinator.onImagesSelected = onImagesSelected
    }

    // MARK: Coordinator
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onImagesSelected: ([UIImage]) -> Void
        init(onImagesSelected: @escaping ([UIImage]) -> Void) {
            self.onImagesSelected = onImagesSelected
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    self?.onImagesSelected([])
                }
                return
            }

            // Use a serial queue so dict writes are thread-safe;
            // group.leave() is always called AFTER the store completes.
            let serialQ = DispatchQueue(label: "ph.picker.image.load")
            let total   = results.count
            var loaded  = [Int: UIImage]()
            let group   = DispatchGroup()

            for (index, result) in results.enumerated() {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                    // serialQ.sync blocks until the store finishes before leave() runs
                    serialQ.sync {
                        if let img = object as? UIImage { loaded[index] = img }
                    }
                    group.leave()
                }
            }

            // Fires on main after every leave() — loaded is fully populated here
            group.notify(queue: .main) { [weak self] in
                let ordered = (0..<total).compactMap { loaded[$0] }
                guard !ordered.isEmpty else { return }
                self?.onImagesSelected(ordered)
            }
        }
    }
}

// MARK: - Single-Image Picker  (for profile photos, group avatars, etc.)
struct SingleImagePicker: UIViewControllerRepresentable {
    var onImageSelected: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(onImageSelected: onImageSelected) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit   = 1
        config.selection        = .ordered
        config.filter           = .images
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        context.coordinator.onImageSelected = onImageSelected
        context.coordinator.dismiss = dismiss
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onImageSelected: (UIImage) -> Void
        var dismiss: DismissAction?
        init(onImageSelected: @escaping (UIImage) -> Void) {
            self.onImageSelected = onImageSelected
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let result = results.first,
                  result.itemProvider.canLoadObject(ofClass: UIImage.self) else {
                DispatchQueue.main.async { [weak self] in self?.dismiss?() }
                return
            }
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                if let img = object as? UIImage {
                    DispatchQueue.main.async {
                        self?.onImageSelected(img)
                        self?.dismiss?()
                    }
                }
            }
        }
    }
}

// MARK: - Camera Picker  (take a photo in-app)
/// Wraps `UIImagePickerController` with `sourceType = .camera`. PHPicker cannot
/// access the camera, so this is required for the "Take Photo" option in chats
/// and listings. Returns a single captured image. Only present this when
/// `CameraPicker.isAvailable` is true (e.g. never on the Simulator).
struct CameraPicker: UIViewControllerRepresentable {
    var onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Whether a hardware camera is available on this device.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPicking info: [UIImagePickerController.InfoKey: Any]) {
            let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
            DispatchQueue.main.async { [parent] in
                if let image {
                    parent.onImageCaptured(image)
                }
                parent.dismiss()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            DispatchQueue.main.async { [parent] in
                parent.dismiss()
            }
        }
    }
}
