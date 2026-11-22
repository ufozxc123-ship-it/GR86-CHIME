import Foundation
import CoreLocation
import AVFoundation
import Combine

@MainActor
final class SpeedTracker: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var speedKmh: Double = 0
    @Published var accuracy: Double?
    @Published var threshold: Double = 105
    @Published var volume: Double = 0.35
    @Published var repeatInterval: Double = 0.8
    @Published var isMuted = false
    @Published var isRunning = false
    @Published var isSimulating = false
    @Published var simulatedSpeed: Double = 0
    @Published var status = "GPS 대기 중"
    @Published var warning = "SPEED STANDBY"

    private let locationManager = CLLocationManager()
    private let chime = AE86ChimePlayer()
    private var chimeTimer: DispatchSourceTimer?
    private var requestedAlways = false
    private var hasStartedLocation = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
    }

    var displayedSpeed: Double { isSimulating ? simulatedSpeed : speedKmh }
    var isOverLimit: Bool { displayedSpeed >= threshold }

    func start() {
        guard !isRunning else { return }
        chime.prepareAudioSession()
        switch locationManager.authorizationStatus {
        case .notDetermined:
            status = "위치 권한 요청 중"
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            requestAlwaysIfNeeded()
        case .authorizedAlways:
            beginLocationUpdates()
        case .denied, .restricted:
            status = "위치 권한이 필요합니다"
        @unknown default:
            status = "위치 권한 상태 확인 필요"
        }
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        hasStartedLocation = false
        isRunning = false
        stopChimeLoop()
        status = "측정 중지됨"
        speedKmh = 0
    }

    func toggleMute() {
        isMuted.toggle()
        syncChimeLoop()
    }

    func testChime() {
        chime.prepareAudioSession()
        chime.play(volume: volume)
    }

    func setThreshold(_ value: Double) {
        threshold = value
        syncChimeLoop()
    }

    func setVolume(_ value: Double) {
        volume = value
    }

    func setRepeatInterval(_ value: Double) {
        repeatInterval = value
        if chimeTimer != nil {
            stopChimeLoop()
            syncChimeLoop()
        }
    }

    func setSimulation(_ enabled: Bool) {
        isSimulating = enabled
        if !enabled { simulatedSpeed = 0 }
        syncChimeLoop()
    }

    func setSimulatedSpeed(_ value: Double) {
        simulatedSpeed = value
        isSimulating = true
        syncChimeLoop()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            beginLocationUpdates()
        case .authorizedWhenInUse:
            requestAlwaysIfNeeded()
        case .denied, .restricted:
            status = "설정에서 위치 권한을 허용해 주세요"
        case .notDetermined:
            status = "위치 권한 대기 중"
        @unknown default:
            status = "위치 권한 상태 확인 필요"
        }
    }

    private func requestAlwaysIfNeeded() {
        guard !requestedAlways else {
            status = "위치 접근을 '항상 허용'으로 변경해 주세요"
            return
        }
        requestedAlways = true
        status = "백그라운드 사용을 위해 '항상 허용'이 필요합니다"
        locationManager.requestAlwaysAuthorization()
    }

    private func beginLocationUpdates() {
        guard !hasStartedLocation else { return }
        hasStartedLocation = true
        isRunning = true
        status = "GPS 신호 수신 중..."
        locationManager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else { return }
        accuracy = location.horizontalAccuracy
        if !isSimulating, location.speed >= 0 {
            speedKmh = max(0, location.speed * 3.6)
        }
        status = "GPS 연동됨 · 백그라운드 위치 추적"
        syncChimeLoop()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "GPS 신호 일시 손실"
    }

    private func syncChimeLoop() {
        let shouldPlay = isRunning && isOverLimit && !isMuted && volume > 0
        if shouldPlay {
            guard chimeTimer == nil else { return }
            chime.play(volume: volume)
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + repeatInterval, repeating: repeatInterval, leeway: .milliseconds(30))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                if self.isRunning && self.isOverLimit && !self.isMuted && self.volume > 0 {
                    self.chime.play(volume: self.volume)
                } else {
                    self.stopChimeLoop()
                }
            }
            chimeTimer = timer
            timer.resume()
        } else {
            stopChimeLoop()
        }
    }

    private func stopChimeLoop() {
        chimeTimer?.setEventHandler {}
        chimeTimer?.cancel()
        chimeTimer = nil
    }
}

private final class AE86ChimePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isPrepared = false
    private let sampleRate = 44_100.0

    func prepareAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if !isPrepared {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: nil)
                try engine.start()
                isPrepared = true
            } else if !engine.isRunning {
                try engine.start()
            }
        } catch {
            print("Audio setup failed: \(error)")
        }
    }

    func play(volume: Double) {
        prepareAudioSession()
        guard isPrepared, let buffer = makeChimeBuffer() else { return }
        player.volume = Float(min(1, max(0, volume)))
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func makeChimeBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.92
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames

        // Port of the supplied web chime: two bright metallic notes, 350 ms apart.
        let firstBase = 2489.02 * pow(2, 1.0 / 12.0) * pow(2, -1.0 / 48.0) * pow(2, -1.0 / 12.0) * pow(2, 1.0 / 48.0) * pow(2, 1.0 / 48.0)
        let secondBase = 2217.46 * pow(2, 1.0 / 12.0) * pow(2, -1.0 / 48.0) * pow(2, -1.0 / 12.0) * pow(2, 1.0 / 48.0) * pow(2, -1.0 / 48.0)
        let firstScale = 0.72 * 0.7
        let secondScale = 0.8 * 0.7 * 0.76 * 0.7 * 0.49
        let secondDurationScale = (1.2 * 1.35 * 1.2) * 0.9 * 1.1
        let secondSharpScale = (1.45 * 0.5 * 1.25 * 1.18) * 1.3
        let firstPartials: [(Double, Double, Double, Bool)] = [
            (firstBase, 0.34 * firstScale * 1.25, 0.40, false),
            (firstBase * 1.006, 0.065 * firstScale * 0.7, 0.40, false),
            (firstBase * 2.42, 0.23 * firstScale * 1.35 * 1.25, 0.328, true),
            (firstBase * 3.98, 0.19 * firstScale * 1.35 * 1.25, 0.035, false),
            (firstBase * 5.62, 0.11 * firstScale * 1.35 * 1.25, 0.018, true)
        ]
        let secondPartials: [(Double, Double, Double, Bool)] = [
            (secondBase, 0.33 * secondScale * 1.25, 0.26 * secondDurationScale, false),
            (secondBase * 1.0065, 0.08 * secondScale * 0.7 * 0.49, 0.28 * secondDurationScale, false),
            (secondBase * 2.44, 0.17 * secondScale * secondSharpScale * 1.25, 0.12 * secondDurationScale, true),
            (secondBase * 4.02, 0.14 * secondScale * (secondSharpScale * 1.2) * 1.25, 0.045, false),
            (secondBase * 5.65, 0.15 * secondScale * 0.78 * 1.25, 0.022, true)
        ]

        for frame in 0..<Int(frames) {
            let t = Double(frame) / sampleRate
            var sample = 0.0
            sample += noteSample(time: t, start: 0, partials: firstPartials, isSecond: false)
            sample += noteSample(time: t, start: 0.35, partials: secondPartials, isSecond: true)
            // Very subtle 85 ms metallic room echo from the original Web Audio patch.
            if t >= 0.085 {
                let delayed = t - 0.085
                sample += 0.045 * (noteSample(time: delayed, start: 0, partials: firstPartials, isSecond: false)
                    + noteSample(time: delayed, start: 0.35, partials: secondPartials, isSecond: true))
            }
            let output = Float(max(-0.95, min(0.95, sample * 0.42)))
            channels[0][frame] = output
            channels[1][frame] = output
        }
        return buffer
    }

    private func noteSample(time: Double, start: Double, partials: [(Double, Double, Double, Bool)], isSecond: Bool) -> Double {
        let local = time - start
        guard local >= 0 else { return 0 }
        var sum = 0.0
        for (frequency, amplitude, decay, triangle) in partials {
            guard local <= decay else { continue }
            let attack = min(1, local / 0.0015)
            var envelope = amplitude * attack
            if isSecond {
                let openPoint = min(decay * 0.3, 0.045 + 0.03)
                if local < openPoint {
                    let fraction = max(0, local / max(0.001, openPoint))
                    envelope *= max(0.22, 1 - 0.78 * fraction)
                } else {
                    envelope *= 0.22 * exp(-7.0 * (local - openPoint) / max(0.01, decay))
                }
            } else {
                envelope *= exp(-6.8 * local / max(0.01, decay))
            }
            let pitchStart = isSecond ? 1.036 : 1.024
            let pitchProgress = min(1, local / 0.0075)
            let pitch = pitchStart + (1 - pitchStart) * pitchProgress
            let phase = 2 * Double.pi * frequency * pitch * local
            let wave = triangle ? (2 / Double.pi) * asin(sin(phase)) : sin(phase)
            sum += wave * envelope
        }
        return sum
    }
}
