import Foundation

@MainActor
protocol ActivityTracking {
    var activitySegments: AsyncStream<[ActivitySegment]> { get }
    var currentSegments: [ActivitySegment] { get }
    var isCapturingLiveActivity: Bool { get }
    func start() async
    func stop() async
}

#if DEBUG
@MainActor
final class MockActivityTracker: ActivityTracking {
    private let seedSegments: [ActivitySegment]

    init(seedSegments: [ActivitySegment] = []) {
        self.seedSegments = seedSegments
    }

    var activitySegments: AsyncStream<[ActivitySegment]> {
        AsyncStream { continuation in
            continuation.yield(seedSegments)
            continuation.finish()
        }
    }

    var currentSegments: [ActivitySegment] {
        seedSegments
    }

    var isCapturingLiveActivity: Bool {
        !seedSegments.isEmpty
    }

    func start() async {}
    func stop() async {}
}
#endif
