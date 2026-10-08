import Foundation
import HostCore
import Testing

@Suite("Naming a paired Remote from its User-Agent")
struct RemoteNameTests {
    @Test(arguments: [
        ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1", "iPhone"),
        ("Mozilla/5.0 (iPad; CPU OS 18_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1", "iPad"),
        // iPadOS asks for desktop sites by default, so an iPad usually looks like a Mac.
        ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15", "Mac or iPad"),
        ("Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36", "Android"),
        ("curl/8.7.1", "Browser"),
        ("", "Browser"),
    ])
    func namesTheDevice(userAgent: String, name: String) {
        #expect(Pairing.name(userAgent: userAgent, taken: []) == name)
    }

    @Test func numbersASecondRemoteOfTheSameKind() {
        let iPhone = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4 like Mac OS X)"
        #expect(Pairing.name(userAgent: iPhone, taken: ["iPhone"]) == "iPhone 2")
        #expect(Pairing.name(userAgent: iPhone, taken: ["iPhone", "iPhone 2"]) == "iPhone 3")
        #expect(Pairing.name(userAgent: iPhone, taken: ["iPhone 2"]) == "iPhone")
    }
}
