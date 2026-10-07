import Foundation
import HostCore
import Testing

@Suite("Volume state pushed to the Remote")
struct VolumeStateTests {
    private func fields(_ text: String) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary)
    }

    @Test func encodesLevelMuteAndWhetherTheSliderCanSetIt() throws {
        let text = VolumeState(level: 0.4000000059604645, muted: false, settable: true).encoded()
        #expect(try fields(text) == ["t": "vol", "v": 0.4, "muted": false, "settable": true])
    }

    @Test func encodesAnOutputWithoutSoftwareVolume() throws {
        let text = VolumeState(level: 1, muted: true, settable: false).encoded()
        #expect(try fields(text) == ["t": "vol", "v": 1, "muted": true, "settable": false])
    }
}
