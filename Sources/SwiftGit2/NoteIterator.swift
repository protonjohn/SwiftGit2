//
//  NoteIterator.swift
//  
//
//  Created by John Biggs on 06.12.23.
//

import Foundation
import Clibgit2

open class NoteIterator: IteratorProtocol, Sequence {
    public typealias Iterator = NoteIterator
    public typealias Element = Result<Note, GitError>

    private let repo: Repository
    private let notesRef: String?

    private var noteIterator: OpaquePointer?

    public init(repo: Repository, notesRef: String?) throws {
        self.repo = repo
        self.notesRef = notesRef

        var pointer: OpaquePointer?
        try calling(git_note_iterator_new(&pointer, repo.pointer, notesRef))
        self.noteIterator = pointer
    }

    private enum Next {
        case over
        case okay

        init(_ result: Int32) throws {
            let code = GitError.Code(int32Value: result)
            switch code {
            case .endIteration:
                self = .over
            case .ok:
                self = .okay
            default:
                throw GitError.lastError(with: code)
            }
        }
    }

    open func next() -> Element? {
        var noteId = git_oid() // we don't do anything with this, it just gives us the blob and not the note object
        var annotatedId = git_oid()
        do {
            switch try Next(git_note_next(&noteId, &annotatedId, noteIterator)) {
            case .okay:
                var pointer: OpaquePointer?
                try calling(git_note_read(&pointer, repo.pointer, notesRef, &annotatedId))
                defer { git_note_free(pointer) }
                return .success(Note(pointer!))
            case .over:
                return nil
            }
        } catch let error as GitError {
            return .failure(error)
        } catch {
            assertionFailure("Unexpected error: \(String(describing: error))")
            return .failure(GitError(
                code: .invalid,
                detail: .internal,
                description: "Unexpected error: \(String(describing: error))")
            )
        }
    }

    deinit {
        git_note_iterator_free(noteIterator)
    }
}
