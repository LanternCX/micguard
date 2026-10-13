import Foundation

@main
struct ConnectionPolicyTests {
    static func main() {
        var count = 0
        func check(_ steps: [(Set<UInt32>, UInt32, Double, UInt32?)], _ name: String) {
            var policy = ConnectionPolicy()
            for (inputs, selected, time, expected) in steps {
                let actual = policy.observe(inputs: inputs, selected: selected, now: time)
                precondition(actual == expected, "\(name): expected \(String(describing: expected)), got \(String(describing: actual))")
            }
            count += 1
        }
        check([([1, 2], 2, 0, nil), ([1, 2], 1, 1, nil), ([1, 2], 2, 2, nil)],
              "Accept startup and manual choices")
        check([([1], 1, 0, nil), ([1, 2], 2, 1, 1), ([1, 2], 1, 1.1, nil),
               ([1, 2], 2, 1.2, nil)], "Correct once, then accept manual selection")
        check([([1], 1, 0, nil), ([1, 2], 1, 1, nil), ([1, 2], 2, 1.5, 1)],
              "Device list notification arrives first")
        check([([1], 1, 0, nil), ([1, 2], 1, 1, nil), ([1, 2], 2, 3, nil)],
              "Expired window allows selection")
        check([([1, 3], 3, 0, nil), ([1, 2, 3], 2, 1, 3)],
              "Restore selected external microphone, not built-in")
        check([([1], 1, 0, nil), ([2], 2, 1, nil)], "Allow disconnected input fallback")
        check([([1], 1, 0, nil), ([1, 2], 1, 1, nil), ([2], 2, 1.1, nil)],
              "Previous input disappears during connection window")
        check([([1, 3], 1, 0, nil), ([1, 2, 3], 1, 1, nil),
               ([1, 2, 3], 3, 1.1, nil), ([1, 2, 3], 2, 1.2, nil)],
              "Choosing an existing device cancels protection")
        check([([1], 1, 0, nil), ([1, 2], 2, 1, 1), ([1, 2], 2, 1.1, nil)],
              "Failed correction is not retried")
        check([([1], 1, 0, nil), ([1, 2], 2, 1, 1), ([1, 2], 1, 1.1, nil),
               ([1], 1, 2, nil), ([1, 2], 2, 3, 1)], "Reconnect opens a new window")
        check([([1], 1, 0, nil), ([], 0, 1, nil), ([1], 1, 2, nil)],
              "Invalid snapshot is ignored")
        check([([1], 1, 0, nil), ([1, 2, 3], 2, 1, 1), ([1, 2, 3], 1, 1.1, nil),
               ([1, 2, 3], 3, 1.2, nil)], "One correction per connection batch")
        print("Passed \(count) connection policy scenarios.")
    }
}
