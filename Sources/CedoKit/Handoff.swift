/// A value written on one thread and read on another only after waiting for the writer to finish.
final class Handoff<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}
