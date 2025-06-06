//
//  Merge.swift
//  SwiftGit2
//
//  Created by John Biggs on 06.06.2025.
//

import Foundation
import Clibgit2

public struct MergeFlags: RawRepresentable, OptionSet {
    public let rawValue: git_merge_flag_t.RawValue

    init(mergeFlag: git_merge_flag_t) {
        self.init(rawValue: mergeFlag.rawValue)
    }

    public init(rawValue: git_merge_flag_t.RawValue) {
        self.rawValue = rawValue
    }

    static let findRenames = Self(mergeFlag: GIT_MERGE_FIND_RENAMES)
    static let failOnConflict = Self(mergeFlag: GIT_MERGE_FAIL_ON_CONFLICT)
    static let skipREUC = Self(mergeFlag: GIT_MERGE_SKIP_REUC)
    static let virtualBase = Self(mergeFlag: GIT_MERGE_VIRTUAL_BASE)
}

public struct MergeFileFlags: RawRepresentable, OptionSet {
    public let rawValue: git_merge_file_flag_t.RawValue

    public init(rawValue: git_merge_file_flag_t.RawValue) {
        self.rawValue = rawValue
    }

    init(mergeFileFlag: git_merge_file_flag_t) {
        self.init(rawValue: mergeFileFlag.rawValue)
    }

    static let `default` = Self(mergeFileFlag: GIT_MERGE_FILE_DEFAULT)
    static let styleMerge = Self(mergeFileFlag: GIT_MERGE_FILE_STYLE_MERGE)
    static let styleDiff3 = Self(mergeFileFlag: GIT_MERGE_FILE_STYLE_DIFF3)
    static let simplifyAlnum = Self(mergeFileFlag: GIT_MERGE_FILE_SIMPLIFY_ALNUM)
    static let ignoreWhitespace = Self(mergeFileFlag: GIT_MERGE_FILE_IGNORE_WHITESPACE)
    static let ignoreWhitespaceChange = Self(mergeFileFlag: GIT_MERGE_FILE_IGNORE_WHITESPACE_CHANGE)
    static let ignoreWhitespaceEol = Self(mergeFileFlag: GIT_MERGE_FILE_IGNORE_WHITESPACE_EOL)
    static let diffPatience = Self(mergeFileFlag: GIT_MERGE_FILE_DIFF_PATIENCE)
    static let diffMinimal = Self(mergeFileFlag: GIT_MERGE_FILE_DIFF_MINIMAL)
    static let styleZdiff3 = Self(mergeFileFlag: GIT_MERGE_FILE_STYLE_ZDIFF3)
    static let acceptConflicts = Self(mergeFileFlag: GIT_MERGE_FILE_ACCEPT_CONFLICTS)
}

public enum MergeFileFavor: RawRepresentable {
    case normal
    case ours
    case theirs
    case union

    public var rawValue: git_merge_file_favor_t {
        switch self {
        case .normal:
            return GIT_MERGE_FILE_FAVOR_NORMAL
        case .ours:
            return GIT_MERGE_FILE_FAVOR_OURS
        case .theirs:
            return GIT_MERGE_FILE_FAVOR_THEIRS
        case .union:
            return GIT_MERGE_FILE_FAVOR_UNION
        }
    }

    public init?(rawValue: git_merge_file_favor_t) {
        switch rawValue {
        case GIT_MERGE_FILE_FAVOR_NORMAL:
            self = .normal
        case GIT_MERGE_FILE_FAVOR_OURS:
            self = .ours
        case GIT_MERGE_FILE_FAVOR_THEIRS:
            self = .theirs
        case GIT_MERGE_FILE_FAVOR_UNION:
            self = .union
        default:
            return nil
        }
    }
}

public class MergeOptions: GitCallbackOptions<git_merge_options> {
    /// This object supports all of the properties for git_merge_options, except for git_diff_similarity_metric.
    init(
        flags: MergeFlags? = nil,
        renameThreshold: Int? = nil,
        targetLimit: Int? = nil,
        recursionLimit: Int? = nil,
        defaultDriver: String? = nil,
        fileFavor: MergeFileFavor? = nil,
        fileFlags: MergeFileFlags? = nil
    ) throws {
        try super.init()
        if let flags {
            self.options.flags = flags.rawValue
        }
        if let renameThreshold {
            self.options.rename_threshold = UInt32(renameThreshold)
        }
        if let targetLimit {
            self.options.target_limit = UInt32(targetLimit)
        }
        if let recursionLimit {
            self.options.recursion_limit = UInt32(recursionLimit)
        }
        if let defaultDriver {
            defaultDriver.withCString {
                let copy = UnsafeMutablePointer<CChar>.allocate(capacity: defaultDriver.count + 1)
                copy.initialize(from: $0, count: defaultDriver.count + 1)
                self.options.default_driver = UnsafePointer(copy)
            }
        }
        if let fileFavor {
            self.options.file_favor = fileFavor.rawValue
        }
        if let fileFlags {
            self.options.file_flags = fileFlags.rawValue
        }
    }

    deinit {
        self.options.default_driver.deallocate()
    }
}

extension Repository {
    public func mergeBase(_ one: PointerTo<Commit>, _ two: PointerTo<Commit>) throws -> PointerTo<Commit> {
        var out = git_oid()

        var oneOid = one.oid.rawValue
        var twoOid = two.oid.rawValue
        try calling(git_merge_base(
            &out,
            self.pointer,
            &oneOid,
            &twoOid
        ))

        return .init(.init(rawValue: out))
    }

    public func mergeBase(_ commits: [PointerTo<Commit>]) throws -> PointerTo<Commit> {
        try commits
            .map(\.oid.rawValue)
            .withUnsafeBufferPointer {
                var out = git_oid()
                try calling(
                    git_merge_base_many(
                        &out,
                        self.pointer,
                        commits.count,
                        $0.baseAddress
                    )
                )

                return .init(.init(rawValue: out))
            }
    }

    public func mergeBases(_ one: PointerTo<Commit>, _ two: PointerTo<Commit>) throws -> [PointerTo<Commit>] {
        var out = git_oidarray()

        var oneOid = one.oid.rawValue
        var twoOid = two.oid.rawValue
        try calling(git_merge_bases(
            &out,
            self.pointer,
            &oneOid,
            &twoOid
        ))

        defer {
            git_oidarray_dispose(&out)
        }

        return UnsafeBufferPointer(start: out.ids, count: out.count).map {
            .init(.init(rawValue: $0))
        }
    }

    public func mergeBases(_ commits: [PointerTo<Commit>]) throws -> [PointerTo<Commit>] {
        try commits
            .map(\.oid.rawValue)
            .withUnsafeBufferPointer {
                var out = git_oidarray()

                try calling(
                    git_merge_bases_many(
                        &out,
                        self.pointer,
                        commits.count,
                        $0.baseAddress
                    )
                )

                defer {
                    git_oidarray_dispose(&out)
                }

                return UnsafeBufferPointer(start: out.ids, count: out.count).map {
                    .init(.init(rawValue: $0))
                }
            }
    }

    public func octopusMergeBase(_ commits: [PointerTo<Commit>]) throws -> PointerTo<Commit> {
        try commits
            .map(\.oid.rawValue)
            .withUnsafeBufferPointer {
                var out = git_oid()

                try calling(
                    git_merge_base_octopus(
                        &out,
                        self.pointer,
                        commits.count,
                        $0.baseAddress
                    )
                )

                return .init(.init(rawValue: out))
            }
    }

    public func merge(heads: [AnnotatedCommit], mergeOptions: MergeOptions, checkoutOptions: CheckoutOptions) throws {
        var headPointers = heads.map(\.pointer)
        return try headPointers.withUnsafeMutableBufferPointer {
                try calling(git_merge(
                    self.pointer,
                    $0.baseAddress,
                    heads.count,
                    &mergeOptions.options,
                    &checkoutOptions.options
                ))
            }
    }
}
