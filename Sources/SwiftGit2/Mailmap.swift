//
//  Mailmap.swift
//  
//
//  Created by John Biggs on 08.01.24.
//

import Foundation
import Clibgit2

open class Mailmap {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        git_mailmap_free(pointer)
    }

    public init(repository: Repository) throws {
        var pointer: OpaquePointer?
        try calling(git_mailmap_from_repository(&pointer, repository.pointer))
        self.pointer = pointer!
    }

    public init(parsing string: String) throws {
        var pointer: OpaquePointer?
        _ = try string.withCString {
            try calling(git_mailmap_from_buffer(&pointer, $0, string.count))
        }
        self.pointer = pointer!
    }

    public func resolve(name: String, email: String) throws -> (name: String, email: String) {
        var realNamePointer: UnsafePointer<CChar>?
        var realEmailPointer: UnsafePointer<CChar>?

        try calling(git_mailmap_resolve(&realNamePointer, &realEmailPointer, pointer, name, email))

        guard let realNamePointer, let realEmailPointer else {
            throw GitError(
                code: .notFound,
                detail: .internal,
                description: "Couldn't resolve name and/or email in mailmap"
            )
        }

        return (String(cString: realNamePointer), String(cString: realEmailPointer))
    }
}
