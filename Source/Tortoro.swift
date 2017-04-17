//
//  Tortoro.swift
//  SwiftyTor
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
import Darwin

//http://stackoverflow.com/a/7520655/449547
extension Data {
    var hexString: String? {
        return withUnsafeBytes { (buf: UnsafePointer<UInt8>) -> String? in
            let charA = UInt8(UnicodeScalar("a").value)
            let char0 = UInt8(UnicodeScalar("0").value)

            func itoh(_ value: UInt8) -> UInt8 {
                return (value > 9) ? (charA + value - 10) : (char0 + value)
            }

            let hexLen = count * 2
            let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: hexLen)

            for i in 0 ..< count {
                ptr[i*2] = itoh((buf[i] >> 4) & 0xF)
                ptr[i*2+1] = itoh(buf[i] & 0xF)
            }

            let result = String(bytesNoCopy: ptr, length: hexLen, encoding: .utf8, freeWhenDone: true)

            return result?.characters.count == 0 ? nil : result
        }
    }

    var utf8String: String? {
        return String(data: self, encoding: .utf8)
    }
}

private extension DispatchSource {
    class func makeTimer(repeat period: DispatchTimeInterval,
                         queue: DispatchQueue,
                         handler: @escaping () -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)

        timer.scheduleRepeating(deadline: DispatchTime.now(), interval: period)

        timer.setEventHandler(handler: handler)

        return timer
    }

    class func makeTimer(timeout: DispatchTimeInterval,
                         queue: DispatchQueue,
                         handler: @escaping () -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)

        timer.scheduleOneshot(deadline: DispatchTime.now() + timeout)

        timer.setEventHandler(handler: handler)

        return timer
    }
}
fileprivate extension Data {
    mutating func append(_ newElement: DispatchData) {
        newElement.withUnsafeBytes {
            append($0, count: newElement.count)
        }
    }
}

fileprivate class CommandQueue<ResponseType> {
    private class BlockOperation: Operation {
        private let block: () -> Void
        init(block: @escaping () -> Void) {
            self.block = block
            super.init()
        }

        override func main() {
            guard !isCancelled else { return }
            block()
        }
    }

    var queue: OperationQueue!
    var semaphore = DispatchSemaphore(value: 0)
    var responseData: ResponseType! {
        didSet {
            semaphore.signal()
        }
    }

    init() {
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    func add(timeout: DispatchTimeInterval,
             priority: Operation.QueuePriority,
             request: @escaping () -> Void,
             response: @escaping (ResponseType) -> Void) {

        let operation = BlockOperation { [weak self] in
            guard let sself = self else { return }

            request()

            guard sself.semaphore.wait(timeout: DispatchTime.now() + timeout) == .success else { return }

            response(sself.responseData)
        }

        operation.queuePriority = priority

        queue.addOperation(operation)

    }

    func cancelAllOperations() {
        queue.cancelAllOperations()
        while semaphore.signal() != 0 {}
    }

    func suspend() {
        queue.isSuspended = true
    }

    func resume() {
        queue.isSuspended = false
    }

}

enum ReplySeparators: Character {
    case mid = "-"
    case data = "+"
    case end = " "
}

/// The `Tortoro` provides control for `tor` process.
/// Only class methods should be used.
public class Tortoro {

    /// The type of response type.
    public typealias ResponseResult = Result<[Response]>

    /// The type of event result
    public typealias EventResult = Result<Event>

    /// The type of event listener
    public typealias EventListener = (EventResult) -> Void

    /// Encapsulates `event` data
    public struct Event {
        var type: String
        var severity: String
        var action: String
        var arguments: [String: String]
    }

    /// encapsulates response data
    public struct Response {
        var code: Int
        var string: String?
        var data: Data?
    }

    var channel: DispatchIO?
    private (set) var configuration: Configuration!
    var queue = DispatchQueue.global(qos: .background)
    var pollingPeriod: DispatchTimeInterval = DispatchTimeInterval.milliseconds(100)
    var startTimeout: DispatchTimeInterval = DispatchTimeInterval.seconds(60)
    var sendTimeout: DispatchTimeInterval = DispatchTimeInterval.seconds(60)
    private var pollingTimer: DispatchSourceTimer?
    private var timeoutTimer: DispatchSourceTimer?
    fileprivate let commandQueue: CommandQueue<ResponseResult>
    fileprivate var needReconfigure = false
    private var eventListeners: [EventListener] = []
    private var events: [String] = []

    public static var instance: Tortoro?

    init() {
        commandQueue = CommandQueue<ResponseResult>()
    }

    /// Subscribes for particular tor event.
    ///
    /// - parameter event: desired `tor` event.
    /// - parameter handler: result handler
    public func subscribe(event: String, handler: @escaping EventListener) {
        listenEvents(events: [event]) { [weak self] (response) in
            switch response {
            case .success():
                self?.eventListeners.append(handler)
            case .failure(let error):
                handler(.failure(error))
            }
        }
    }

    /// Sends commands to `tor` process.
    ///
    /// - parameter priority: command priority.
    /// - parameter command: `tor` command.
    /// - parameter event: command's arguments.
    /// - parameter arguments: command's arguments.
    /// - parameter data: command's data arguments.
    /// - parameter handler: result handler
    public func send(priority: Operation.QueuePriority = .normal,
                     command: String,
                     arguments: [String]? = nil,
                     data: Data? = nil,
                     handler: @escaping (ResponseResult) -> Void) {
        send(priority: priority, command:command, arguments: { () -> (arguments: [String]?, data: Data?) in
            return (arguments: arguments, data: data)
        }, response: handler)
    }

    /// Forces `tor` process to reload configuration. Should be called after app wakes from sleep.
    ///
    /// - parameter handler: result handler
    public func reload(handler: @escaping (Result<Void>) -> Void) {
        send(priority: .veryHigh, command: "SIGNAL", arguments: ["RELOAD"]) { (result) in
            switch result {
            case .failure(let error):
                handler(Result<Void>.failure(error))
                return
            case .success(let value):
                guard let response = value.first,
                    let message = response.string else {
                        handler(Result<Void>.failure(NSError(code: -1, message: "Bad response")))
                        return
                }

                guard response.code == 250 && message == "OK" else {
                    handler(Result<Void>.failure(NSError(code: response.code, message: message)))
                    return
                }
            }

            handler(Result<Void>.success())
        }
    }

    /// Configures `tor` process. May be used multiple times
    ///
    /// - parameter handler: result handler
    public func configure(configuration: Configuration, handler: @escaping (Result<Void>) -> Void) {
        do {
            try configuration.write()
        } catch {
            handler(Result<Void>.failure(error))
            return
        }

        if !TorThread.isRunning {
            guard let torrcURL = configuration.torrcPath else {
                handler(Result<Void>.failure(NSError(code: -1, message: "torrcPath is not set")))
                return
            }

            torrcURL.withUnsafeFileSystemRepresentation {
                guard let path = $0 else {
                    handler(Result<Void>.failure(NSError(code: -1, message: "unable to get path to torrc")))
                    return
                }
                TorThread.start(arguments: ["--defaults-torrc": String(cString: path)])
            }
        }

        let shouldStart = self.configuration == nil
        self.configuration = configuration

        if shouldStart {
            self.start(handler: handler)
        } else {
            reload(handler: handler)
        }
    }

    private func start(handler: @escaping (Result<Void>) -> Void) {
        commandQueue.suspend()

        guard let controlSocket = configuration.controlSocket else {
            handler(Result<Void>.failure(NSError(code: -1, message: "control socket is not set")))
            return
        }

        timeoutTimer?.cancel()
        timeoutTimer = nil

        guard configuration.cookieAuthentication, let cookieAuthFile = configuration.cookieAuthFile else {
            handler(Result<Void>.failure(NSError(code: -1, message: "unsupported authentication")))
            return
        }

        authenticate(cookie: cookieAuthFile) { result in
            switch result {
            case .success:
                handler(Result<Void>.success())
            case .failure (let error):
                handler(Result<Void>.failure(error))
            }
        }

        startSocketChecker(controlSocket: controlSocket, handler: handler)

        timeoutTimer = DispatchSource.makeTimer(timeout: startTimeout, queue: queue) { [weak self] in
            self?.pollingTimer?.cancel()
            handler(Result<Void>.failure(NSError(code: -1, message: "start timeout")))
        }

        timeoutTimer?.resume()
    }

    private func listenEvents(events: [String], handler: @escaping (Result<Void>) -> Void) {
        let newEvents = events.filter {
            !self.events.contains($0)
        }

        if newEvents.isEmpty {
            handler(.success())
            return
        }

        send(command: "SETEVENTS", arguments: events) { (response) in
            do {
                switch response {
                case .success(let res):
                    guard let firstLine = res.first else {
                        throw NSError(code: -1, message: "no result")
                    }

                    guard let line = firstLine.string else {
                        throw NSError(code: -1, message: "Wrong string encoding")
                    }

                    guard firstLine.code == 250 else {
                        throw NSError(code: firstLine.code, message: line)
                    }

                    handler(Result<Void>.success())
                case .failure(let error):
                    throw error
                }
            } catch {
                handler(Result<Void>.failure(error))
            }
        }
    }

    private func startSocketChecker(controlSocket: URL, handler: @escaping (Result<Void>) -> Void) {
        pollingTimer?.cancel()
        pollingTimer = DispatchSource.makeTimer(repeat: pollingPeriod, queue: queue) { [weak self] in
            guard let sself = self else { return }

            let sock: Socket?

            if controlSocket.isFileURL {
                sock = try? Socket(fileURL: controlSocket)
            } else {
                guard let host = controlSocket.host, let port = controlSocket.port else {
                    handler(Result<Void>.failure(NSError(code: -1, message: "no host and/or port")))
                    return
                }

                sock = try? Socket(host: host, port: Int32(port))
            }

            guard let socket = sock else { return }

            sself.timeoutTimer?.cancel()
            sself.timeoutTimer = nil

            sself.pollingTimer?.cancel()
            sself.pollingTimer = nil

            do {
                try self?.setupReader(socket: socket)
                self?.commandQueue.resume()
            } catch {
                handler(Result<Void>.failure(error))
                return
            }
        }

        pollingTimer?.resume()
    }

    private func authenticate(cookie: URL?, completion: @escaping (Result<Void>) -> Void) {
        send(priority: .high, command: "AUTHENTICATE", arguments: { () -> (arguments: [String]?, data: Data?) in
            let cookieData = cookie.flatMap { try? Data(contentsOf: $0) }

            let hexString = cookieData?.hexString

            return (arguments: hexString.flatMap { [$0] }, data: nil)
        }) { (result) in
            switch result {
            case .failure(let error):
                completion(Result<Void>.failure(error))
                return
            case .success(let value):
                guard let response = value.first,
                    let message = response.string else {
                        completion(Result<Void>.failure(NSError(code: -1, message: "Bad response")))
                        return
                }

                guard response.code == 250 && message == "OK" else {
                    completion(Result<Void>.failure(NSError(code: response.code, message: message)))
                    return
                }
            }

            completion(Result<Void>.success())
        }
    }

    private func send(priority: Operation.QueuePriority = .normal,
                      command: String,
                      arguments: @escaping () -> (arguments: [String]?, data: Data?),
                      response: @escaping (ResponseResult) -> Void) {
        commandQueue.add(timeout: sendTimeout, priority: priority, request: {
            let (arguments, data) = arguments()

            var argumentsString = command

            arguments.flatMap { argumentsString.append(" \($0.joined(separator: " "))") }

            let hasData = !(data?.isEmpty ?? true)

            var commandData = Data()

            if hasData {
                commandData.append(0x2b)
            }

            guard let argumentsData = argumentsString.data(using: .utf8) else {
                response(.failure(NSError(code: -1, message: "unable to convert string into utf8")))
                return
            }

            commandData.append(argumentsData)
            commandData.append(contentsOf: [0xd, 0xa])

            if hasData, let data = data {
                commandData.append(data)
                commandData.append(contentsOf: [0xd, 0xa, 0xe, 0xd, 0xa])
            }

            commandData.withUnsafeBytes { [weak self] (x: UnsafePointer<UInt8>) in
                guard let sself = self else { return }

                let data = DispatchData(bytes: UnsafeBufferPointer(start: x, count: commandData.count))
                sself.channel?.write(offset: 0, data: data, queue: sself.queue) { (_, _, error) in
                    guard error == 0 else {
                        response(.failure(NSError(code: -1, message: "failed to write command")))
                        return
                    }
                }
            }
        }, response: response)
    }

    private func setupReader(socket: Socket) throws {
        guard channel == nil else {
            throw NSError(code: -1, message: "already connected")
        }

        channel = DispatchIO(type: .stream, fileDescriptor: socket.socket, queue: queue) { [weak self] _ in
            socket.close()
            self?.channel?.close(flags: .stop)
            self?.channel = nil
        }

        channel?.setLimit(lowWater: 1)

        let separator = Data(bytes: [0xd, 0x0a])
        let dot = Data(bytes: [0x2e])

        var buffer = Data()
        var result = [Response]()

        channel?.read(offset: 0, length: size_t.max, queue: queue) { [weak self] (_, data, _) in
            guard let data = data, data.count > 0 else { return }

            buffer.append(data)

            var remainingRange: Range<Data.Index> = buffer.startIndex ..< buffer.endIndex
            var dataBlock: Response? = nil

            while let separatorRange = buffer.range(of: separator, options: [], in: remainingRange) {
                let lineLength = separatorRange.lowerBound - remainingRange.lowerBound
                let lineData = buffer.subdata(in: remainingRange.lowerBound ..< remainingRange.lowerBound + lineLength)

                remainingRange = remainingRange.lowerBound + lineLength + separator.count ..< buffer.endIndex

                if dataBlock != nil {
                    if lineData == dot {
                        result.append(dataBlock!)
                        dataBlock = nil
                    } else {
                        dataBlock?.data?.append(lineData)
                    }
                    continue
                }

                guard lineData.count >= 4 else { continue }

                let statusCodeData = lineData.subdata(in: Range<Data.Index>(0...2))

                guard let statusCodeString = statusCodeData.utf8String,
                      let statusCode = Int(statusCodeString) else { continue }

                guard let character = lineData.subdata(in: Range<Data.Index>(3...3)).first,
                      let scalar = UnicodeScalar(UInt32(character)),
                      let lineType = ReplySeparators(rawValue: Character(scalar))
                else { continue }

                buffer.removeFirst(lineLength + separator.count)
                remainingRange = buffer.startIndex ..< buffer.endIndex

                if lineType == ReplySeparators.data {
                    dataBlock = Response(code: statusCode,
                                         string: nil,
                                         data: lineData.subdata(in: 4 ..< lineData.endIndex))
                } else {
                    let string = lineData.subdata(in: 4 ..< lineData.endIndex).utf8String
                    result.append(Response(code: statusCode, string: string, data: nil))
                }

                guard lineType == ReplySeparators.end else { continue }

                self?.route(lines: result)

                result = []
            }
        }
    }

    private func route(lines: [Response]) {
        var events = [(code: Int, string: String)]()
        var results = [Response]()

        for line in lines {
            if  let string = line.string, line.code == 650 {
                events.append((code: line.code, string: string))
            } else {
                results.append(line)
            }
        }

        if !events.isEmpty {
            let parsedEvents = parseEvents(events: events)
            for event in parsedEvents {
                for listener in eventListeners {
                    queue.async {
                        listener(EventResult.success(event))
                    }
                }
            }
        }

        if !results.isEmpty {
            commandQueue.responseData = .success(results)
        }
    }

    private func parseEvents(events: [(code: Int, string: String)]) -> [Event] {
        var parsedEvents = [Event]()

        for event in events {
            guard event.code == 650 else { continue }
            guard event.string.hasPrefix("STATUS_") else { continue }
            let components = event.string.components(separatedBy: " ")
            guard components.count >= 3 else { continue }

            var arguments = [String: String]()

            if components.count > 3 {
                for component in components.suffix(from: 3) {
                    let kv = component.components(separatedBy: "=")

                    guard kv.count == 2 else { continue }

                    arguments[kv[0]] = kv[1]
                }
            }

            let type = components[0]
            let severity = components[1]
            let action = components[2]

            parsedEvents.append(Event(type: type, severity: severity, action: action, arguments: arguments))
        }

        return parsedEvents
    }

    deinit {
        channel?.close(flags: .stop)
    }
}

extension Tortoro {
    public class func configure(configuration: Configuration, handler: @escaping (Result<Void>) -> Void) {
        if instance == nil {
            instance = Tortoro()
        }

        instance?.configure(configuration: configuration, handler: handler)
    }
}
