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
        let result = git_mailmap_from_repository(&pointer, repository.pointer)
        guard result == GIT_OK.rawValue, let pointer else {
            throw NSError(gitError: result, pointOfFailure: "git_mailmap_from_repository")
        }

        self.pointer = pointer
    }

    public init(parsing string: String) throws {
        var pointer: OpaquePointer?
        let result = string.withCString {
            git_mailmap_from_buffer(&pointer, $0, string.count)
        }
        guard result == GIT_OK.rawValue, let pointer else {
            throw NSError(gitError: result, pointOfFailure: "git_mailmap_from_buf")
        }

        self.pointer = pointer
    }

    public func resolve(name: String, email: String) throws -> (name: String, email: String) {
        var realNamePointer: UnsafePointer<CChar>?
        var realEmailPointer: UnsafePointer<CChar>?

        let result = git_mailmap_resolve(&realNamePointer, &realEmailPointer, pointer, name, email)
        guard result == GIT_OK.rawValue else {
            throw NSError(gitError: result, pointOfFailure: "git_mailmap_resolve")
        }

        guard let realNamePointer, let realEmailPointer else {
            throw NSError(gitError: GIT_ENOTFOUND.rawValue, pointOfFailure: "git_mailmap_resolve")
        }

        return (String(cString: realNamePointer), String(cString: realEmailPointer))
    }
}
