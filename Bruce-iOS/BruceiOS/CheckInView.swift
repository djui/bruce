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

/// Check in tab: the camera QR scanner with the suggested studio and "Other studios" below it, so scanning
/// and checking in by studio live in one place. Every check-in asks for confirmation (`askCheckIn`) and
/// sends a real check-in when logged in. Same top bar as the other tabs (title, Notifications, Menu), light
/// on the camera.
struct CheckInTab: View {
    @State private var showAll = AppModel.demo && AppModel.setting("BRUCE_SCREEN") == "checkinall"
    var body: some View {
        CheckInScanner(inSheet: false, showAll: $showAll)
            .bruceTitle("Check in")
            .toolbar { MainToolbarButtons() }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .environment(\.colorScheme, .dark)
            .navigationDestination(isPresented: $showAll) { OtherStudiosView() }
    }
}

struct CheckInScanner: View {
    @Environment(AppModel.self) var m
    @StateObject private var scanner = QRScanner()
    var inSheet = true
    var showAll: Binding<Bool>? = nil

    var body: some View {
        ZStack {
            camera.ignoresSafeArea()
            VStack(spacing: 12) {
                // The tab shows its title in the navigation bar; the sheet has no bar, so it draws its own.
                if inSheet {
                    HStack {
                        Text("CHECK IN").bruceScreenTitle(26).foregroundStyle(.white)
                        Spacer()
                        Button(role: .close) { scanner.stop(); m.dismissSheets() }.buttonStyle(.glass)
                    }
                }
                Label("Hold the camera steady over the QR code on the studio door", systemImage: "qrcode.viewfinder")
                    .bruceFont(15, weight: .medium).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.clear, in: .rect(cornerRadius: 22))
                Spacer(minLength: 8)
                ScanCorners().stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .frame(width: 220, height: 220)
                    .shadow(color: .black.opacity(0.3), radius: 6)
                    .overlay { if scanner.state != .running { cameraStatus.frame(width: 300) } }
                Spacer(minLength: 8)
                if let showAll { CheckInSuggestions(showAll: showAll) }
            }
            .padding(Theme.gutter)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            visible = true
            scanner.onCode = { handle($0) }
            if !coveredBySheet { scanner.start() }
        }
        .onDisappear { visible = false; scanner.stop() }
        // A sheet over the tab (the ticket after a check-in, notifications, menu) does not fire onDisappear, so the
        // camera kept running underneath. Pause it while covered: no camera use the user cannot see, and no live
        // video backdrop under the scanner's glass while the sheet animates in (TestFlight crash Oct 15 in the
        // system glass renderer right after a check-in).
        .onChange(of: coveredBySheet) { _, covered in
            guard visible else { return }
            if covered { scanner.stop() } else { scanner.start() }
        }
    }

    @State private var visible = false
    /// The tab scanner is covered by one of the model's sheets. The sheet variant is itself a sheet, so never.
    var coveredBySheet: Bool { !inSheet && !m.sheets.isEmpty }

    @ViewBuilder var camera: some View {
        if scanner.state == .running {
            CameraPreview(session: scanner.session)
        } else {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)
        }
    }

    /// Shown inside the viewfinder while the camera isn't running.
    var cameraStatus: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.viewfinder").bruceFont(50, weight: .light)
            switch scanner.state {
            case .denied:
                Text("Camera access is off. Allow it in Settings to scan the door QR code.")
                Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                    .buttonStyle(.glass)
            case .unavailable(let s): Text(s)
            default: ProgressView()
            }
        }
        .bruceFont(15).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.85))
    }

    func handle(_ code: String) {
        guard m.confirm == nil else { return }
        guard let t = m.target(forScanned: code) else { m.flash("Not a Bruce check-in QR code"); return }
        m.askCheckIn(t)
    }
}

// MARK: - Check in by studio (under the scanner): one suggestion + "Other studios"

struct CheckInSuggestions: View {
    @Environment(AppModel.self) var m
    @EnvironmentObject var loc: LocationProvider
    @Binding var showAll: Bool

    var body: some View {
        let suggestion = m.suggestedCheckIn(location: loc.authorized ? m.userLocation : nil)
        VStack(alignment: .leading, spacing: 10) {
            if let sug = suggestion {
                SuggestedCheckInCard(suggestion: sug)
            }
            if !loc.authorized && suggestion?.kind != .booking {
                HStack {
                    Text("Suggest the gym you're at").bruceFont(14).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    UseLocationButton()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .glassEffect(.clear, in: .rect(cornerRadius: 22))
            }
            Button { showAll = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "list.bullet").bruceFont(18).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Other studios").bruceFont(17, weight: .semibold)
                        Text("Bookings, recent visits and all check-in studios").bruceFont(13).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(.white)
                .padding(16).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
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
                .bruceFont(13, weight: .heavy, width: .expanded).textCase(.uppercase)
                .foregroundStyle(suggestion.kind == .booking ? Color.black : Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(suggestion.kind == .booking ? Theme.lime : Theme.chipGrey))
            Text(t.name).bruceFont(26, weight: .black, width: .expanded).lineLimit(2).minimumScaleFactor(0.7)
            if !t.subtitle.isEmpty, suggestion.kind == .booking || !t.subtitle.hasPrefix("Checked in") {
                Text(t.subtitle).bruceFont(15).foregroundStyle(Theme.secondary)
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
                            Text(t.name).bruceFont(16, weight: .semibold).lineLimit(1)
                            if m.isCheckInPinned(t.studioId) { Image(systemName: "pin.fill").bruceFont(11).foregroundStyle(Theme.limeInk) }
                        }
                        if !t.subtitle.isEmpty { Text(t.subtitle).bruceFont(13).foregroundStyle(Theme.secondary).lineLimit(1) }
                    }
                    Spacer()
                    Button { m.askCheckIn(t) } label: { Text("Check in").bruceFont(13, weight: .bold).foregroundStyle(.black) }
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
