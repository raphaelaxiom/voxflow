import Foundation

@main
struct VoxflowTests {
    static func main() async {
        AppContextServiceTests.run()
        await LLMAPITransportTests.run()
        TemperatureCapabilityCacheTests.run()
        ModelConfigurationTests.run()
        RecordingCaptureTimingTests.run()
        RecordingTimerPreferenceTests.run()
        ShortcutCoreTests.run()
        SemanticVersionTests.run()
        LLMCooldownManagerTests.run()
        PostProcessingServiceTests.run()
        TranscriptionErrorPresentationCoreTests.run()
        TranscriptTextCoreTests.run()
        await TranscriptionServiceTests.run()
        await APIConfigurationDraftTests.run()
        DashboardStatsTests.run()
        AIProviderTests.run()
        OverlayPhaseTests.run()
        print("VoxflowTests passed")
    }
}
