@testable import ConnectingCaptions_Debug
import CoreAudio
import XCTest

/// Covers the two silent-input decisions that decide whether a listen keeps
/// trying after audio stops arriving: the PCM watchdog latch and the
/// "did the resolved microphone change" predicates behind route recovery.
final class AudioCaptureIdlePolicyWatchdogTests: XCTestCase {
    private typealias Watchdog = AudioCaptureIdlePolicy.SilentPCMRecoveryWatchdog

    func testShouldRecoverFiresOnceAfterSustainedSilenceFollowingSignal() {
        var watchdog = Watchdog()

        XCTAssertFalse(
            watchdog.shouldRecover(isInternalMicrophone: true, isDirectCapture: true, rms: 0.1, peak: 0.1),
            "a live signal never requests recovery"
        )
        for _ in 0..<(Watchdog.requiredSilentWindows - 1) {
            XCTAssertFalse(
                watchdog.shouldRecover(isInternalMicrophone: true, isDirectCapture: true, rms: 0, peak: 0),
                "recovery must not fire before the required run of silent windows completes"
            )
        }
        XCTAssertTrue(
            watchdog.shouldRecover(isInternalMicrophone: true, isDirectCapture: true, rms: 0, peak: 0),
            "recovery fires once the silent window count is reached"
        )
    }

    func testOneShotLatchBlocksASecondTriggerUntilRearmed() {
        var watchdog = Watchdog()
        self.triggerRecovery(&watchdog)

        XCTAssertFalse(
            watchdog.shouldRecover(isInternalMicrophone: true, isDirectCapture: true, rms: 0, peak: 0),
            "the latch blocks a second trigger in the same session before rearm()"
        )

        watchdog.rearm()

        XCTAssertTrue(
            self.triggerRecovery(&watchdog),
            "after rearm(), a fresh run of silence can trigger recovery again"
        )
    }

    func testShouldRecoverIgnoresAnythingThatIsNotAnInternalDirectInput() {
        var watchdog = Watchdog()
        // A USB or Bluetooth input is not a built-in mic: silence there is not
        // a stuck route, so the watchdog must stay out of the way.
        for _ in 0...Watchdog.requiredSilentWindows {
            XCTAssertFalse(
                watchdog.shouldRecover(isInternalMicrophone: false, isDirectCapture: true, rms: 0, peak: 0),
                "an external input must never trip the silent-PCM watchdog"
            )
            XCTAssertFalse(
                watchdog.shouldRecover(isInternalMicrophone: true, isDirectCapture: false, rms: 0, peak: 0),
                "the engine capture path is not covered by this watchdog"
            )
        }
    }

    // MARK: - Resolved-microphone identity

    func testLosingTheOnlyPriorityInputRequiresReconciliation() {
        // Every input vanished while the user had named one: the resolved
        // microphone went from that mic to nothing.
        XCTAssertTrue(
            AudioCaptureIdlePolicy.shouldReconcileInputSelection(
                priorityInputUIDs: ["uid-belt-pack"],
                migrationPending: false,
                previousInputUIDs: ["uid-belt-pack"],
                currentInputUIDs: []
            ),
            "unplugging the only listed input is a selection change"
        )
    }

    func testFallingBackToALowerPriorityInputRequiresReconciliation() {
        // Both listed mics existed, now only the second one does, so the
        // resolved choice moves down the list.
        XCTAssertTrue(
            AudioCaptureIdlePolicy.shouldReconcileInputSelection(
                priorityInputUIDs: ["uid-belt-pack", "uid-lav"],
                migrationPending: false,
                previousInputUIDs: ["uid-belt-pack", "uid-lav"],
                currentInputUIDs: ["uid-lav"]
            ),
            "resolving to a different listed input is a selection change"
        )
    }

    func testLosingAnUnlistedInputLeavesTheSelectionAlone() {
        // The resolved choice stays on the belt pack, so there is nothing to
        // rebuild the capture route for.
        XCTAssertFalse(
            AudioCaptureIdlePolicy.shouldReconcileInputSelection(
                priorityInputUIDs: ["uid-belt-pack", "uid-lav"],
                migrationPending: false,
                previousInputUIDs: ["uid-belt-pack", "uid-lav"],
                currentInputUIDs: ["uid-belt-pack"]
            ),
            "losing an input nobody had resolved to must not restart capture"
        )
        XCTAssertFalse(
            AudioCaptureIdlePolicy.shouldReconcileInputSelection(
                priorityInputUIDs: ["uid-belt-pack"],
                migrationPending: false,
                previousInputUIDs: [],
                currentInputUIDs: []
            ),
            "a session that never had an input has nothing to reconcile"
        )
    }

    func testAnUnconfiguredPriorityListAlwaysReconciles() {
        // Most users never edit the priority list, so an empty list must defer
        // to the system default rather than to a stored preference.
        XCTAssertTrue(
            AudioCaptureIdlePolicy.shouldReconcileInputSelection(
                priorityInputUIDs: [],
                migrationPending: false,
                previousInputUIDs: ["uid-belt-pack"],
                currentInputUIDs: ["uid-lav"]
            ),
            "with no priority list, any change in available inputs reconciles"
        )
    }

    func testMigrationPendingReconcilesWithoutASelectionChange() {
        XCTAssertTrue(
            AudioCaptureIdlePolicy.shouldReconcileInputSelection(
                priorityInputUIDs: ["uid-belt-pack"],
                migrationPending: true,
                previousInputUIDs: ["uid-belt-pack"],
                currentInputUIDs: ["uid-belt-pack"]
            ),
            "a pending priority migration reconciles even when the resolved input is unchanged"
        )
    }

    func testSameUIDUnderANewObjectIDCountsAsAnIdentityChange() {
        // A Bluetooth headset that powers back on keeps its UID and is handed
        // out as a new AudioObjectID, which is exactly the stale-binding case.
        XCTAssertTrue(
            AudioCaptureIdlePolicy.didResolvedPriorityInputIdentityChange(
                priorityInputUIDs: ["uid-belt-pack"],
                previousInputDeviceIDsByUID: ["uid-belt-pack": AudioObjectID(7)],
                currentInputDeviceIDsByUID: ["uid-belt-pack": AudioObjectID(9)]
            ),
            "the same UID rebound to a new object ID is a new capture source"
        )
        XCTAssertFalse(
            AudioCaptureIdlePolicy.didResolvedPriorityInputIdentityChange(
                priorityInputUIDs: ["uid-belt-pack"],
                previousInputDeviceIDsByUID: ["uid-belt-pack": AudioObjectID(7)],
                currentInputDeviceIDsByUID: ["uid-belt-pack": AudioObjectID(7)]
            ),
            "an unchanged UID and unchanged object ID is not a change"
        )
        XCTAssertFalse(
            AudioCaptureIdlePolicy.didResolvedPriorityInputIdentityChange(
                priorityInputUIDs: ["uid-belt-pack"],
                previousInputDeviceIDsByUID: ["uid-lav": AudioObjectID(7)],
                currentInputDeviceIDsByUID: ["uid-lav": AudioObjectID(9)]
            ),
            "a listed input that was never present cannot change identity"
        )
    }

    @discardableResult
    private func triggerRecovery(_ watchdog: inout Watchdog) -> Bool {
        _ = watchdog.shouldRecover(isInternalMicrophone: true, isDirectCapture: true, rms: 0.1, peak: 0.1)
        var triggered = false
        for _ in 0..<Watchdog.requiredSilentWindows {
            triggered = watchdog.shouldRecover(isInternalMicrophone: true, isDirectCapture: true, rms: 0, peak: 0)
        }
        return triggered
    }
}
