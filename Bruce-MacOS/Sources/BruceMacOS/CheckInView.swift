import SwiftUI

struct CheckInView: View {
    @Environment(AppModel.self) var m
    @StateObject private var scanner = QRScanner()
    @State private var cameraOn = false

    var body: some View {
        VStack(spacing: 0) {
            NavBar(title: "Check in", leading: .close) { scanner.stop(); m.dismissSheets() }
            ZStack(alignment: .top) {
                Group {
                    if cameraOn && scanner.state == .running {
                        CameraPreview(session: scanner.session)
                    } else {
                        Color(white: 0.12).overlay {
                            VStack(spacing: 14) {
                                Image(systemName: "qrcode.viewfinder").font(.system(size: 54, weight: .light))
                                switch scanner.state {
                                case .denied: Text("Camera access denied. Enable it in System Settings › Privacy › Camera.")
                                case .unavailable(let s): Text(s)
                                default:
                                    Button { cameraOn = true; scanner.start() } label: {
                                        Text("Start camera").font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                                            .padding(.horizontal, 24).frame(height: 44).background(Capsule().fill(Theme.lime))
                                    }.buttonStyle(.plain)
                                }
                            }
                            .multilineTextAlignment(.center).padding(30).foregroundStyle(.white)
                        }
                    }
                }
                ScanCorners().stroke(Color.white, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    .frame(width: 210, height: 210).frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Aim at the QR code and hold still until it has been read")
                    .font(.system(size: 16)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 24).padding(.vertical, 12).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.25).opacity(0.92)))
                    .padding(.horizontal, Theme.gutter).padding(.top, 12)
            }
            .frame(maxHeight: .infinity)
            .clipped()
        }
        .onAppear {
            scanner.onCode = { code in handle(code) }
        }
        .onDisappear { scanner.stop() }
    }

    func handle(_ code: String) {
        guard m.confirm == nil else { return }
        guard let t = m.target(forScanned: code) else { m.flash("Not a Bruce check-in QR code"); return }
        scanner.stop()
        m.askCheckIn(t)
    }
}
