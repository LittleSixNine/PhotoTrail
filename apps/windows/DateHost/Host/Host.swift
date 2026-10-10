import Foundation

struct Item: Decodable {
    let id: String; let op: String; let text: String?
    let years: Int?; let months: Int?; let days: Int?; let hours: Int?; let minutes: Int?; let seconds: Int?
    let component: String?; let value: Int?; let components: [String: Int]?
    let count: Int?; let end: String?; let zone: String?
}
struct Request: Decodable { let version: String; let id: String; let items: [Item] }
struct Source: Encodable { let commit = BuildIdentity.commit; let path = BuildIdentity.path; let sha256 = BuildIdentity.sha256 }
struct Failure: Error, Encodable { let scope: String; let code: String }
struct Result: Encodable { let id: String; let values: [String]?; let error: Failure? }
struct Response: Encodable {
    let version = BuildIdentity.version; let source = Source()
    let id: String; let results: [Result]; let computeMs: Double; let jobError: Failure?
}
func fail(_ scope: String, _ code: String) -> Failure { Failure(scope: scope, code: code) }
func fullInput(_ text: String?) throws -> String {
    guard let text else { throw fail("parameter", "missingInput") }
    guard text.utf8.count <= 128 else { throw fail("boundary", "textLimit") }
    guard !text.contains("\n"), !text.contains("\r") else { throw fail("parameter", "dateInput") }
    return text // Never Trim. Empty date is not a clear action.
}
// Validate integer tokens before JSONDecoder (which can accept integral decimal JSON).
func checkIntegers(_ data: Data) throws {
    guard let text = String(data: data, encoding: .utf8) else { throw fail("parameter", "invalidJSON") }
    let bytes = Array(text.utf8); var i = 0; var quoted = false
    while i < bytes.count {
        let ch = bytes[i]
        if quoted { if ch == 92 { i += 2; continue }; if ch == 34 { quoted = false }; i += 1; continue }
        if ch == 34 { quoted = true; i += 1; continue }
        if ch == 45 || (48...57).contains(ch) {
            let start = i; i += 1
            while i < bytes.count && (Array("0123456789+-.eE".utf8).contains(bytes[i])) { i += 1 }
            let token = String(decoding: bytes[start..<i], as: UTF8.self)
            guard !token.contains("."), !token.lowercased().contains("e"), Int64(token) != nil else { throw fail("parameter", "invalidInteger") }
        } else { i += 1 }
    }
}
func component(_ name: String?) throws -> Calendar.Component {
    switch name {
    case "year": return .year; case "month": return .month; case "day": return .day
    case "hour": return .hour; case "minute": return .minute; case "second": return .second
    default: throw fail("parameter", "unknownComponent")
    }
}
func calculate(_ item: Item) throws -> [String] {
    let text = try fullInput(item.text)
    switch item.op {
    case "normalize": return [try MetadataDate(text).text]
    case "offset": return [try MetadataDate(text).offsetting(years: item.years ?? 0, months: item.months ?? 0, days: item.days ?? 0, hours: item.hours ?? 0, minutes: item.minutes ?? 0, seconds: item.seconds ?? 0).text]
    case "shift": guard let seconds = item.seconds else { throw fail("parameter", "missingParameter") }; return [try MetadataDate(text).shifting(seconds: seconds).text]
    case "calendarDays": guard let days = item.days else { throw fail("parameter", "missingParameter") }; return [try MetadataDate(text).addingCalendarDays(days, timeZoneID: item.zone).text]
    case "replace": guard let value = item.value else { throw fail("parameter", "missingParameter") }; return [try MetadataDate(text).replacing(component(item.component), with: value).text]
    case "replaceAtomic":
        guard let changes = item.components, !changes.isEmpty else { throw fail("parameter", "emptyComponents") }
        let first = try MetadataDate(text)
        let names = ["year", "month", "day", "hour", "minute", "second"]
        guard changes.keys.allSatisfy(names.contains) else { throw fail("parameter", "unknownComponent") }
        // Only substitute text components. The unchanged candidate validates the final combination.
        var parts = String(first.text.prefix(19)).split(whereSeparator: { $0 == ":" || $0 == " " }).map(String.init)
        for (index, name) in names.enumerated() { if let value = changes[name] { parts[index] = String(format: index == 0 ? "%04lld" : "%02lld", Int64(value)) } }
        let final = parts[0...2].joined(separator: ":") + " " + parts[3...5].joined(separator: ":") + first.fraction + first.offset
        return [try MetadataDate(final).text]
    case "sequence": guard let count = item.count, let seconds = item.seconds else { throw fail("parameter", "missingParameter") }; return try MetadataDate.sequence(start: text, stepSeconds: seconds, count: count)
    case "distribute": guard let count = item.count else { throw fail("parameter", "missingParameter") }; return try MetadataDate.distribute(start: text, end: fullInput(item.end), count: count)
    default: throw fail("parameter", "unknownOperation")
    }
}
@main struct Host {
    static func main() {
        var requestId = ""; var results = [Result](); var jobError: Failure?; var computeMs = 0.0
        do {
            var input = Data()
            while let chunk = try FileHandle.standardInput.read(upToCount: 65536), !chunk.isEmpty { input.append(chunk); guard input.count <= 1_048_576 else { throw fail("boundary", "inputLimit") } }
            if let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any] {
                requestId = object["id"] as? String ?? ""
                guard Set(object.keys).isSubset(of: ["version", "id", "items"]) else { throw fail("parameter", "unknownMember") }
            }
            try checkIntegers(input)
            if let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any], let items = object["items"] as? [[String: Any]] {
                let allowed: Set<String> = ["id", "op", "text", "years", "months", "days", "hours", "minutes", "seconds", "component", "value", "components", "count", "end", "zone"]
                guard items.allSatisfy({ Set($0.keys).isSubset(of: allowed) }) else { throw fail("parameter", "unknownMember") }
            }
            let request: Request
            do { request = try JSONDecoder().decode(Request.self, from: input) } catch { throw fail("parameter", "invalidJSON") }
            guard request.version == BuildIdentity.version else { throw fail("parameter", "versionMismatch") }
            guard !request.id.isEmpty, request.id.utf8.count <= 64, request.items.count <= 3000 else { throw fail("boundary", "requestLimit") }
            var seen = Set<String>(); var count = 0
            for item in request.items {
                guard !item.id.isEmpty, item.id.utf8.count <= 64, seen.insert(item.id).inserted else { throw fail("parameter", "invalidID") }
                let needed = item.op == "sequence" || item.op == "distribute" ? max(0, item.count ?? 0) : 1
                guard needed <= 3000, count <= 3000 - needed else { throw fail("boundary", "resultLimit") }; count += needed
                guard (item.zone?.utf8.count ?? 0) <= 128 else { throw fail("boundary", "textLimit") }
            }
            let start = Date(); var marked = false
            for item in request.items {
                do {
                    let values = try calculate(item)
                    if !marked { marked = true; FileHandle.standardError.write(Data("CALC_STARTED:first_item_computed\n".utf8)) }
                    results.append(Result(id: item.id, values: values, error: nil))
                } catch let error as MetadataDateError {
                    let code: String
                    switch error { case .invalidDate: code = "invalidDate"; case .invalidSequence: code = "invalidSequence"; case .missingDate: code = "missingDate" }
                    results.append(Result(id: item.id, values: nil, error: fail("business", code)))
                } catch let error as Failure { results.append(Result(id: item.id, values: nil, error: error)) }
                catch { throw fail("process", "internal") }
            }
            computeMs = Date().timeIntervalSince(start) * 1000
        } catch let error as Failure { jobError = error; results = [] }
        catch { jobError = fail("process", "internal"); results = [] }
        do {
            var output = try JSONEncoder().encode(Response(id: requestId, results: results, computeMs: computeMs, jobError: jobError))
            if output.count > 1_048_576 { output = try JSONEncoder().encode(Response(id: requestId, results: [], computeMs: computeMs, jobError: fail("boundary", "outputLimit"))) }
            FileHandle.standardOutput.write(output)
        } catch { FileHandle.standardError.write(Data("HOST_ENCODING_FAILED\n".utf8)); exit(3) }
    }
}
