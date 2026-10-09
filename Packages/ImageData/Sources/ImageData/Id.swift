// A concurrency safe source of monotonically increasing identifiers

import os

extension ImageData {
    private static let idMutex = OSAllocatedUnfairLock(initialState: 0)

    static func nextId() -> Int {
        return idMutex.withLock { id in
            id += 1
            return id
        }
    }
}
