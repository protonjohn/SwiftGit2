//
//  Repository.swift
//  SwiftGit2
//
//  Created by Matt Diephouse on 11/7/14.
//  Copyright (c) 2014 GitHub, Inc. All rights reserved.
//

import Foundation
import Clibgit2

/// A git repository.
public final class Repository {
    public typealias SigningCallback = (Data) throws -> Data?

    public func push(remote remoteName: String = "origin", options: PushOptions, reference: ReferenceType) throws {

        var remote: OpaquePointer? = nil
        try calling(git_remote_lookup(&remote, pointer, remoteName))
        defer { git_remote_free(remote) }

        let refnames = [reference.longName]
        var array = git_strarray(strings: refnames)
        defer { git_strarray_free(&array) }

        try calling(git_remote_push(remote, &array, &options.options))
    }

    
    // MARK: - Creating Repositories

    /// Create a new repository at the given URL.
    ///
    /// URL - The URL of the repository.
    ///
    /// Returns a `Result` with a `Repository` or an error.
    public class func create(at url: URL) throws -> Repository {
        var pointer: OpaquePointer? = nil
        try url.withUnsafeFileSystemRepresentation {
            _ = try calling(git_repository_init(&pointer, $0, 0))
        }
        return Repository(pointer!)
    }

    /// Load the repository at the given URL.
    ///
    /// URL - The URL of the repository.
    ///
    /// Returns a `Result` with a `Repository` or an error.
    public class func at(_ url: URL) throws -> Repository {
        var pointer: OpaquePointer? = nil
        try url.withUnsafeFileSystemRepresentation {
            _ = try calling(git_repository_open(&pointer, $0))
        }
        return Repository(pointer!)
    }

    /// Clone the repository from a given URL.
    ///
    /// remoteURL        - The URL of the remote repository
    /// localURL         - The URL to clone the remote repository into
    /// localClone       - Will not bypass the git-aware transport, even if remote is local.
    /// bare             - Clone remote as a bare repository.
    /// credentials      - Credentials to be used when connecting to the remote.
    /// checkoutStrategy - The checkout strategy to use, if being checked out.
    /// checkoutProgress - A block that's called with the progress of the checkout.
    ///
    /// Returns a `Result` with a `Repository` or an error.
    public class func clone(
        from remoteURL: URL,
        to localURL: URL,
        localClone: Bool = false,
        bare: Bool = false,
        credentials: Credentials = .default,
        options: CloneOptions
    ) throws -> Repository {
        var pointer: OpaquePointer? = nil
        let absoluteRemoteURLString = remoteURL.absoluteString
        let remoteURLString = absoluteRemoteURLString.hasPrefix("file:") ? remoteURL.path : remoteURL.absoluteString

        try localURL.withUnsafeFileSystemRepresentation { localPath in
            _ = try calling(git_clone(&pointer, remoteURLString, localPath, &options.options))
        }

        return Repository(pointer!)
    }
    
    // MARK: - Initializers

    /// Create an instance with a libgit2 `git_repository` object.
    ///
    /// The Repository assumes ownership of the `git_repository` object.
    public init(_ pointer: OpaquePointer) {
        self.pointer = pointer

        let path = git_repository_workdir(pointer)
        self.directoryURL = path.map({ URL(fileURLWithPath: String(validatingUTF8: $0)!, isDirectory: true) })
    }

    deinit {
        git_repository_free(pointer)
    }

    // MARK: - Properties

    /// The underlying libgit2 `git_repository` object.
    public let pointer: OpaquePointer

    /// The URL of the repository's working directory, or `nil` if the
    /// repository is bare.
    public let directoryURL: URL?

    // MARK: - Configuration
    public func config() throws -> Config {
        var pointer: OpaquePointer?
        try calling(git_repository_config(&pointer, self.pointer))
        return .init(pointer: pointer!)
    }

    // MARK: - Object Lookups

    /// Load a libgit2 object and transform it to something else.
    ///
    /// oid       - The OID of the object to look up.
    /// type      - The type of the object to look up.
    /// transform - A function that takes the libgit2 object and transforms it
    ///             into something else.
    ///
    /// Returns the result of calling `transform` or an error if the object
    /// cannot be loaded.
    private func withGitObject<T>(
        _ oid: OID,
        type: GitObjectType,
        transform: (OpaquePointer) throws -> T
    ) throws -> T {
        var pointer: OpaquePointer? = nil
        var oid = oid.rawValue

        try calling(git_object_lookup(&pointer, self.pointer, &oid, type.rawValue))
        defer { git_object_free(pointer) }

        let value = try transform(pointer!)
        return value
    }

    private func withGitObjects<T>(
        _ oids: [OID],
        type: git_object_t,
        transform: ([OpaquePointer]) throws -> T
    ) throws -> T {
        var pointers = [OpaquePointer]()
        defer {
            for pointer in pointers {
                git_object_free(pointer)
            }
        }

        for oid in oids {
            var pointer: OpaquePointer? = nil
            var oid = oid.rawValue
            try calling(git_object_lookup(&pointer, self.pointer, &oid, type))
            pointers.append(pointer!)
        }

        return try transform(pointers)
    }

    private func withGitReference<T>(_ reference: ReferenceType, transform: (OpaquePointer) throws -> T) throws -> T {
        var pointer: OpaquePointer? = nil
        try calling(git_reference_lookup(&pointer, self.pointer, reference.longName))
        return try transform(pointer!)
    }

    /// Loads the object with the given OID.
    ///
    /// oid - The OID of the blob to look up.
    ///
    /// Returns a `Blob`, `Commit`, `Tag`, or `Tree` if one exists, or an error.
    public func object(_ oid: OID) throws -> ObjectType {
        return try withGitObject(oid, type: .any) { pointer in
            guard let object = GitObjectType.object(pointer) else {
                throw GitError(
                    code: .invalid,
                    detail: .object,
                    description: "Unrecognized git_object_t for oid '\(oid)'."
                )
            }
            return object
        }
    }
    
    /// Loads the blob with the given OID.
    ///
    /// oid - The OID of the blob to look up.
    ///
    /// Returns the blob if it exists, or an error.
    public func blob(_ oid: OID) throws -> Blob {
        return try withGitObject(oid, type: .blob) { Blob($0) }
    }

    /// Loads the commit with the given OID.
    ///
    /// oid - The OID of the commit to look up.
    ///
    /// Returns the commit if it exists, or an error.
    public func commit(_ oid: OID) throws -> Commit {
        return try withGitObject(oid, type: .commit) { Commit($0) }
    }

    /// Loads the tag with the given OID.
    ///
    /// oid - The OID of the tag to look up.
    ///
    /// Returns the tag if it exists, or an error.
    public func tag(_ oid: OID) throws -> Tag {
        return try withGitObject(oid, type: .tag) { Tag($0) }
    }

    /// Creates an annotated tag with the given name, target, signature, and message.
    ///
    /// Returns the tag if successful, or an error.
    public func createTag(_ name: String, target: ObjectType, signature: Signature, message: String) throws -> Tag {
        var buf = git_buf()
        git_message_prettify(&buf, message, 0, /* ascii for # */ 35)
        defer { git_buf_free(&buf) }

        let signature = try signature.makeUnsafeSignature()

        defer { signature.deallocate() }
        return try withGitObject(target.oid, type: type(of: target).type) { targetObject in
            var oid = git_oid()

            try calling(git_tag_create(
                &oid,
                pointer,
                name,
                targetObject,
                signature,
                buf.ptr,
                /* force */ 0
            ))

            return try withGitObject(
                OID(rawValue: oid),
                type: .tag
            ) { Tag($0) }
        }
    }

    public func createTag(
        _ name: String,
        target: ObjectType,
        signature: Signature,
        message: String?,
        force: Bool = false,
        signingCallback: SigningCallback?
    ) throws -> Tag {
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "Z"
        let tz = formatter.string(from: date)

        var buffer = """
            object \(target.oid)
            type \(type(of: target).type)
            tag \(name)
            tagger \(signature) \(Int(date.timeIntervalSince1970)) \(tz)
            """

        if var message {
            if !message.hasSuffix("\n") {
                message += "\n"
            }

            var buf = git_buf()
            git_message_prettify(&buf, message, 0, /* ascii for # */ 35)
            defer { git_buf_free(&buf) }

            let data = Data(
                bytes: buf.ptr,
                count: strnlen(buf.ptr, buf.size)
            )

            let str = String(data: data, encoding: .utf8)!
            buffer += "\n\n\(str)"
        }

        if let signingCallback,
           let data = buffer.data(using: .utf8),
           let signature = try signingCallback(data) {

            guard var tagSignature = String(data: signature, encoding: .utf8) else {
                throw GitError(
                    code: .invalid,
                    detail: .tag,
                    description: "Signature callback did not return valid data"
                )
            }

            if !tagSignature.hasSuffix("\n") {
                tagSignature += "\n"
            }
            buffer += tagSignature
        }

        let signature = try signature.makeUnsafeSignature()
        defer { signature.deallocate() }

        return try withGitObject(target.oid, type: type(of: target).type) { targetObject in
            var tagOid = git_oid()
            try calling(git_tag_create_from_buffer(
                &tagOid,
                self.pointer,
                buffer,
                force ? 1 : 0
            ))

            return try withGitObject(
                OID(rawValue: tagOid),
                type: .tag
            ) { Tag($0) }
        }
    }

    /// Loads the tree with the given OID.
    ///
    /// oid - The OID of the tree to look up.
    ///
    /// Returns the tree if it exists, or an error.
    public func tree(_ oid: OID) throws -> Tree {
        return try withGitObject(oid, type: .tree) { Tree($0) }
    }

    /// Loads the referenced object from the pointer.
    ///
    /// pointer - A pointer to an object.
    ///
    /// Returns the object if it exists, or an error.
    public func object<T>(from pointer: PointerTo<T>) throws -> T {
        return try withGitObject(pointer.oid, type: pointer.type) { T($0) }
    }

    /// Loads the referenced object from the pointer.
    ///
    /// pointer - A pointer to an object.
    ///
    /// Returns the object if it exists, or an error.
    public func object(from pointer: Pointer) throws -> ObjectType {
        switch pointer {
        case let .blob(oid):
            return try blob(oid)
        case let .commit(oid):
            return try commit(oid)
        case let .tag(oid):
            return try tag(oid)
        case let .tree(oid):
            return try tree(oid)
        }
    }

    // MARK: - Remote Lookups

    /// Loads all the remotes in the repository.
    ///
    /// Returns an array of remotes, or an error.
    public func allRemotes() throws -> [Remote] {
        var array = git_strarray()
        try calling(git_remote_list(&array, self.pointer))
        defer { git_strarray_free(&array) }

        return try array.map {
            try self.remote(named: $0)
        }
    }

    private func withUnsafeRemote<A>(named name: String, _ callback: (OpaquePointer) throws -> A) throws -> A {
        var pointer: OpaquePointer? = nil
        defer { git_remote_free(pointer) }

        try calling(git_remote_lookup(&pointer, self.pointer, name))
        return try callback(pointer!)
    }

    /// Load a remote from the repository.
    ///
    /// name - The name of the remote.
    ///
    /// Returns the remote if it exists, or an error.
    public func remote(named name: String) throws -> Remote {
        return try withUnsafeRemote(named: name, Remote.init)
    }

    /// Download new data and update tips
    public func fetch(_ remote: Remote) throws {
        return try withUnsafeRemote(named: remote.name) { remote in
            var opts = git_fetch_options()
            try calling(git_fetch_init_options(&opts, UInt32(GIT_FETCH_OPTIONS_VERSION)))
            try calling(git_remote_fetch(remote, nil, &opts, nil))
        }
    }

    // MARK: - Reference Lookups

    /// Load all the references with the given prefix (e.g. "refs/heads/")
    public func references(withPrefix prefix: String) throws -> [ReferenceType] {
        var array = git_strarray()
        try calling(git_reference_list(&array, self.pointer))
        defer { git_strarray_free(&array) }

        return try array
            .filter {
                $0.hasPrefix(prefix)
            }
            .map {
                try self.reference(named: $0)
            }
    }

    /// Load the reference with the given long name (e.g. "refs/heads/master")
    ///
    /// If the reference is a branch, a `Branch` will be returned. If the
    /// reference is a tag, a `TagReference` will be returned. Otherwise, a
    /// `Reference` will be returned.
    public func reference(named name: String) throws -> ReferenceType {
        var pointer: OpaquePointer? = nil
        try calling(git_reference_lookup(&pointer, self.pointer, name))
        defer { git_reference_free(pointer) }

        return referenceWithLibGit2Reference(pointer!)
    }

    public func createReference(
        named name: String,
        pointingTo oid: OID,
        force: Bool,
        reflogMessage: String
    ) throws -> ReferenceType {
        var pointer: OpaquePointer? = nil
        var oid = oid.rawValue
        try calling(git_reference_create(&pointer, self.pointer, name, &oid, force ? 1 : 0, reflogMessage))
        defer { git_reference_free(pointer) }

        return referenceWithLibGit2Reference(pointer!)
    }

    public func removeReference(named name: String) throws {
        try calling(git_reference_remove(self.pointer, name))
    }

    public func object(parsing spec: String) throws -> ObjectType {
        var pointer: OpaquePointer? = nil
        try calling(git_revparse_single(&pointer, self.pointer, spec))
        defer { git_object_free(pointer) }
        guard let pointer, let object = GitObjectType.object(pointer) else {
            throw GitError(
                code: .invalid,
                detail: .object,
                description: "Unrecognized git_object_t for spec '\(spec)'."
            )
        }
        return object
    }

    public func objects(parsing spec: String) throws -> RevisionSpecification {
        var revspec = git_revspec()
        try calling(git_revparse(&revspec, self.pointer, spec))

        guard let spec = RevisionSpecification(revspec) else {
            throw GitError(
                code: .invalidSpec,
                detail: .invalid,
                description: "Unrecognized revision specification for spec '\(spec)'."
            )
        }

        return spec
    }

    public func setTarget(of reference: ReferenceType, to oid: OID, refLogMessage: String) throws -> ReferenceType {
        var newReferencePointer: OpaquePointer?
        var oid = oid.rawValue

        try withGitReference(reference) { referencePointer in
            _ = try calling(git_reference_set_target(
                &newReferencePointer,
                referencePointer,
                &oid,
                refLogMessage
            ))
        }

        let newReference = referenceWithLibGit2Reference(newReferencePointer!)
        return newReference
    }

    /// Load and return a list of all local branches.
    public func localBranches() throws -> [Branch] {
        try references(withPrefix: "refs/heads/").map { $0 as! Branch }
    }

    /// Load and return a list of all remote branches.
    public func remoteBranches() throws -> [Branch] {
        try references(withPrefix: "refs/remotes/").map { $0 as! Branch }
    }

    /// Load the local branch with the given name (e.g., "master").
    public func localBranch(named name: String) throws -> Branch {
        try reference(named: "refs/heads/" + name) as! Branch
    }

    /// Load the remote branch with the given name (e.g., "origin/master").
    public func remoteBranch(named name: String) throws -> Branch {
        try reference(named: "refs/remotes/" + name) as! Branch
    }

    /// Load and return a list of all the `TagReference`s.
    public func allTags() throws -> [TagReference] {
        try references(withPrefix: "refs/tags/").map { $0 as! TagReference }
    }

    /// Load the tag with the given name (e.g., "tag-2").
    public func tag(named name: String) throws -> TagReference {
        try reference(named: "refs/tags/" + name) as! TagReference
    }

    // MARK: - Working Directory

    /// Load the reference pointed at by HEAD.
    ///
    /// When on a branch, this will return the current `Branch`.
    public func HEAD() throws -> ReferenceType {
        var pointer: OpaquePointer? = nil
        try calling(git_repository_head(&pointer, self.pointer))
        defer { git_reference_free(pointer) }

        return referenceWithLibGit2Reference(pointer!)
    }

    /// Set HEAD to the given oid (detached).
    ///
    /// :param: oid The OID to set as HEAD.
    /// :returns: Returns a result with void or the error that occurred.
    public func setHEAD(_ oid: OID) throws {
        var oid = oid.rawValue
        try calling(git_repository_set_head_detached(self.pointer, &oid))
    }

    /// Set HEAD to the given reference.
    ///
    /// :param: reference The reference to set as HEAD.
    /// :returns: Returns a result with void or the error that occurred.
    public func setHEAD(_ reference: ReferenceType) throws {
        try calling(git_repository_set_head(self.pointer, reference.longName))
    }

    /// Check out HEAD.
    ///
    /// :param: strategy The checkout strategy to use.
    /// :param: progress A block that's called with the progress of the checkout.
    /// :returns: Returns a result with void or the error that occurred.
    public func checkout(options: CheckoutOptions) throws {
        try calling(git_checkout_head(self.pointer, &options.options))
    }

    /// Check out the given OID.
    ///
    /// :param: oid The OID of the commit to check out.
    /// :param: strategy The checkout strategy to use.
    /// :param: progress A block that's called with the progress of the checkout.
    /// :returns: Returns a result with void or the error that occurred.
    public func checkout(_ oid: OID, options: CheckoutOptions) throws {
        try setHEAD(oid)
        try checkout(options: options)
    }

    /// Check out the given reference.
    ///
    /// :param: reference The reference to check out.
    /// :param: strategy The checkout strategy to use.
    /// :param: progress A block that's called with the progress of the checkout.
    /// :returns: Returns a result with void or the error that occurred.
    public func checkout(_ reference: ReferenceType, options: CheckoutOptions) throws {
        try setHEAD(reference)
        try checkout(options: options)
    }

    /// Load all commits in the specified branch in topological & time order descending
    ///
    /// :param: branch The branch to get all commits from
    /// :returns: Returns a result with array of branches or the error that occurred
    public func commits(in branch: Branch) -> CommitIterator {
        let iterator = CommitIterator(repo: self, root: branch.oid.rawValue)
        return iterator
    }
    
    /// Load current commit
    ///
    /// :returns: Returns a result with array of branches or the error that occurred
    func getCurrentCommit() throws -> Commit {
        return try commit(HEAD().oid)
    }

    /// Get the index for the repo. The caller is responsible for freeing the index.
    func unsafeIndex() throws -> OpaquePointer {
        var index: OpaquePointer? = nil
        try calling(git_repository_index(&index, self.pointer))
        return index!
    }

    /// Stage the file(s) under the specified path.
    public func add(path: String) throws {
        var paths = git_strarray(strings: [path])
        defer { git_strarray_free(&paths) }

        let index = try unsafeIndex()
        defer { git_index_free(index) }

        try calling(git_index_add_all(index, &paths, 0, nil, nil))
        // write index to disk
        try calling(git_index_write(index))
    }

    /// Perform a commit with arbitrary numbers of parent commits.
    public func commit(
        tree treeOID: OID,
        parents: [Commit],
        message: String,
        signature: Signature,
        signatureField: String? = nil,
        signingCallback: SigningCallback? = nil
    ) throws -> Commit {
        let signature = try signature.makeUnsafeSignature()
        defer { git_signature_free(signature) }

        var tree: OpaquePointer? = nil
        var treeOIDCopy = treeOID.rawValue
        try calling(git_tree_lookup(&tree, self.pointer, &treeOIDCopy))
        defer { git_tree_free(tree) }

        var msgBuf = git_buf()
        git_message_prettify(&msgBuf, message, 0, /* ascii for # */ 35)
        defer { git_buf_free(&msgBuf) }

        // libgit2 expects a C-like array of parent git_commit pointer
        var parentGitCommits: [OpaquePointer?] = []
        defer {
            for commit in parentGitCommits {
                git_commit_free(commit)
            }
        }
        for parentCommit in parents {
            var parent: OpaquePointer? = nil
            var oid = parentCommit.oid.rawValue
            try calling(git_commit_lookup(&parent, self.pointer, &oid))
            parentGitCommits.append(parent!)
        }

        let parentsContiguous = ContiguousArray(parentGitCommits)
        return try parentsContiguous.withUnsafeBufferPointer { unsafeBuffer in
            var commitOID = git_oid()
            var commitBuf = git_buf()
            let parentsPtr = UnsafeMutablePointer(mutating: unsafeBuffer.baseAddress)

            try calling(git_commit_create_buffer(
                &commitBuf,
                self.pointer,
                signature,
                signature,
                "UTF-8",
                msgBuf.ptr,
                tree,
                parents.count,
                parentsPtr
            ))

            let data = Data(
                bytes: commitBuf.ptr,
                count: strnlen(commitBuf.ptr, commitBuf.size)
            )

            let commitSignature = try signingCallback?(data)
            try data.withUnsafeBytes { content in
                if let commitSignature {
                    _ = try commitSignature.withUnsafeBytes { signature in
                        // all this extra fluff just so we can have an optional signature.
                        try calling(git_commit_create_with_signature(
                            &commitOID,
                            self.pointer,
                            content.baseAddress,
                            signature.baseAddress,
                            signatureField
                        ))
                    }
                } else {
                    try calling(git_commit_create_with_signature(
                        &commitOID,
                        self.pointer,
                        content.baseAddress,
                        nil,
                        signatureField
                    ))
                }
            }
            return try commit(OID(rawValue: commitOID))
        }
    }

    /// Perform a commit of the staged files with the specified message and signature,
    /// assuming we are not doing a merge and using the current tip as the parent.
    public func commit(
        message: String,
        signature: Signature,
        signatureField: String? = nil,
        signingCallback: SigningCallback? = nil
    ) throws -> Commit {
        let index = try unsafeIndex()
        defer { git_index_free(index) }

        var treeOID = git_oid()
        try calling(git_index_write_tree(&treeOID, index))

        var parentID = git_oid()
        try calling(git_reference_name_to_id(&parentID, self.pointer, "HEAD"))

        let parentCommit = try commit(OID(parentID))
        return try commit(
            tree: OID(treeOID),
            parents: [parentCommit],
            message: message,
            signature: signature,
            signatureField: signatureField,
            signingCallback: signingCallback
        )
    }

    // MARK: - Notes
    public func note(for oid: OID, notesRef: String? = nil) throws -> Note {
        var note: OpaquePointer?
        var targetOid = oid.rawValue
        try calling(git_note_read(&note, self.pointer, notesRef, &targetOid))
        defer { git_note_free(note) }
        return Note(note!)
    }

   public func createNote(
        for oid: OID,
        message: String,
        author: Signature,
        committer: Signature,
        notesRef: ReferenceType? = nil,
        force: Bool = false
   ) throws -> Note {
        let _author = try author.makeUnsafeSignature()
        defer { git_signature_free(_author) }

        let _committer = try committer.makeUnsafeSignature()
        defer { git_signature_free(_committer) }

        var noteOid = git_oid()
        var oid = oid.rawValue
        try calling(git_note_create(
            &noteOid,
            self.pointer,
            notesRef?.longName,
            _author,
            _committer,
            &oid,
            message,
            force ? 1 : 0
        ))

        return .init(oid: OID(rawValue: noteOid), author: author, committer: committer, message: message)
    }

    public var defaultNotesRefName: String {
        get throws {
            var buf = git_buf()
            try calling(git_note_default_ref(&buf, self.pointer))

            let data = Data(bytes: buf.ptr, count: strnlen(buf.ptr, buf.size))
            guard let name = String(data: data, encoding: .utf8) else {
                throw NSError(
                    domain: "org.libgit2.SwiftGit2",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Could not determine default notes ref for repository.",
                    ]
                )
            }
            return name
        }
    }

    /// Similar to how we have to work around libgit2 to create signed tags, we do
    /// some trickery here with Git internals to allow signing git note commits.
    public func createNote(
         for oid: OID,
         message: String,
         author: Signature,
         committer: Signature,
         noteCommitMessage: String? = nil,
         notesRefName: String? = nil,
         signatureField: String? = nil,
         force: Bool = false,
         signingCallback: SigningCallback?
    ) throws -> Note {
        let notesRefName = try notesRefName ?? defaultNotesRefName

        var parent: Commit?
        if let reference = try? reference(named: notesRefName) {
            parent = try commit(reference.oid)
        }

        let (noteCommit, _) = try createNoteCommit(
            for: oid,
            message: message,
            parent: parent,
            author: author,
            committer: committer,
            noteCommitMessage: noteCommitMessage,
            updateRefName: notesRefName,
            signatureField: signatureField,
            force: force,
            signingCallback: signingCallback
        )

        return try readNoteCommit(for: oid, commit: noteCommit)
    }

    public func createNoteCommit(
        for oid: OID,
        message: String,
        parent: Commit?,
        author: Signature,
        committer: Signature,
        noteCommitMessage: String? = nil,
        updateRefName: String? = nil, // This is a string so it can create the reference if needed
        signatureField: String? = nil,
        force: Bool = false,
        signingCallback: SigningCallback? = nil
    ) throws -> (Commit, Blob) {
        let author = try author.makeUnsafeSignature()
        defer { git_signature_free(author) }

        let committer = try committer.makeUnsafeSignature()
        defer { git_signature_free(committer) }

        var oid = oid.rawValue
        var noteCommitOid = git_oid()
        var noteBlobOid = git_oid()

        if let parent {
            try withGitObject(parent.oid, type: .commit) { parentCommit in
                _ = try calling(git_note_commit_create(
                    &noteCommitOid,
                    &noteBlobOid,
                    self.pointer,
                    parentCommit,
                    author,
                    committer,
                    &oid,
                    message,
                    force ? 1 : 0
                ))
            }
        } else {
            try calling(git_note_commit_create(
                &noteCommitOid,
                &noteBlobOid,
                self.pointer,
                nil,
                author,
                committer,
                &oid,
                message,
                force ? 1 : 0
            ))
        }

        var noteCommit = try commit(OID(rawValue: noteCommitOid))
        let noteBlob = try blob(OID(rawValue: noteBlobOid))

        if let signingCallback {
            // git_note_commit_create makes a dangling commit anyway, it should eventually get picked up
            // by the garbage collector. Create a commit with exactly the same contents as the note commit,
            // but pass the signing callback as well so that we can sign the contents. Then return that one.
            noteCommit = try commit(
                tree: noteCommit.tree.oid,
                parents: noteCommit.parents.map { try commit($0.oid) },
                message: noteCommitMessage ?? noteCommit.message,
                signature: noteCommit.author,
                signatureField: signatureField,
                signingCallback: signingCallback
            )
        }

        if let updateRefName {
            let subject = noteCommit.message.split(separator: "\n", maxSplits: 1).first!
            // We use 'create' with force here in case the reference doesn't already exist. If it does, it will be
            // overwritten instead.
            _ = try createReference(
                named: updateRefName,
                pointingTo: noteCommit.oid,
                force: true,
                reflogMessage: "commit: \(subject)"
            )
        }

        return (noteCommit, noteBlob)
    }

    public func removeNoteCommit(
        for oid: OID,
        commit: Commit,
        author: Signature,
        committer: Signature,
        updateRef: ReferenceType? = nil,
        signatureField: String? = nil,
        force: Bool = false,
        signingCallback: SigningCallback? = nil
    ) throws -> Commit {
        let author = try author.makeUnsafeSignature()
        defer { git_signature_free(author) }

        let committer = try committer.makeUnsafeSignature()
        defer { git_signature_free(committer) }

        var oid = oid.rawValue
        var noteCommitOid = git_oid()

        try withGitObject(commit.oid, type: .commit) { commitPointer in
            _ = try calling(git_note_commit_remove(
                &noteCommitOid,
                self.pointer,
                commitPointer,
                author,
                committer,
                &oid
            ))
        }

        var noteCommit = try self.commit(OID(rawValue: noteCommitOid))
        if let signingCallback {
            noteCommit = try self.commit(
                tree: noteCommit.tree.oid,
                parents: noteCommit.parents.map { try self.commit($0.oid) },
                message: noteCommit.message,
                signature: noteCommit.author,
                signatureField: signatureField,
                signingCallback: signingCallback
            )
        }

        if let updateRef {
            let subject = noteCommit.message.split(separator: "\n", maxSplits: 1).first!
            _ = try setTarget(
                of: updateRef,
                to: noteCommit.oid,
                refLogMessage: "commit: \(subject)"
            )
        }
        return noteCommit
    }

    public func readNoteCommit(
        for oid: OID,
        commit: Commit
    ) throws -> Note {
        var oid = oid.rawValue
        var note: OpaquePointer?

        try withGitObject(commit.oid, type: .commit) { commitPointer in
            _ = try calling(git_note_commit_read(
                &note,
                self.pointer,
                commitPointer,
                &oid
            ))
        }

        return Note(note!)
    }

    public func removeNote(
        for oid: OID,
        author: Signature,
        committer: Signature,
        notesRefName: String? = nil
    ) throws {
        let author = try author.makeUnsafeSignature()
        defer { git_signature_free(author) }

        let committer = try committer.makeUnsafeSignature()
        defer { git_signature_free(committer) }

        var oid = oid.rawValue
        try calling(git_note_remove(self.pointer, notesRefName, author, committer, &oid))
    }

    public func removeNote(
        for oid: OID,
        author: Signature,
        committer: Signature,
        noteCommitMessage: String? = nil,
        notesRefName: String? = nil,
        signatureField: String? = nil,
        signingCallback: SigningCallback? = nil
    ) throws {
        let author = try author.makeUnsafeSignature()
        defer { git_signature_free(author) }

        let committer = try committer.makeUnsafeSignature()
        defer { git_signature_free(committer) }

        var oid = oid.rawValue

        // We have to get this first, just in case getting the default fails after we create the note.
        let notesRefName = try notesRefName ?? defaultNotesRefName
        try calling(git_note_remove(self.pointer, notesRefName, author, committer, &oid))

        guard let signingCallback else {
            return
        }

        let notesRef = try reference(named: notesRefName)
        // Removing the note should have updated the ref by default, find the notes commit at the tip of the branch
        var noteCommit = try commit(notesRef.oid)

        do {
            noteCommit = try commit(
                tree: noteCommit.tree.oid,
                parents: noteCommit.parents.map { try commit($0.oid) },
                message: noteCommitMessage ?? noteCommit.message,
                signature: noteCommit.author,
                signatureField: signatureField,
                signingCallback: signingCallback
            )

            _ = try setTarget(of: notesRef, to: noteCommit.oid, refLogMessage: "commit: \(noteCommit.message)")
        } catch { // Something happened after we created the note commit, so we need to roll back the reference.
            if let parent = noteCommit.parents.first {
                _ = try setTarget(
                    of: notesRef,
                    to: parent.oid,
                    refLogMessage: "signing error: rollback git_note_remove"
                )
            } else {
                try removeReference(named: notesRefName)
            }
        }
    }

    // MARK: - Diffs

    public func diff(for commit: Commit) throws -> Diff {
        var mergeDiff: OpaquePointer? = nil
        defer {
            if let mergeDiff {
                git_object_free(mergeDiff)
            }
        }

        for parent in commit.parents {
            // Merge all parent diffs together...?
            try withUnsafeDiff(from: parent.oid, to: commit.oid) { newDiff in
                if mergeDiff == nil {
                    mergeDiff = newDiff
                } else {
                    try calling(git_diff_merge(mergeDiff, newDiff))
                }
            }
        }

        guard let mergeDiff else {
            // Initial commit in a repository
            return try self.diff(from: nil, to: commit.oid)
        }

        return Diff(mergeDiff)
    }

    private func withUnsafeDiff<T>(
        from oldCommitOid: OID?,
        to newCommitOid: OID?,
        transform: (OpaquePointer) throws -> T
    ) throws -> T {
        guard !(oldCommitOid == nil && newCommitOid == nil) else {
            assertionFailure("It is an error to pass nil for both the oldOid and newOid")
            throw GitError(code: .invalid, detail: .internal, description: "Need at least one OID to calculate diff.")
        }

        func withUnsafeTreeIfAvailable(forCommitOid oid: OID?, transform: (OpaquePointer?) throws -> T) throws -> T {
            if let oid {
                return try withUnsafeTree(forCommitOid: oid) { try transform($0) }
            } else {
                return try transform(nil)
            }
        }

        return try withUnsafeTreeIfAvailable(forCommitOid: oldCommitOid) { oldTree in
            try withUnsafeTreeIfAvailable(forCommitOid: newCommitOid) { newTree in
                var diff: OpaquePointer? = nil
                try calling(git_diff_tree_to_tree(
                    &diff,
                    self.pointer,
                    oldTree,
                    newTree,
                    nil
                ))
                return try transform(diff!)
            }
        }
    }

    private func diff(from oldCommitOid: OID?, to newCommitOid: OID?) throws -> Diff {
        try withUnsafeDiff(from: oldCommitOid, to: newCommitOid) { Diff($0) }
    }

    private func processDiffDeltas(_ diffResult: OpaquePointer) throws -> [Diff.Delta] {
        let count = git_diff_num_deltas(diffResult)

        return (0..<count).map {
            let delta = git_diff_get_delta(diffResult, $0)
            return Diff.Delta(delta!.pointee)
        }
    }

    private func safeTreeForCommitId(_ oid: OID) throws -> Tree {
        return try withGitObject(oid, type: .commit) { commit in
            let treeId = git_commit_tree_id(commit)
            return try tree(OID(treeId!.pointee))
        }
    }

    /// Caller responsible to free returned tree with git_object_free
    private func withUnsafeTree<T>(forCommitOid oid: OID, transform: (OpaquePointer) throws -> T) throws -> T {
        var commit: OpaquePointer? = nil
        var oid = oid.rawValue

        try calling(git_object_lookup(&commit, self.pointer, &oid, GIT_OBJECT_COMMIT))
        defer { git_object_free(commit) }

        var tree: OpaquePointer? = nil
        let treeId = git_commit_tree_id(commit)
        try calling(git_object_lookup(&tree, self.pointer, treeId, GIT_OBJECT_TREE))
        defer { git_object_free(tree) }

        return try transform(tree!)
    }

    // MARK: - Status

    public func status() throws -> [StatusEntry] {
        var returnArray = [StatusEntry]()

        var options = git_status_options_init_value
        var unsafeStatus: OpaquePointer? = nil

        defer {
            if let unsafeStatus {
                git_status_list_free(unsafeStatus)
            }
        }

        try calling(git_status_list_new(&unsafeStatus, self.pointer, &options))
        guard let unsafeStatus else {
            throw GitError(code: .invalid, detail: .internal, description: "Could not fetch status result")
        }

        let count = git_status_list_entrycount(unsafeStatus)
        for i in 0..<count {
            let s = git_status_byindex(unsafeStatus, i)
            if s?.pointee.status.rawValue == GIT_STATUS_CURRENT.rawValue {
                continue
            }

            let statusEntry = StatusEntry(from: s!.pointee)
            returnArray.append(statusEntry)
        }

        return returnArray
    }

    // MARK: - Default signature

    public func defaultSignature() throws -> Signature {
        var signature: UnsafeMutablePointer<git_signature>?
        try calling(git_signature_default(&signature, pointer))
        defer { signature?.deallocate() }
        return Signature(signature!.pointee)
    }

    // MARK: - Validity/Existence Check

    /// - returns: `.success(true)` iff there is a git repository at `url`,
    ///   `.success(false)` if there isn't,
    ///   and a `.failure` if there's been an error.
    public static func isValid(url: URL) throws -> Bool {
        var pointer: OpaquePointer?

        let result = url.withUnsafeFileSystemRepresentation {
            git_repository_open_ext(&pointer, $0, GIT_REPOSITORY_OPEN_NO_SEARCH.rawValue, nil)
        }

        let code = GitError.Code(int32Value: result)
        switch code {
        case .ok:
            return true
        case .notFound:
            return false
        default:
            throw GitError.lastError(with: code)
        }
    }
}
