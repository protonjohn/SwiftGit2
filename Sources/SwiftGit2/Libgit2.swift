//
//  Libgit2.swift
//  SwiftGit2
//
//  Created by Matt Diephouse on 1/11/15.
//  Copyright (c) 2015 GitHub, Inc. All rights reserved.
//

import Clibgit2

extension git_strarray {
    func filter(_ isIncluded: (String) throws -> Bool) rethrows -> [String] {
        return try map { $0 }.filter(isIncluded)
    }

    func map<T>(_ transform: (String) throws -> T) rethrows -> [T] {
        return try (0..<self.count).map {
            let string = String(validatingUTF8: self.strings[$0]!)!
            return try transform(string)
        }
    }

    /// Create a git_strarray from an array of strings.
    ///
    /// - Note: This array should be freed after use with `git_strarray_free`.
    init(strings: [String]) {
        let cStrings = strings.map { (string: String) -> UnsafeMutablePointer<CChar>? in
            guard let data = string.data(using: .utf8) else { return nil }
            let ptr = UnsafeMutablePointer<CChar>.allocate(capacity: data.count)
            ptr.initialize(from: data.map { CChar($0) }, count: data.count)
            return ptr
        }

        let cStringArray = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
            .allocate(capacity: cStrings.count)
        cStringArray.initialize(from: cStrings, count: cStrings.count)

        self.init(strings: cStringArray, count: cStrings.count)
    }
}
