//
//  Objects.swift
//  SwiftGit2
//
//  Created by Matt Diephouse on 12/4/14.
//  Copyright (c) 2014 GitHub, Inc. All rights reserved.
//

import Foundation
import Clibgit2

public enum GitObjectType: RawRepresentable {
    public typealias RawValue = git_object_t

    case any
    case invalid
    case commit
    case tree
    case blob
    case tag
    case offsetDelta
    case referenceDelta

    public var rawValue: git_object_t {
        switch self {
        case .any:
            return GIT_OBJECT_ANY
        case .invalid:
            return GIT_OBJECT_INVALID
        case .commit:
            return GIT_OBJECT_COMMIT
        case .tree:
            return GIT_OBJECT_TREE
        case .blob:
            return GIT_OBJECT_BLOB
        case .tag:
            return GIT_OBJECT_TAG
        case .offsetDelta:
            return GIT_OBJECT_OFS_DELTA
        case .referenceDelta:
            return GIT_OBJECT_REF_DELTA
        }
    }

    public init?(rawValue: git_object_t) {
        switch rawValue {
        case GIT_OBJECT_ANY:
            self = .any
        case GIT_OBJECT_INVALID:
            self = .invalid
        case GIT_OBJECT_COMMIT:
            self = .commit
        case GIT_OBJECT_TREE:
            self = .tree
        case GIT_OBJECT_BLOB:
            self = .blob
        case GIT_OBJECT_TAG:
            self = .tag
        case GIT_OBJECT_OFS_DELTA:
            self = .offsetDelta
        case GIT_OBJECT_REF_DELTA:
            self = .referenceDelta
        default:
            return nil
        }
    }

    public static func fromPointer(_ pointer: OpaquePointer) -> Self? {
        Self(rawValue: git_object_type(pointer))
    }

    public static func object(_ pointer: OpaquePointer) -> ObjectType? {
        let type = Self.fromPointer(pointer)
        if type == Blob.type {
            return Blob(pointer)
        } else if type == Commit.type {
            return Commit(pointer)
        } else if type == Tag.type {
            return Tag(pointer)
        } else if type == Tree.type {
            return Tree(pointer)
        }
        return nil
    }
}

/// A git object.
public protocol ObjectType {
    static var type: GitObjectType { get }

    /// The OID of the object.
    var oid: OID { get }

    /// Create an instance with the underlying libgit2 type.
    init(_ pointer: OpaquePointer)
}

public extension ObjectType {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.oid == rhs.oid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(oid)
    }
}

public struct Signature {
    /// The name of the person.
    public let name: String

    /// The email of the person.
    public let email: String

    /// The time when the action happened.
    public let time: Date

    /// The time zone that `time` should be interpreted relative to.
    public let timeZone: TimeZone

    /// Create an instance with custom name, email, dates, etc.
    public init(name: String, email: String, time: Date = Date(), timeZone: TimeZone = TimeZone.autoupdatingCurrent) {
        self.name = name
        self.email = email
        self.time = time
        self.timeZone = timeZone
    }

    /// Create an instance with a libgit2 `git_signature`.
    public init(_ signature: git_signature) {
        name = String(validatingUTF8: signature.name)!
        email = String(validatingUTF8: signature.email)!
        time = Date(timeIntervalSince1970: TimeInterval(signature.when.time))
        timeZone = TimeZone(secondsFromGMT: 60 * Int(signature.when.offset))!
    }

    /// Return an unsafe pointer to the `git_signature` struct.
    /// Caller is responsible for freeing it with `git_signature_free`.
    func makeUnsafeSignature() -> Result<UnsafeMutablePointer<git_signature>, NSError> {
        var signature: UnsafeMutablePointer<git_signature>? = nil
        let time = git_time_t(self.time.timeIntervalSince1970)  // Unix epoch time
        let offset = Int32(timeZone.secondsFromGMT(for: self.time) / 60)
        let signatureResult = git_signature_new(&signature, name, email, time, offset)
        guard signatureResult == GIT_OK.rawValue, let signatureUnwrap = signature else {
            let err = NSError(gitError: signatureResult, pointOfFailure: "git_signature_new")
            return .failure(err)
        }
        return .success(signatureUnwrap)
    }
}

extension Signature: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(email)
        hasher.combine(time)
    }
}

/// A git note.
public struct Note: ObjectType, Hashable {
    /// Notes are blobs in special branches that point to other objects.
    public static let type: GitObjectType = .blob

    /// The OID of the note blob.
    public let oid: OID
    /// The author of the note.
    public let author: Signature
    /// The committer of the note.
    public let committer: Signature
    /// The note message.
    public let message: String

    internal init(oid: OID, author: Signature, committer: Signature, message: String) {
        self.oid = oid
        self.author = author
        self.committer = committer
        self.message = message
    }

    /// Create an instance with a libgit2 `git_note` object.
    public init(_ pointer: OpaquePointer) {
        oid = OID(git_note_id(pointer).pointee)
        author = Signature(git_note_author(pointer).pointee)
        committer = Signature(git_note_committer(pointer).pointee)
        message = String(cString: git_note_message(pointer))
    }
}

/// A git commit.
public struct Commit: ObjectType, Hashable {
    public static let type: GitObjectType = .commit

    /// The OID of the commit.
    public let oid: OID

    /// The OID of the commit's tree.
    public let tree: PointerTo<Tree>

    /// The OIDs of the commit's parents.
    public let parents: [PointerTo<Commit>]

    /// The author of the commit.
    public let author: Signature

    /// The committer of the commit.
    public let committer: Signature

    /// The date the commit was made.
    public let date: Date

    /// The full message of the commit.
    public let message: String

    /// Create an instance with a libgit2 `git_commit` object.
    public init(_ pointer: OpaquePointer) {
        oid = OID(git_object_id(pointer).pointee)
        message = String(validatingUTF8: git_commit_message(pointer))!
        author = Signature(git_commit_author(pointer).pointee)
        committer = Signature(git_commit_committer(pointer).pointee)
        tree = PointerTo(OID(git_commit_tree_id(pointer).pointee))

        let time = git_commit_time(pointer)
        date = Date(timeIntervalSince1970: TimeInterval(time))

        self.parents = (0..<git_commit_parentcount(pointer)).map {
            return PointerTo(OID(git_commit_parent_id(pointer, $0).pointee))
        }
    }

    public struct Trailer: Hashable {
        public let key: String
        public let value: String

        public init(_ trailer: git_message_trailer) {
            self.key = String(cString: trailer.key)
            self.value = String(cString: trailer.value)
        }
    }

    public func trailers() -> Result<[Trailer], NSError> {
        var array = git_message_trailer_array()
        defer { git_message_trailer_array_free(&array) }

        let result = git_message_trailers(&array, message)
        guard result == GIT_OK.rawValue else {
            let error = NSError(gitError: result, pointOfFailure: "git_message_trailers")
            return .failure(error)
        }

        let trailers = UnsafeBufferPointer(start: array.trailers, count: array.count)
            .map(Trailer.init)

        return .success(trailers)
    }
}

/// A git tree.
public struct Tree: ObjectType, Hashable {
    public static let type: GitObjectType = .tree

    /// An entry in a `Tree`.
    public struct Entry: Hashable {
        /// The entry's UNIX file attributes.
        public let attributes: Int32

        /// The object pointed to by the entry.
        public let object: Pointer

        /// The file name of the entry.
        public let name: String

        /// Create an instance with a libgit2 `git_tree_entry`.
        public init(_ pointer: OpaquePointer) {
            let oid = OID(git_tree_entry_id(pointer).pointee)
            attributes = Int32(git_tree_entry_filemode(pointer).rawValue)
            object = Pointer(oid: oid, type: git_tree_entry_type(pointer))!
            name = String(validatingUTF8: git_tree_entry_name(pointer))!
        }

        /// Create an instance with the individual values.
        public init(attributes: Int32, object: Pointer, name: String) {
            self.attributes = attributes
            self.object = object
            self.name = name
        }
    }

    /// The OID of the tree.
    public let oid: OID

    /// The entries in the tree.
    public let entries: [String: Entry]

    /// Create an instance with a libgit2 `git_tree`.
    public init(_ pointer: OpaquePointer) {
        oid = OID(git_object_id(pointer).pointee)

        var entries: [String: Entry] = [:]
        for idx in 0..<git_tree_entrycount(pointer) {
            let entry = Entry(git_tree_entry_byindex(pointer, idx)!)
            entries[entry.name] = entry
        }
        self.entries = entries
    }
}

extension Tree.Entry: CustomStringConvertible {
    public var description: String {
        return "\(attributes) \(object) \(name)"
    }
}

/// A git blob.
public struct Blob: ObjectType, Hashable {
    public static let type: GitObjectType = .blob

    /// The OID of the blob.
    public let oid: OID

    /// The contents of the blob.
    public let data: Data

    /// Create an instance with a libgit2 `git_blob`.
    public init(_ pointer: OpaquePointer) {
        oid = OID(git_object_id(pointer).pointee)

        let length = Int(git_blob_rawsize(pointer))
        data = Data(bytes: git_blob_rawcontent(pointer), count: length)
    }
}

/// An annotated git tag.
public struct Tag: ObjectType, Hashable {
    public static let type: GitObjectType = .tag

    /// The OID of the tag.
    public let oid: OID

    /// The tagged object.
    public let target: Pointer

    /// The name of the tag.
    public let name: String

    /// The tagger (author) of the tag.
    public let tagger: Signature

    /// The message of the tag.
    public let message: String

    /// Create an instance with a libgit2 `git_tag`.
    public init(_ pointer: OpaquePointer) {
        oid = OID(git_object_id(pointer).pointee)
        let targetOID = OID(git_tag_target_id(pointer).pointee)
        target = Pointer(oid: targetOID, type: git_tag_target_type(pointer))!
        name = String(validatingUTF8: git_tag_name(pointer))!
        tagger = Signature(git_tag_tagger(pointer).pointee)
        message = String(validatingUTF8: git_tag_message(pointer))!
    }
}
