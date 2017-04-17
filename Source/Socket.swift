//
//  Socket.swift
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

import Foundation

let htons = Int(OSHostByteOrder()) == OSLittleEndian ? _OSSwapInt16 : { $0 }

class Socket {
    var socket: Int32

    init(fileURL url: URL) throws {
        guard url.isFileURL else {
            throw NSError(code: -1, message: "not a file url")
        }

        var control_addr = sockaddr_un()
        control_addr.sun_family = UInt8(AF_UNIX)

        _ = url.withUnsafeFileSystemRepresentation { path in
            withUnsafeMutablePointer(to: &control_addr.sun_path) {
                $0.withMemoryRebound(to: Int8.self,
                                     capacity: MemoryLayout.size(ofValue: control_addr.sun_path)) { sun_path in
                                        strncpy(sun_path, path, MemoryLayout.size(ofValue: control_addr.sun_path) - 1)
                }
            }
        }

        control_addr.sun_len = UInt8(MemoryLayout.size(ofValue: control_addr))

        socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)

        let result = withUnsafePointer(to: &control_addr) {
            $0.withMemoryRebound(to: Darwin.sockaddr.self,
                                 capacity: MemoryLayout.size(ofValue: control_addr)) { address in
                                    Darwin.connect(socket, address, socklen_t(control_addr.sun_len))
            }
        }
        guard result == 0 else {
            throw NSError.globalError
        }
    }

    init(host: String, port: Int32) throws {
        var addr = in_addr()

        guard host.withCString({ inet_aton($0, &addr) }) == 0 else {
            throw NSError.globalError
        }

        var control_addr = sockaddr_in()
        control_addr.sin_family = UInt8(AF_INET)
        control_addr.sin_port = htons(UInt16(port))
        control_addr.sin_addr = addr
        control_addr.sin_len =  UInt8(MemoryLayout.size(ofValue: control_addr))

        socket = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)

        let result = withUnsafePointer(to: &control_addr) {
            $0.withMemoryRebound(to: Darwin.sockaddr.self,
                                 capacity: MemoryLayout.size(ofValue: control_addr)) { address in
                                    Darwin.connect(socket, address, socklen_t(control_addr.sin_len))
            }
        }
        guard result == 0 else {
            throw NSError()
        }
    }

    func close() {
        if socket != -1 {
            _ = Darwin.close(socket)
        }
    }

    deinit {
        close()
    }
}
