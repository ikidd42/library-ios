import SwiftUI
import Vision
import VisionKit

/// A SwiftUI wrapper around DataScannerViewController for scanning ISBN barcodes.
/// Requires iOS 16+ and a device with a camera.
struct BarcodeScannerView: UIViewControllerRepresentable {
    @Binding var scannedISBN: String?
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .code39])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        // Start scanning if not already running
        if !uiViewController.isScanning {
            try? uiViewController.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: BarcodeScannerView

        init(parent: BarcodeScannerView) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            switch item {
            case .barcode(let barcode):
                handleBarcode(barcode)
            default:
                break
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            // Auto-capture the first barcode detected
            for item in addedItems {
                switch item {
                case .barcode(let barcode):
                    handleBarcode(barcode)
                    return
                default:
                    break
                }
            }
        }

        private func handleBarcode(_ barcode: RecognizedItem.Barcode) {
            guard let payload = barcode.payloadStringValue,
                  let code = ISBN.lookupCode(fromScannedPayload: payload) else { return }
            parent.scannedISBN = code
            parent.isPresented = false
        }
    }
}

/// A wrapper view that handles the scanner lifecycle and device capability check
struct BarcodeScannerSheet: View {
    @Binding var scannedISBN: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    scannerView
                } else {
                    unsupportedView
                }
            }
            .navigationTitle("Scan ISBN Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var scannerView: some View {
        BarcodeScannerView(
            scannedISBN: $scannedISBN,
            isPresented: .init(
                get: { true },
                set: { if !$0 { dismiss() } }
            )
        )
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            Text("Point your camera at a book's ISBN barcode")
                .font(.callout)
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 40)
        }
    }

    private var unsupportedView: some View {
        ContentUnavailableView(
            "Scanner Not Available",
            systemImage: "barcode.viewfinder",
            description: Text("Barcode scanning requires a device with a camera.")
        )
    }
}
