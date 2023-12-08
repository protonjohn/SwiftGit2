//
//  Revisions.swift
//  
//
//  Created by John Biggs on 08.12.23.
//

import Foundation
import Clibgit2

public enum RevisionSpecification {
    struct Flags: RawRepresentable, OptionSet {
        let rawValue: UInt32

        static let single = Self(rawValue: GIT_REVSPEC_SINGLE.rawValue)
        static let range = Self(rawValue: GIT_REVSPEC_RANGE.rawValue)
        static let base = Self(rawValue: GIT_REVSPEC_MERGE_BASE.rawValue)
    }

    case single(ObjectType)
    case range(start: ObjectType, end: ObjectType)
    case base(start: ObjectType)

    init?(_ revspec: git_revspec) {
        guard let startPointer = revspec.from,
              let start = GitObjectType.object(startPointer) else {
            return nil
        }

        let flags = Flags(rawValue: revspec.flags)
        if flags.contains(.single) {
            self = .single(start)
        } else if flags.contains(.range) {
            guard let endPointer = revspec.to,
                  let end = GitObjectType.object(endPointer) else {
                return nil
            }
            self = .range(start: start, end: end)
        } else if flags.contains(.base) {
            self = .base(start: start)
        } else {
            return nil
        }
    }
}
