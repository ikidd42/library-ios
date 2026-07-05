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
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .ean8, .code128, .code39])],
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
            guard let payload = barcode.payloadStringValue else { return }
            let cleaned = payload.replacingOccurrences(of: "[^0-9Xx]", with: "", options: .regularExpression)

            print("[Scanner] Raw barcode: \(payload) → cleaned: \(cleaned) (length: \(cleaned.count))")

            var code: String?

            if cleaned.count == 13 && (cleaned.hasPrefix("978") || cleaned.hasPrefix("979")) {
                // Standard ISBN-13 / EAN-13 Bookland barcode — this IS the ISBN
                code = cleaned
            } else if cleaned.count == 10 {
                // Likely ISBN-10 — convert to ISBN-13
                code = isbn10toISBN13(cleaned)
            } else if cleaned.count == 12 || cleaned.count == 13 || cleaned.count == 8 {
                // UPC-A (12), non-Bookland EAN-13, or EAN-8
                // These are retail product codes, NOT ISBNs, but pass them through
                // and let the lookup service try to find the book anyway
                code = cleaned
            }

            if let code = code {
                print("[Scanner] Accepted barcode: \(code)")
                parent.scannedISBN = code
                parent.isPresented = false
            } else {
                print("[Scanner] Rejected barcode: \(cleaned)")
            }
        }

        /// Convert ISBN-10 to ISBN-13 by prepending 978 and recalculating check digit
        private func isbn10toISBN13(_ isbn10: String) -> String {
            let digits = "978" + isbn10.prefix(9)
            var sum = 0
            for (i, char) in digits.enumerated() {
                guard let d = char.wholeNumberValue else { return isbn10 }
                sum += (i % 2 == 0) ? d : d * 3
            }
            let check = (10 - (sum % 10)) % 10
            return digits + "\(check)"
        }
    }
}

/// A wrapper view that handles the scanner lifecycle and device capability check
struct BarcodeScannerSheet: View {
    @Binding var scannedISBN: String?
    @Environment(\.dismiss) private var dismiss

    @State private var isActive = false

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
        .onAppear {
            isActive = true
        }
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
