//
//  CommandsTests.swift
//
//  Copyright © 2017 Solomenchuk, Vlad (http://aramzamzam.net/).
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import XCTest
@testable import Tortoro

class CommandsTests: XCTestCase {
    func testGetSocksConfiguration() throws {
        let e = expectation(description: "GetSocksConfiguration")

        let configuration = try Configuration(dataDirectory: torDirectory)

        Tortoro.configure(configuration: configuration) { (result) in
            XCTAssert(result.isSuccess)
        }

        Tortoro.getSocksConfiguration { (result) in
            XCTAssert(result.isSuccess)
            e.fulfill()
        }

        waitForExpectations(timeout: 30)
    }

    func testReconfigure() throws {
        let e1 = expectation(description: "Reconfigure1")

        var configuration = try Configuration(dataDirectory: torDirectory)
        configuration.socksPort = 8888

        Tortoro.configure(configuration: configuration) { (result) in
            XCTAssert(result.isSuccess)
        }

        Tortoro.getSocksConfiguration { (result) in
            XCTAssert(result.isSuccess)
            result.value.flatMap { XCTAssertEqual($0.port, 8888) }
            e1.fulfill()
        }

        waitForExpectations(timeout: 120)

        let e2 = expectation(description: "Reconfigure2")

        configuration.socksPort = 9999

        Tortoro.configure(configuration: configuration) { (result) in
            XCTAssert(result.isSuccess)
        }

        Tortoro.getSocksConfiguration { (result) in
            XCTAssert(result.isSuccess)
            result.value.flatMap { XCTAssertEqual($0.port, 9999) }

            e2.fulfill()
        }

        waitForExpectations(timeout: 1200)
    }
}
