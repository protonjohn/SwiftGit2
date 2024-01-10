//
//  OID.swift
//  SwiftGit2
//
//  Created by Matt Diephouse on 11/17/14.
//  Copyright (c) 2014 GitHub, Inc. All rights reserved.
//

import Clibgit2

/// An identifier for a Git object.
public struct OID: RawRepresentable {

    // MARK: - Initializers

    /// Create an instance from a hex formatted string.
    ///
    /// string - A 40-byte hex formatted string.
    public init?(string: String) {
        // libgit2 doesn't enforce a maximum length
        if string.lengthOfBytes(using: String.Encoding.ascii) > 40 {
            return nil
        }

        let pointer = UnsafeMutablePointer<git_oid>.allocate(capacity: 1)
        defer { pointer.deallocate() }

        do {
            try calling(git_oid_fromstr(pointer, string))
        } catch {
            return nil
        }

        rawValue = pointer.pointee
    }

    /// Create an instance from a libgit2 `git_oid`.
    public init(_ oid: git_oid) {
        self.rawValue = oid
    }

    public init(rawValue: git_oid) {
        self.init(rawValue)
    }

    // MARK: - Properties

    public let rawValue: git_oid

    // MARK: - minimumLength

    /// The minimum length required to losslessly represent an OID among the other OIDs in the list.
    ///
    /// - Note: This function first converts all of the passed OIDs to strings before calling the actual function.
    public static func minimumLength(toLosslesslyRepresent oids: some Collection<OID>, initialMinimum: Int = 6) throws -> Int {
        return try minimumLength(toLosslesslyRepresent: oids.map(\.description), initialMinimum: initialMinimum)
    }

    /// The minimum length required to losslessly represent an OID among the other OIDs in the list.
    ///
    /// - Note: This is more efficient than its sister function because it doesn't need to convert the OIDs to strings.
    public static func minimumLength(toLosslesslyRepresent oids: some Collection<String>, initialMinimum: Int = 6) throws -> Int {
        guard let shorten = git_oid_shorten_new(initialMinimum) else {
            throw GitError(
                code: .error,
                detail: .noMemory,
                description: "Insufficient available memory to allocate git_oid_shorten instance"
            )
        }
        defer { git_oid_shorten_free(shorten) }

        var minimum = initialMinimum
        for oid in oids {
            let new = try Int(calling(git_oid_shorten_add(shorten, oid)))
            minimum = new < minimum ? new : minimum
        }

        return minimum
    }
}

extension OID: CustomStringConvertible {
    public var description: String {
        let length = Int(GIT_OID_RAWSZ) * 2
        let string = UnsafeMutablePointer<Int8>.allocate(capacity: length)
        var oid = rawValue
        git_oid_fmt(string, &oid)

        return String(bytesNoCopy: string, length: length, encoding: .ascii, freeWhenDone: true)!
    }
}

extension OID: Hashable {
    public func hash(into hasher: inout Hasher) {
        withUnsafeBytes(of: rawValue.id) {
            hasher.combine(bytes: $0)
        }
    }

    public static func == (lhs: OID, rhs: OID) -> Bool {
        var left = lhs.rawValue
        var right = rhs.rawValue
        return git_oid_cmp(&left, &right) == 0
    }
}
