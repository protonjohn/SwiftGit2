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
    public typealias Element = Result<Note, NSError>

    private let repo: Repository
    private let notesRef: String?

    private var noteIterator: OpaquePointer?

    public init(repo: Repository, notesRef: String?) throws {
        self.repo = repo
        self.notesRef = notesRef

        var pointer: OpaquePointer?
        let iteratorResult = git_note_iterator_new(&pointer, repo.pointer, notesRef)
        guard iteratorResult == GIT_OK.rawValue else {
            throw NSError(gitError: iteratorResult, pointOfFailure: "git_note_iterator_new")
        }
        self.noteIterator = pointer
    }

    private enum Next {
        case over
        case okay
        case error(NSError)

        init(_ result: Int32) {
            switch result {
            case GIT_ITEROVER.rawValue:
                self = .over
            case GIT_OK.rawValue:
                self = .okay
            default:
                self = .error(NSError(gitError: result, pointOfFailure: "git_note_next"))
            }
        }
    }

    open func next() -> Result<Note, NSError>? {
        var noteId = git_oid() // we don't do anything with this, it just gives us the blob and not the note object
        var annotatedId = git_oid()
        switch Next(git_note_next(&noteId, &annotatedId, noteIterator)) {
        case .okay:
            var pointer: OpaquePointer?
            let noteResult = git_note_read(&pointer, repo.pointer, notesRef, &annotatedId)
            defer { git_note_free(pointer) }
            guard let pointer, noteResult == GIT_OK.rawValue else {
                return .failure(NSError(gitError: noteResult, pointOfFailure: "git_note_read"))
            }
            return .success(Note(pointer))
        case .error(let error):
            return .failure(error)
        case .over:
            return nil
        }
    }

    deinit {
        git_note_iterator_free(noteIterator)
    }
}
