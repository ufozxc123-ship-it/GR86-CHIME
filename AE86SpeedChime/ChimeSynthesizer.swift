import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var tracker: SpeedTracker

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.04, blue: 0.055).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    header
                    controls
                    speedPanel
                    settingsPanel
                    simulationPanel
                    footer
                }
                .padding(16)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .tint(Color(red: 1, green: 0.65, blue: 0.08))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("AE86 / 4A-GE")
                    .font(.caption2.weight(.heavy)).tracking(1.4)
                    .foregroundStyle(.orange)
                Text("GPS SPEED CHIME")
                    .font(.title3.weight(.black)).foregroundStyle(.white)
            }
            Spacer()
            Text(tracker.isRunning ? "ACTIVE" : "STANDBY")
                .font(.caption2.monospaced().weight(.bold))
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(tracker.isRunning ? Color.green.opacity(0.16) : Color.white.opacity(0.07))
                .foregroundStyle(tracker.isRunning ? .green : .gray)
                .clipShape(Capsule())
        }
        .padding(.vertical, 5)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                tracker.isRunning ? tracker.stop() : tracker.start()
            } label: {
                Label(tracker.isRunning ? "측정 중지" : "GPS 측정 시작", systemImage: tracker.isRunning ? "stop.fill" : "location.fill")
                    .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(tracker.isRunning ? Color.red.opacity(0.85) : Color.orange)
                    .foregroundStyle(.black).clipShape(RoundedRectangle(cornerRadius: 15))
            }
            Button { tracker.testChime() } label: {
                Label("차임 테스트", systemImage: "speaker.wave.2.fill")
                    .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(Color.white.opacity(0.09)).foregroundStyle(.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            }
        }
        .buttonStyle(.plain)
    }

    private var speedPanel: some View {
        VStack(spacing: 16) {
            HStack {
                Circle().fill(tracker.isRunning ? Color.green : Color.gray).frame(width: 9, height: 9)
                Text(tracker.status).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(tracker.isOverLimit ? "SPEED ALERT" : "SPEED STANDBY")
                    .font(.caption2.monospaced().weight(.heavy)).tracking(1)
                    .foregroundStyle(tracker.isOverLimit ? .red : .gray)
            }
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(Int(tracker.displayedSpeed.rounded()))")
                    .font(.system(size: 86, weight: .black, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6).lineLimit(1)
                    .foregroundStyle(tracker.isOverLimit ? .red : .white)
                Text("km/h").font(.title3.monospaced().weight(.bold)).foregroundStyle(.orange)
            }
            HStack(spacing: 3) {
                ForEach(0..<16, id: \.self) { index in
                    let active = Double(index) < ceil(tracker.displayedSpeed / 10)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(active ? (tracker.isOverLimit || Double(index) * 10 >= tracker.threshold ? Color.red : Color.orange) : Color.white.opacity(0.08))
                        .frame(height: 10)
                }
            }
            HStack {
                Text("GPS 정확도")
                Spacer()
                Text(tracker.accuracy.map { "±\(Int($0.rounded())) m" } ?? "--")
            }
            .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.45))
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.12), Color.black], startPoint: .top, endPoint: .bottom))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var settingsPanel: some View {
        VStack(spacing: 18) {
            settingRow(title: "차임 작동 기준 속도", value: "\(Int(tracker.threshold)) km/h") {
                Slider(value: Binding(get: { tracker.threshold }, set: tracker.setThreshold), in: 20...160, step: 1)
            }
            settingRow(title: "차임 음량", value: "\(Int(tracker.volume * 100))%") {
                Slider(value: Binding(get: { tracker.volume }, set: tracker.setVolume), in: 0...1)
            }
            settingRow(title: "세트 간 반복 간격", value: "\(Int(tracker.repeatInterval * 1000)) ms") {
                Slider(value: Binding(get: { tracker.repeatInterval }, set: tracker.setRepeatInterval), in: 0.5...1.6, step: 0.01)
            }
            HStack {
                Text("음소거").font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("음소거", isOn: Binding(get: { tracker.isMuted }, set: { _ in tracker.toggleMute() }))
                    .labelsHidden().tint(.red)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func settingRow<Content: View>(title: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(value).font(.caption.monospaced().weight(.bold)).foregroundStyle(.orange)
            }
            content().tint(.orange)
        }
    }

    private var simulationPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("실내 속도 시뮬레이션").font(.subheadline.weight(.bold))
                    Text("GPS 없이 차임 동작을 테스트합니다.").font(.caption).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Toggle("시뮬레이션", isOn: Binding(get: { tracker.isSimulating }, set: tracker.setSimulation))
                    .labelsHidden().tint(.green)
            }
            HStack {
                Text("가상 속도").font(.caption.weight(.semibold))
                Spacer()
                Text("\(Int(tracker.simulatedSpeed)) km/h").font(.caption.monospaced().weight(.bold)).foregroundStyle(.green)
            }
            Slider(value: Binding(get: { tracker.simulatedSpeed }, set: tracker.setSimulatedSpeed), in: 0...180, step: 1)
                .tint(.green)
            HStack(spacing: 8) {
                ForEach([0.0, 60.0, 105.0, 130.0], id: \.self) { speed in
                    Button("\(Int(speed))") { tracker.setSimulatedSpeed(speed) }
                        .font(.caption.monospaced().weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Color.white.opacity(0.08)).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("화면을 잠그기 전 GPS 측정을 시작하세요.")
            Text("백그라운드 추적에는 위치 권한 '항상 허용'이 필요합니다.")
        }
        .font(.caption2).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.42))
        .padding(.bottom, 16)
    }
}
