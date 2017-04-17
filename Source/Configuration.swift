//
//  Configuration.swift
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

fileprivate extension URL {
    var fileSystemRepresentation: String? {
        return withUnsafeFileSystemRepresentation { (path) -> String? in
            guard let path = path else { return nil }
            return String(cString: path)
        }
    }
}

/// The `Configuration` provides configuration for `tor` process.
public struct Configuration {
    private (set) var arguments: [String: String] = [:]

    private mutating func setArgument(_ key: String, _ url: URL?) {
        guard let url = url else {
            arguments.removeValue(forKey: key)
            return
        }

        guard let path = url.fileSystemRepresentation else {
            arguments.removeValue(forKey: key)
            return
        }

        arguments[key] = path
    }

    /// Creates a `Configuration`.
    ///
    /// - parameter dataDirectory: path to data directory. Can be recreated by `Configuration`.
    public init(dataDirectory: URL) throws {
        self.dataDirectory = dataDirectory

        try setControlSocket(controlSocket: dataDirectory.appendingPathComponent("control"))

        cookieAuthFile = URL(fileURLWithPath: "cookie", relativeTo: dataDirectory)
        cookieAuthentication = true

        arguments["ClientOnly"] = "1"
        arguments["ExitPolicy"] = "reject *:*"
        arguments["AvoidDiskWrites"] = "1"
        arguments["HardwareAccel"] = "1"
        arguments["CookieAuthentication"] = "1"
        arguments["ConnLimit"] = "100"
        arguments["UseEntryGuards"] = "1"
        arguments["SafeLogging"] = "1"
        arguments["TestSocks"] = "0"
        arguments["WarnUnsafeSocks"] = "1"
        arguments["DisableDebuggerAttachment"] = "1"
    }

    private mutating func setControlSocket(controlSocket: URL) throws {
        guard let controlSocketPath = controlSocket.fileSystemRepresentation else {
            throw NSError(code: -1, message: "unable to get path from url: \(controlSocket)")
        }

        let maxPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard  controlSocketPath.characters.count < maxPathLength else {
            let message = "control socket is too long (max \(maxPathLength)): \(controlSocketPath)"
            throw NSError(code: -1, message: message)
        }

        setArgument("ControlSocket", controlSocket)
    }

    /// path to control socket.
    /// Note: socket will be constructed inside `dataDirectory`. Maximum length for unix socket is 104 characters.
    public var controlSocket: URL? {
        return arguments["ControlSocket"].flatMap {URL(fileURLWithPath: $0) }
    }

    /// socks server port.
    public var socksPort: Int? {
        get {
            guard let port = arguments["SocksPort"] else { return nil }
            return Int(port)
        }

        set {
            guard let port = newValue else {
                arguments.removeValue(forKey: "SocksPort")
                return
            }
            arguments["SocksPort"] = String(port)
        }
    }

    /// path to data directory.
    public private (set) var dataDirectory: URL? {
        get {
            return  arguments["DataDirectory"].flatMap {URL(fileURLWithPath: $0) }
        }

        set {
            setArgument("DataDirectory", newValue)
        }
    }

    /// path to cookie authentication file
    public var cookieAuthFile: URL? {
        get {
            return arguments["CookieAuthFile"].flatMap {URL(fileURLWithPath: $0) }
        }

        set {
            setArgument("CookieAuthFile", newValue)
        }
    }

    /// enable/disable cookie authentication
    public var cookieAuthentication: Bool {
        get {
            return arguments["CookieAuthentication"].flatMap { $0 != "0" } ?? false
        }

        set {
            arguments["CookieAuthentication"] = newValue ? "1" : "0"
        }
    }

    /// path to `torrc` file.
    /// Note: this file is controlled by `Configuration`
    var torrcPath: URL? {
        return dataDirectory?.appendingPathComponent("torrc")
    }

    /// writes `torrc` file.
    func write() throws {
        guard let dataDirectory = dataDirectory else {
            throw NSError(code: -1, message: "dataDirectory is not set")
        }

        guard let dataDirectoryPath = dataDirectory.fileSystemRepresentation else {
            throw NSError(code: -1, message: "unable to get path from url: \(String(describing: dataDirectory))")
        }

        let df = FileManager.default

        var isDirectory: ObjCBool = false

        if !df.fileExists(atPath: dataDirectoryPath, isDirectory: &isDirectory) {
            isDirectory = true
            try df.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        }

        guard isDirectory.boolValue else {
            throw NSError(code: -1, message: "dataDirectory should be a directory: \(dataDirectory)")
        }

        try df.setAttributes([FileAttributeKey.posixPermissions: 0o700], ofItemAtPath: dataDirectoryPath)

        guard let torrcPath = torrcPath else {
            throw NSError(code: -1, message: "torrcPath is not set")
        }

        var torrc = ""

        for (key, value) in arguments {
            torrc.append("\(key) \(value)\r\n")
        }

        try torrc.write(to: torrcPath, atomically: true, encoding: .utf8)
    }
}
