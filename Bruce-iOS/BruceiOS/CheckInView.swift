import AVFoundation
import SwiftUI

/// Camera QR reader: AVCaptureSession + AVCaptureMetadataOutput (QR only).
/// (The macOS app uses Vision on raw frames; on iPhone the metadata output is cheaper.)
final class QRScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    enum State: Equatable { case idle, running, denied, unavailable(String) }

    @Published var state: State = .idle
    let session = AVCaptureSession()
    var onCode: ((String) -> Void)?

    private let queue = DispatchQueue(label: "qr.scanner")
    private var lastCode: String?
    private var lastTime = Date.distantPast
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async { ok ? self.configureAndRun() : (self.state = .denied) }
            }
        default: state = .denied
        }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
        if state == .running { state = .idle }
    }

    private func configureAndRun() {
        queue.async {
            if !self.configured {
                guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ?? AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: dev), self.session.canAddInput(input) else {
                    DispatchQueue.main.async { self.state = .unavailable("No camera available on this device.") }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                self.session.addInput(input)
                let out = AVCaptureMetadataOutput()
                if self.session.canAddOutput(out) {
                    self.session.addOutput(out)
                    out.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                    out.metadataObjectTypes = [.qr]
                }
                self.session.commitConfiguration()
                self.configured = true
            }
            self.session.startRunning()
            DispatchQueue.main.async { self.state = .running }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let code = objects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        // Debounce: same code at most every 5 s.
        if code == lastCode, Date().timeIntervalSince(lastTime) < 5 { return }
        lastCode = code; lastTime = Date()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onCode?(code)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.preview.session = session
        v.preview.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Corner brackets of the scanner viewfinder.
struct ScanCorners: Shape {
    func path(in r: CGRect) -> Path {
        let l: CGFloat = 48
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.minX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - l))
        return p
    }
}

/// Check in tab: the camera QR scanner only (as in the original). Every scan asks for confirmation
/// (`askCheckIn`) and sends a real check-in when logged in. Quick check-in lives in the Home top bar.
struct CheckInTab: View {
    var body: some View {
        CheckInScanner(inSheet: false).toolbar(.hidden, for: .navigationBar)
    }
}

struct CheckInScanner: View {
    @Environment(AppModel.self) var m
    @StateObject private var scanner = QRScanner()
    var inSheet = true

    var body: some View {
        ZStack {
            camera.ignoresSafeArea()
            ScanCorners().stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .frame(width: 240, height: 240)
                .shadow(color: .black.opacity(0.3), radius: 6)
            VStack(spacing: 12) {
                HStack {
                    Text("CHECK IN").font(Theme.screenTitle(26)).foregroundStyle(.white)
                    Spacer()
                    if inSheet { Button(role: .close) { scanner.stop(); m.dismissSheets() }.buttonStyle(.glass) }
                }
                Label("Aim at the QR code at the studio door and hold still until it has been read", systemImage: "qrcode.viewfinder")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.clear, in: .rect(cornerRadius: 22))
                Spacer()
            }
            .padding(Theme.gutter)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            scanner.onCode = { handle($0) }
            scanner.start()
        }
        .onDisappear { scanner.stop() }
    }

    @ViewBuilder var camera: some View {
        if scanner.state == .running {
            CameraPreview(session: scanner.session)
        } else {
            ZStack {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 14) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 50, weight: .light))
                    switch scanner.state {
                    case .denied:
                        Text("Camera access is off. Allow it in Settings to scan the door QR code.")
                        Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                            .buttonStyle(.glass)
                    case .unavailable(let s): Text(s)
                    default: ProgressView()
                    }
                }
                .font(.system(size: 15)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.85))
                .padding(40)
            }
        }
    }

    func handle(_ code: String) {
        guard m.confirm == nil else { return }
        guard let t = m.target(forScanned: code) else { m.flash("Not a Bruce check-in QR code"); return }
        m.askCheckIn(t)
    }
}

// MARK: - Quick check-in (Home top bar): one suggestion + "Other studios"

struct QuickCheckInSheet: View {
    @Environment(AppModel.self) var m
    @EnvironmentObject var loc: LocationProvider
    @State private var showAll = AppModel.demo && AppModel.setting("BRUCE_SCREEN") == "checkinall"

    var body: some View {
        let suggestion = m.suggestedCheckIn(location: loc.authorized ? m.userLocation : nil)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let sug = suggestion {
                    SuggestedCheckInCard(suggestion: sug)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "figure.walk.arrival").font(.system(size: 40, weight: .light)).foregroundStyle(Theme.secondary)
                        Text("No booking with an open check-in window and no recent visit. Pick a studio below or scan the door QR code.")
                            .font(.system(size: 15)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(24)
                    .glassEffect(.regular, in: .rect(cornerRadius: 30))
                }
                if !loc.authorized && suggestion?.kind != .booking {
                    HStack {
                        Text("Suggest the gym you're at").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        Spacer()
                        UseLocationButton()
                    }
                    .padding(.horizontal, 6)
                }
                Button { showAll = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "list.bullet").font(.system(size: 18)).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Other studios").font(.system(size: 17, weight: .semibold))
                            Text("Bookings, recent visits and all check-in studios").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
            }
            .padding(Theme.gutter)
        }
        .sheetChrome("Check in")
        .navigationDestination(isPresented: $showAll) { OtherStudiosView() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { m.present(.checkIn) } label: { Image(systemName: "qrcode.viewfinder") }.accessibilityLabel("Scan QR code")
            }
        }
    }
}

/// One large glass card: studio, reason, lime "Check in" (still confirmed by an alert).
struct SuggestedCheckInCard: View {
    @Environment(AppModel.self) var m
    let suggestion: CheckInSuggestion
    var body: some View {
        let t = suggestion.target
        VStack(alignment: .leading, spacing: 14) {
            Label(suggestion.reason, systemImage: icon)
                .font(.system(size: 13, weight: .heavy).width(.expanded)).textCase(.uppercase)
                .foregroundStyle(suggestion.kind == .booking ? Color.black : Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(suggestion.kind == .booking ? Theme.lime : Theme.chipGrey))
            Text(t.name).font(.system(size: 26, weight: .black).width(.expanded)).lineLimit(2).minimumScaleFactor(0.7)
            if !t.subtitle.isEmpty, suggestion.kind == .booking || !t.subtitle.hasPrefix("Checked in") {
                Text(t.subtitle).font(.system(size: 15)).foregroundStyle(Theme.secondary)
            }
            LimeButton(title: "Check in", systemImage: "checkmark.circle.fill") { m.askCheckIn(t) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }
    var icon: String {
        switch suggestion.kind {
        case .booking: return "calendar.badge.checkmark"
        case .nearby: return "location.fill"
        case .lastVisited: return "clock.arrow.circlepath"
        }
    }
}

/// Searchable list: Pinned, Today's bookings, Recent (last 5), All (alphabetical, door or QR id known).
struct OtherStudiosView: View {
    @Environment(AppModel.self) var m
    @State private var query = ""

    func matches(_ t: CheckInTarget) -> Bool {
        query.isEmpty || t.name.localizedCaseInsensitiveContains(query) || t.subtitle.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        let pinned = m.pinnedCheckInTargets.filter(matches)
        let today = m.todaysBookingTargets.filter(matches)
        let recent = m.recentCheckInTargets.filter(matches)
        let all = m.allCheckInTargets.filter(matches)
        List {
            if !pinned.isEmpty { section("Pinned", pinned) }
            if !today.isEmpty { section("Today's bookings", today) }
            if !recent.isEmpty { section("Recent", recent) }
            section("All", all)
            if m.studios.isEmpty && m.isLoggedIn {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search studios")
        .navigationTitle("Other studios").navigationBarTitleDisplayMode(.inline)
    }

    func section(_ title: String, _ list: [CheckInTarget]) -> some View {
        Section(title) {
            ForEach(list) { t in
                HStack(spacing: 12) {
                    Image(systemName: t.door != nil ? "door.left.hand.open" : "qrcode")
                        .foregroundStyle(Theme.secondary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(t.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            if m.isCheckInPinned(t.studioId) { Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(Theme.limeInk) }
                        }
                        if !t.subtitle.isEmpty { Text(t.subtitle).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(1) }
                    }
                    Spacer()
                    Button { m.askCheckIn(t) } label: { Text("Check in").font(.system(size: 13, weight: .bold)).foregroundStyle(.black) }
                        .buttonStyle(.glassProminent).tint(Theme.lime)
                }
                .swipeActions(edge: .leading) {
                    Button { m.toggleCheckInPin(t.studioId) } label: {
                        Label(m.isCheckInPinned(t.studioId) ? "Unpin" : "Pin", systemImage: m.isCheckInPinned(t.studioId) ? "pin.slash" : "pin")
                    }
                    .tint(Theme.limeInk)
                }
            }
        }
    }
}
