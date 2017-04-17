//
//  TorThread.swift
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

//https://gist.github.com/neilpa/b430d148d1c5f4ae5ddd

// Is this really the best way to extend the lifetime of C-style strings? The lifetime
// of those passed to the String.withCString closure are only guaranteed valid during
// that call. Tried cheating this by returning the same C string from the closure but it
// gets dealloc'd almost immediately after the closure returns. This isn't terrible when
// dealing with a small number of constant C strings since you can nest closures. But
// this breaks down when it's dynamic, e.g. creating the char** argv array for an exec
// call.
fileprivate class CString {
    private let len: Int
    let buffer: UnsafeMutablePointer<Int8>

    init(_ string: String) {
        (len, buffer) = string.withCString {
            let len = Int(strlen($0) + 1)
            let dst = strcpy(UnsafeMutablePointer<Int8>.allocate(capacity: len), $0)
            return (len, dst!)
        }
    }

    deinit {
        buffer.deallocate(capacity: len)
    }
}

// An array of C-style strings (e.g. char**) for easier interop.
fileprivate struct CStringArray {
    // Have to keep the owning CString's alive so that the pointers
    // in our buffer aren't dealloc'd out from under us.
    private let strings: [CString?]
    let pointers: [UnsafeMutablePointer<Int8>?]
    let argc: Int32

    let argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>

    init(_ strings: [String?]) {
        self.strings = strings.map { $0.flatMap { CString($0) } }

        pointers = self.strings.map { $0?.buffer }

        argc = Int32(pointers.count - 1)

        argv = UnsafeMutablePointer(mutating: pointers)
    }
}

fileprivate struct CArguments {
    private let array: CStringArray
    let argc: Int32
    let argv: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>

    init(name: String, arguments: [String]) {
        array = CStringArray([name] + arguments + [nil])
        argc = Int32(array.pointers.count - 1)
        argv = UnsafeMutablePointer(mutating: array.pointers)
    }
}

class TorThread: Foundation.Thread {
    let arguments: [String]
    static var instance: TorThread!

    static var isRunning: Bool {
        return instance != nil
    }

    class func start(arguments: [String: String]) {
        guard instance == nil else { return }
        instance = TorThread(arguments: arguments)
        instance.start()
    }

    init(arguments: [String: String]) {
        var args = [String]()

        for (k, v) in arguments {
            args.append(k)
            args.append(v)
        }

        self.arguments = args
    }

    override func main() {
        let arguments = CArguments(name: "tor", arguments: self.arguments)
        tor_main(arguments.argc, arguments.argv)
    }
}
