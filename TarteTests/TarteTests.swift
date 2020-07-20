//
//  TarteTests.swift
//  TarteTests
//
//  Created by Antoine Marandon on 16/07/2020.
//  Copyright © 2020 ntnmrndn. All rights reserved.
//

import XCTest
@testable import Tarte

class TarteTests: XCTestCase {
    private var urlsToCleanup = [URL]()

    private func cleanTargetURL() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        urlsToCleanup.append(url)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        return url
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        try urlsToCleanup.forEach {
            try FileManager.default.removeItem(at: $0)
        }
    }

    func test0BitFileNoXattr() throws {
        let tarURL = Bundle(for: type(of: self)).url(forResource: "single_0_bit_file_named_toto_no_xattr", withExtension: "tar")!
        let untarURL = try cleanTargetURL()
        let untaredFile = untarURL.appendingPathComponent("toto", isDirectory: false)
        XCTAssertNoThrow(try Tarte.unTar(tarURL, to: untarURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: untaredFile.path), "Expected a file but no file was created")
    }


    func testLargeFilesAtSubPath() throws {
        let tarURL = Bundle(for: type(of: self)).url(forResource: "large_files", withExtension: "tar")!
        let untarURL = try cleanTargetURL()
        let root = untarURL
            .appendingPathComponent("Users", isDirectory: true)
            .appendingPathComponent("antoine.marandon", isDirectory: true)
            .appendingPathComponent("Desktop", isDirectory: true)
        XCTAssertNoThrow(try Tarte.unTar(tarURL, to: untarURL))
        do {
            let untaredFile = root.appendingPathComponent("file1.png", isDirectory: false)
            XCTAssertTrue(FileManager.default.fileExists(atPath: untaredFile.path), "Expected a file but no file was created")
        }
        do {
            let untaredFile = root.appendingPathComponent("file2.png", isDirectory: false)
            XCTAssertTrue(FileManager.default.fileExists(atPath: untaredFile.path), "Expected a file but no file was created")
        }
    }

    func testFileWithContentNoXattr() throws {
        let tarURL = Bundle(for: type(of: self)).url(forResource: "single_hi_file_named_toto_no_xattr", withExtension: "tar")!
        let untarURL = try cleanTargetURL()
        let untaredFile = untarURL.appendingPathComponent("toto", isDirectory: false)
        XCTAssertNoThrow(try Tarte.unTar(tarURL, to: untarURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: untaredFile.path), "Expected a file but no file was created")
        try XCTAssertEqual("hi\n", String(contentsOfFile: untaredFile.path))
    }

    func testDoubleFilesWithContentNoXattr() throws {
        let tarURL = Bundle(for: type(of: self)).url(forResource: "two_hi_file_named_toto_tata_no_xattr", withExtension: "tar")!
        let untarURL = try cleanTargetURL()
        let untaredFile = untarURL.appendingPathComponent("toto", isDirectory: false)
        let untaredFile2 = untarURL.appendingPathComponent("tata", isDirectory: false)
        XCTAssertNoThrow(try Tarte.unTar(tarURL, to: untarURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: untaredFile.path), "Expected a file but no file was created")
        try XCTAssertEqual("hi\n", String(contentsOfFile: untaredFile.path))
        try XCTAssertEqual("hi\n", String(contentsOfFile: untaredFile2.path))
    }

    func testEmptyFile() throws {
        let tarURL = Bundle(for: type(of: self)).url(forResource: "empty_file", withExtension: "tar")!
        let untarURL = try cleanTargetURL()
        XCTAssertThrowsError(try Tarte.unTar(tarURL, to: untarURL))
    }

    func testGarbageFiles() throws {
        do {
            let tarURL = Bundle(for: type(of: self)).url(forResource: "garbage_file", withExtension: "tar")!
            let untarURL = try cleanTargetURL()
            try XCTAssertThrowsError(Tarte.unTar(tarURL, to: untarURL))
        }
        do {
            let tarURL = Bundle(for: type(of: self)).url(forResource: "long_garbage_file", withExtension: "tar")!
            let untarURL = try cleanTargetURL()
            try XCTAssertThrowsError(Tarte.unTar(tarURL, to: untarURL))
        }
    }

    //XXX test evil files.

    func testDirectory() throws {
        let tarURL = Bundle(for: type(of: self)).url(forResource: "hi_file_in_toto_directory_no_xattr", withExtension: "tar")!
        let untarURL = try cleanTargetURL()
        let untaredFile = untarURL.appendingPathComponent("toto", isDirectory: true)
            .appendingPathComponent("tata")
        XCTAssertNoThrow(try Tarte.unTar(tarURL, to: untarURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: untaredFile.path), "Expected a file but no file was created")
        try XCTAssertEqual("hi\n", String(contentsOfFile: untaredFile.path))
        
    }

    func testBigFiles() throws {
        let tarURL = Bundle(for: type(of: self)).url(forResource: "big_files", withExtension: "tar")!
        let untarURL = try cleanTargetURL()
        XCTAssertNoThrow(try Tarte.unTar(tarURL, to: untarURL))
        //XXX use hash of file to check for integrity
        do {
            let untaredFile = untarURL.appendingPathComponent("toto", isDirectory: false)
            XCTAssertTrue(FileManager.default.fileExists(atPath: untaredFile.path), "Expected a file but no file was created")
        }
        do {
            let untaredFile = untarURL.appendingPathComponent("tata", isDirectory: false)
            XCTAssertTrue(FileManager.default.fileExists(atPath: untaredFile.path), "Expected a file but no file was created")
        }
    }


    func testEmoji() throws {
        let tarURL = Bundle(for: type(of: self)).url(forResource: "emoji", withExtension: "tar")!
        let untarURL = try cleanTargetURL()
        let untaredFile = untarURL.appendingPathComponent("🇵🇲", isDirectory: false)
        XCTAssertNoThrow(try Tarte.unTar(tarURL, to: untarURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: untaredFile.path), "Expected a file but no file was created")
        try XCTAssertEqual("🇵🇲\n", String(contentsOfFile: untaredFile.path))
    }

    func testLongNames() throws {
        let longFileName = "long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_name"
        let tarURL = Bundle(for: type(of: self)).url(forResource: "long_names", withExtension: "tar")!
        let untarURL = try cleanTargetURL()
        XCTAssertNoThrow(try Tarte.unTar(tarURL, to: untarURL))
        let untaredFile = untarURL.appendingPathComponent(longFileName, isDirectory: false)
        let untaredFileInDirectory = untarURL.appendingPathComponent("toto", isDirectory: true)
            .appendingPathComponent(longFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: untaredFile.path), "Expected a file but no file was created")
        XCTAssertTrue(FileManager.default.fileExists(atPath: untaredFileInDirectory.path), "Expected a file but no file was created")
    }

//    func testPerformanceExample() throws {
//        // This is an example of a performance test case.
//        self.measure {
//            // Put the code you want to measure the time of here.
//        }
//    }

}
