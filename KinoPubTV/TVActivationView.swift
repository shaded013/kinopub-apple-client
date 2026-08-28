import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct TVActivationView: View {
  @EnvironmentObject private var session: TVSession

  var body: some View {
    ZStack {
      TVTheme.background.ignoresSafeArea()

      LinearGradient(colors: [TVTheme.accent.opacity(0.28), .clear],
                     startPoint: .topLeading,
                     endPoint: .center)
        .ignoresSafeArea()

      HStack(spacing: 110) {
        VStack(alignment: .leading, spacing: 28) {
          Label("KINOPUB", systemImage: "play.rectangle.fill")
            .font(.headline.weight(.black))
            .foregroundStyle(TVTheme.accent)

          Text("Bring your cinema\nto the big screen.")
            .font(.system(size: 64, weight: .bold, design: .rounded))
            .tracking(-1.5)

          Text("Scan the code with your phone, then approve this Apple TV in your KinoPub account.")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 610, alignment: .leading)

          if let error = session.errorMessage {
            Text(error)
              .font(.body)
              .foregroundStyle(.red)
              .frame(maxWidth: 610, alignment: .leading)

            Button("Try again") {
              session.retryActivation()
            }
            .buttonStyle(.borderedProminent)
            .tint(TVTheme.accent)
            .accessibilityIdentifier("activation.retry")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        activationCard
          .frame(width: 600)
      }
      .padding(.horizontal, 110)
      .padding(.vertical, 75)
    }
    .task {
      if session.phase == .signedOut, session.deviceCode.isEmpty {
        session.beginActivation()
      }
    }
  }

  private var activationCard: some View {
    VStack(spacing: 30) {
      if session.deviceCode.isEmpty {
        ProgressView()
          .controlSize(.large)
          .frame(height: 240)

        Text("Requesting a device code…")
          .font(.title3)
          .foregroundStyle(.secondary)
      } else {
        if let image = QRCode.make(from: session.verificationURL) {
          Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .frame(width: 240, height: 240)
            .padding(18)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .accessibilityLabel("QR code for device activation")
        }

        Text(session.deviceCode)
          .font(.system(size: 66, weight: .bold, design: .monospaced))
          .tracking(10)
          .accessibilityIdentifier("activation.deviceCode")
          .accessibilityLabel("Device code \(session.deviceCode)")

        Text(session.verificationURL)
          .font(.headline)
          .foregroundStyle(TVTheme.accent)
      }
    }
    .padding(50)
    .frame(maxWidth: .infinity, minHeight: 560)
    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 42))
    .overlay {
      RoundedRectangle(cornerRadius: 42)
        .stroke(Color.white.opacity(0.12), lineWidth: 1)
    }
  }
}

private enum QRCode {
  private static let context = CIContext()
  private static let filter = CIFilter.qrCodeGenerator()

  static func make(from value: String) -> UIImage? {
    guard !value.isEmpty else { return nil }
    filter.message = Data(value.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
          let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
    return UIImage(cgImage: cgImage)
  }
}
