//
// Created by Arnon Keereena on 4/28/17.
// Copyright (c) 2017 GitHub, Inc. All rights reserved.
//

import Foundation
import Clibgit2

public class CommitIterator: IteratorProtocol, Sequence {
    public typealias Iterator = CommitIterator
    public typealias Element = Result<Commit, GitError>
    let repo: Repository
    private var revisionWalker: OpaquePointer?

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

    init(repo: Repository, root: git_oid) {
        self.repo = repo
        setupRevisionWalker(root: root)
    }

    deinit {
        git_revwalk_free(self.revisionWalker)
    }

    private func setupRevisionWalker(root: git_oid) {
        var oid = root
        git_revwalk_new(&revisionWalker, repo.pointer)
        git_revwalk_sorting(revisionWalker, GIT_SORT_TOPOLOGICAL.rawValue)
        git_revwalk_sorting(revisionWalker, GIT_SORT_TIME.rawValue)
        git_revwalk_push(revisionWalker, &oid)
    }

    public func next() -> Element? {
        var oid = git_oid()
        do {
            switch try Next(git_revwalk_next(&oid, revisionWalker)) {
            case .over:
                return nil
            case .okay:
                var unsafeCommit: OpaquePointer? = nil
                try calling(git_commit_lookup(&unsafeCommit, repo.pointer, &oid))

                guard let unsafeCommit else {
                    throw GitError(
                        code: .notFound,
                        detail: .internal,
                        description: "Commit with oid \(OID(rawValue: oid)) not found"
                    )
                }

                defer {
                    git_commit_free(unsafeCommit)
                }

                return .success(Commit(unsafeCommit))
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
}
