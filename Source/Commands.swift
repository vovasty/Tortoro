//
//  Commands.swift
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

/// Commands to control/retriever information from tor process
/// `Tortoro` should not be subclassed.
/// For custom commands use `Tortoro.instance` class variable to access `Tortoro` instance.
extension Tortoro {

    /// The type of Info result
    public typealias InfoResult = Result<[String: String?]>

    /// Retrieves tor info for specified keys.
    ///
    /// - parameter keys:    info keys.
    /// - parameter handler: result handler
    public class func getInfoForKeys(keys: [String],
                                     handler: @escaping (InfoResult) -> Void) {
        instance?.send(command: "GETINFO", arguments: keys) { (response) in
            do {
                let result: [Response]

                switch response {
                case .success(let res):
                    result = res
                case .failure(let error):
                    throw error
                }

                var lines = try result.map { (response) throws -> String in
                    guard let line = response.string else {
                        throw NSError(code: -1, message: "Wrong info key string encoding")
                    }

                    guard response.code == 250 else {
                        throw NSError(code: response.code, message: line)
                    }

                    return line
                }

                let message = lines.count > 0 ? lines.removeLast() : "Unknown error"

                let code = result.last?.code ?? -1

                guard code == 250 && message == "OK" else {
                    throw NSError(code: code, message: message)
                }

                guard lines.count == keys.count else {
                    throw NSError(code: -1, message: "Wrong number of response keys")
                }

                let quotes = CharacterSet(["\""])
                var info = [String: String]()

                for i in 0 ..< lines.count {
                    let line = lines[i]

                    let pairs = line.components(separatedBy: "=")
                    let key: String
                    let value: String?

                    if pairs.count == 2 {
                        key = pairs[0].trimmingCharacters(in: quotes)
                        value = pairs[1].trimmingCharacters(in: quotes)
                    } else {
                        key = line.trimmingCharacters(in: quotes)
                        value = nil
                    }

                    guard keys.contains(key) else {
                        let error = NSError(code: -1, message: "Unknown key (\(key)) in line(\(i)): \"\(line)\"")
                        throw error
                    }

                    info[key] = value
                }

                handler(InfoResult.success(info))
            } catch {
                handler(InfoResult.failure(error))
            }
        }
    }

    /// The type of socks configuration
    public typealias SocksConfigurationResult = Result<(host: String, port: Int)>

    /// Retrieves socks server configuration.
    ///
    /// - parameter handler: result handler
    public class func getSocksConfiguration(handler: @escaping (SocksConfigurationResult) -> Void) {
        Tortoro.getInfoForKeys(keys: ["net/listeners/socks"]) { (result) in
            let info: [String: String?]

            switch result {
            case .success(let res):
                info = res
            case .failure(let error):
                handler(SocksConfigurationResult.failure(error))
                return
            }

            guard info.count == 1 else {
                handler(SocksConfigurationResult.failure(NSError(code: -1, message: "Wrong response \(info)")))
                return
            }

            guard let pairs = info["net/listeners/socks"]??.components(separatedBy: ":"),
                pairs.count == 2 else {
                handler(SocksConfigurationResult.failure(NSError(code: -1, message: "Wrong response \(info)")))
                return
            }

            guard pairs[0] != "unix",
                let port = Int(pairs[1]) else {
                    let error = NSError(code: -1, message: "Socks proxy configured improperly \(info)")
                    handler(SocksConfigurationResult.failure(error))
                return
            }

            handler(SocksConfigurationResult.success((host: pairs[0], port: port)))
        }
   }

    /// Adds listener for tor state
    ///
    /// - parameter handler: result handler
    public class func addReadinessListener(handler: @escaping ((Result<Bool>) -> Void)) {
        instance?.subscribe(event: "STATUS_CLIENT") { (result) in
            switch result {
            case .success(let event):
                switch event.action {
                case "CIRCUIT_ESTABLISHED":
                    handler(.success( true ))
                case "CIRCUIT_NOT_ESTABLISHED":
                    handler(.success( false ))
                default:
                    break
                }
            case .failure(let error):
                handler(.failure(error))
            }
        }
    }

    /// Forces `tor` process to reload configuration. Should be called after app wakes from sleep.
    ///
    /// - parameter handler: result handler
    public class func reload(handler: @escaping (Result<Void>) -> Void) {
        instance?.reload(handler: handler)
    }
}
