//
//  Utils.swift
//  Tortoro
//
//  Created by Solomenchuk, Vlad on 4/6/17.
//  Copyright © 2017 Aramzamzam LLC. All rights reserved.
//

import Foundation

var torDirectory: URL = {
    #if (arch(i386) || arch(x86_64)) && os(iOS)
        return URL(fileURLWithPath: "/private/tmp/tor")
    #else
        return FileManager.default.urls(for: .cachesDirectory,
                                        in: .userDomainMask).last!.appendingPathComponent("tor")
    #endif
}()
