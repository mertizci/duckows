import XCTest

/// The updater only offers a release that ships a `.dmg`, so asset selection is
/// load-bearing: picking the ZIP would hand `hdiutil` something it cannot mount.
final class GitHubReleaseDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
    }

    private let sample = """
    {
      "tag_name": "v1.4.0",
      "name": "v1.4.0",
      "body": "### Fixed\\n- A thing",
      "assets": [
        {
          "name": "Duckows-1.4.0.zip",
          "browser_download_url": "https://example.com/Duckows-1.4.0.zip"
        },
        {
          "name": "Duckows-1.4.0.dmg",
          "browser_download_url": "https://example.com/Duckows-1.4.0.dmg"
        }
      ]
    }
    """

    func testDecodesSnakeCaseKeys() throws {
        let release = try decode(sample)
        XCTAssertEqual(release.tagName, "v1.4.0")
        XCTAssertEqual(release.assets.count, 2)
        XCTAssertEqual(release.assets[1].browserDownloadURL.lastPathComponent, "Duckows-1.4.0.dmg")
    }

    func testDisplayVersionStripsTheTagPrefix() throws {
        XCTAssertEqual(try decode(sample).displayVersion, "1.4.0")
    }

    func testReleaseNotesFallBackToEmptyString() throws {
        let json = #"{"tag_name":"v1.0.0","assets":[]}"#
        XCTAssertEqual(try decode(json).releaseNotes, "")
    }

    func testPicksTheDMGNotTheZIP() throws {
        let asset = GitHubReleaseService().dmgAsset(in: try decode(sample))
        XCTAssertEqual(asset?.name, "Duckows-1.4.0.dmg")
    }

    func testReturnsNilWhenNoDMGIsAttached() throws {
        let json = """
        {
          "tag_name": "v1.0.0",
          "assets": [
            { "name": "Duckows-1.0.0.zip",
              "browser_download_url": "https://example.com/Duckows-1.0.0.zip" }
          ]
        }
        """
        XCTAssertNil(GitHubReleaseService().dmgAsset(in: try decode(json)))
    }

    func testAssetMatchIsCaseInsensitive() throws {
        let json = """
        {
          "tag_name": "v1.0.0",
          "assets": [
            { "name": "Duckows-1.0.0.DMG",
              "browser_download_url": "https://example.com/Duckows-1.0.0.DMG" }
          ]
        }
        """
        XCTAssertNotNil(GitHubReleaseService().dmgAsset(in: try decode(json)))
    }
}
