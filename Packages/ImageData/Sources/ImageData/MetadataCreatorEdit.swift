import Exiftool

public enum MetadataCreatorValue: Equatable, Sendable {
    case absent
    case names([String])
}

public enum MetadataCreatorEditError: Error {
    case invalidNames
}

public enum MetadataCreatorEditAction: Equatable, Sendable {
    case set([String])
    case fillMissing([String])
    case remove

    // The caller must supply a successfully read value; a read failure is not
    // an absent field and must never trigger fillMissing or removal.
    public func change(from current: MetadataCreatorValue) throws -> MetadataTagChange? {
        switch self {
        case .set(let names):
            try Self.check(names)
            return current == .names(names) ? nil : .set(.list(names))
        case .fillMissing(let names):
            try Self.check(names)
            return current == .absent ? .set(.list(names)) : nil
        case .remove:
            return current == .absent ? nil : .remove
        }
    }

    private static func check(_ names: [String]) throws {
        guard !names.isEmpty, names.allSatisfy({ !$0.isEmpty }) else {
            throw MetadataCreatorEditError.invalidNames
        }
    }
}
