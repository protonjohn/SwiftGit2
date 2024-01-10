//
//  Remotes.swift
//  SwiftGit2
//
//  Created by Matt Diephouse on 1/2/15.
//  Copyright (c) 2015 GitHub, Inc. All rights reserved.
//

import Clibgit2
import Foundation

func unsafeClassDereference<T: AnyObject>(_ type: T.Type, consumeRetain: Bool = false, _ pointer: UnsafeRawPointer) -> T {
    let unmanaged = Unmanaged<T>.fromOpaque(pointer)
    return consumeRetain ? unmanaged.takeRetainedValue() : unmanaged.takeUnretainedValue()
}

func wrapCallback(_ detail: GitError.Detail = .net, _ closure: (() throws -> ()), caller: StaticString = #function, file: StaticString = #file, line: Int = #line) -> Int32 {
    do {
        try closure()
        return 0
    } catch let error as GitError {
        git_error_set_str(detail.int32Value, "In \(file):\(line) (\(caller))")
        return error.code.int32Value
    } catch {
        return GitError.Code.error.int32Value
    }
}

public typealias PackerProgressCallback = (PackBuilderStage, /* current */ Int, /* total */ Int) throws -> ()
public typealias TransferProgressCallback = (TransferProgress) throws -> ()
public typealias RemoteProgressCallback = (String) throws -> ()
public typealias CredentialsCallback = () throws -> Credentials?
public typealias RemoteReferenceUpdateCallback = (/* refname */ String, /* status */ String?) throws -> ()
public typealias TipUpdateCallback = (/* refname */ String, /* oldOid */ OID, /* newOid */ OID) throws -> ()
public typealias RemoteReadyCallback = (Remote, Remote.Direction) throws -> ()
public typealias CheckoutProgressCallback = (
    String, /* path */
    Int, /* completedSteps */
    Int /* totalSteps */
) throws -> ()
public typealias PushNegotiationCallback = ([Remote.Update]) throws -> ()

public struct TransferProgress {
    public let totalObjects: Int
    public let indexedObjects: Int
    public let receivedObjects: Int
    public let localObjects: Int

    public let totalDeltas: Int
    public let indexedDeltas: Int

    public let receivedBytes: Int
}

public enum PackBuilderStage: RawRepresentable {
    case addingObjects
    case deltafication

    public var rawValue: git_packbuilder_stage_t {
        switch self {
        case .addingObjects:
            return GIT_PACKBUILDER_ADDING_OBJECTS
        case .deltafication:
            return GIT_PACKBUILDER_DELTAFICATION
        }
    }

    public init?(rawValue: git_packbuilder_stage_t) {
        switch rawValue {
        case GIT_PACKBUILDER_ADDING_OBJECTS:
            self = .addingObjects
        case GIT_PACKBUILDER_DELTAFICATION:
            self = .deltafication
        default:
            return nil
        }
    }

    public init?(int32Value: Int32) {
        self.init(rawValue: .init(UInt32(int32Value)))
    }
}

extension TransferProgress {
    init(_ progress: git_indexer_progress) {
        self.init(
            totalObjects: Int(progress.total_objects),
            indexedObjects: Int(progress.indexed_objects),
            receivedObjects: Int(progress.received_objects),
            localObjects: Int(progress.local_objects),
            totalDeltas: Int(progress.total_deltas),
            indexedDeltas: Int(progress.indexed_deltas),
            receivedBytes: Int(progress.received_bytes)
        )
    }
}


public protocol GitOptionsStruct {
    init()

    static var initializer: ((UnsafeMutablePointer<Self>?, /* version */ UInt32) -> Int32) { get }
    static var version: Int32 { get }
}

extension GitOptionsStruct {
    static var `default`: Self {
        get throws {
            var value = Self()
            try calling(initializer(&value, UInt32(version)))
            return value
        }
    }
}

extension git_push_options: GitOptionsStruct {
    public static let initializer = git_push_init_options
    public static let version = GIT_PUSH_OPTIONS_VERSION
}

extension git_checkout_options: GitOptionsStruct {
    public static let initializer = git_checkout_init_options
    public static let version = GIT_CHECKOUT_OPTIONS_VERSION
}

extension git_fetch_options: GitOptionsStruct {
    public static let initializer = git_fetch_init_options
    public static let version = GIT_FETCH_OPTIONS_VERSION
}

extension git_clone_options: GitOptionsStruct {
    public static let initializer = git_clone_init_options
    public static let version = GIT_CLONE_OPTIONS_VERSION
}

open class GitCallbackOptions<O: GitOptionsStruct> {
    var options: O

    public init() throws {
        self.options = try O.default
    }
}

open class CheckoutOptions: GitCallbackOptions<git_checkout_options> {
    /// A progress callback invoked with the path, the total number of completed steps, and the total number of steps.
    public var progressCallback: CheckoutProgressCallback?

    public init(strategy: CheckoutStrategy = .safe) throws {
        try super.init()

        options.checkout_strategy = strategy.rawValue
        options.progress_payload = Unmanaged<CheckoutOptions>.passUnretained(self).toOpaque()
        options.progress_cb = { path, completedSteps, totalSteps, payload in
            guard let path, let payload else { return }

            let `self` = unsafeClassDereference(CheckoutOptions.self, payload)
            try? self.progressCallback?(
                String(cString: path),
                completedSteps,
                totalSteps
            )
        }
    }
}

open class FetchOptions: GitCallbackOptions<git_fetch_options> {
    public var credentialsCallback: CredentialsCallback?
    public var remoteProgressCallback: RemoteProgressCallback?
    public var packerCallback: PackerProgressCallback?
    public var transferProgressCallback: TransferProgressCallback?
    public var updateTipsCallback: TipUpdateCallback?
    public var referenceUpdateCallback: RemoteReferenceUpdateCallback?
    public var remoteReadyCallback: RemoteReadyCallback?
    public var pushNegotiationCallback: PushNegotiationCallback?

    public override init() throws {
        try super.init()

        options.callbacks.payload = Unmanaged<FetchOptions>.passUnretained(self).toOpaque()

        options.callbacks.credentials = { cred, _, usernamePointer, _, payload in
            guard let payload else { return -1 }
            let `self` = unsafeClassDereference(FetchOptions.self, payload)

            guard let credentialsCallback = self.credentialsCallback else {
                return GitError.Code.passthrough.int32Value
            }

            guard let usernamePointer else { return -1 }

            return wrapCallback {
                cred?.pointee = try credentialsCallback()?
                    .makeUnsafeCredential(username: String(cString: usernamePointer))
            }
        }

        options.callbacks.transfer_progress = { progressPointer, payload in
            guard let progressPointer, let payload else { return -1 }
            let `self` = unsafeClassDereference(FetchOptions.self, payload)

            let progress = TransferProgress(progressPointer.pointee)

            return wrapCallback {
                try self.transferProgressCallback?(progress)
            }
        }

        options.callbacks.pack_progress = { stage, current, total, payload in
            guard let payload, let stage = PackBuilderStage(int32Value: stage) else { return -1 }
            let `self` = unsafeClassDereference(FetchOptions.self, payload)

            return wrapCallback {
                try self.packerCallback?(stage, Int(current), Int(total))
            }
        }

        options.callbacks.sideband_progress = { stringPointer, length, payload in
            guard let payload else { return -1 }
            let `self` = unsafeClassDereference(FetchOptions.self, payload)

            guard let callback = self.remoteProgressCallback else {
                return GitError.Code.passthrough.int32Value
            }

            guard let stringPointer else { return 0 }

            let data = Data(
                bytesNoCopy: UnsafeMutableRawPointer(mutating: stringPointer),
                count: Int(length),
                deallocator: .none
            )

            guard let string = String(data: data, encoding: .utf8) else {
                return -1
            }

            return wrapCallback { try callback(string) }
        }

        options.callbacks.push_update_reference = { refname, status, payload in
            guard let payload, let refname else { return -1 }
            let `self` = unsafeClassDereference(FetchOptions.self, payload)

            let reference = String(cString: refname)
            var message: String?
            if let status {
                message = String(cString: status)
            }

            return wrapCallback {
                try self.referenceUpdateCallback?(reference, message)
            }
        }

        options.callbacks.update_tips = { refname, oldOid, newOid, payload in
            guard let payload, let refname, let oldOid, let newOid else { return -1 }
            let `self` = unsafeClassDereference(FetchOptions.self, payload)

            let reference = String(cString: refname)
            return wrapCallback {
                try self.updateTipsCallback?(
                    reference,
                    OID(rawValue: oldOid.pointee),
                    OID(rawValue: newOid.pointee)
                )
            }
        }

        options.callbacks.remote_ready = { remote, direction, payload in
            guard let remotePointer = remote,
                  let direction = Remote.Direction(int32Value: direction),
                  let payload else { return -1 }
            let `self` = unsafeClassDereference(FetchOptions.self, payload)

            return wrapCallback {
                try self.remoteReadyCallback?(Remote(remotePointer), direction)
            }
        }

        options.callbacks.push_negotiation = { updatesPointer, count, payload in
            guard let payload else { return -1 }
            let `self` = unsafeClassDereference(FetchOptions.self, payload)
            let updatesPointer = UnsafeMutableBufferPointer(start: updatesPointer, count: count)
            let updates: [Remote.Update] = updatesPointer.compactMap { updatePointer in
                guard let updatePointer else { return nil }
                return .init(updatePointer.pointee)
            }

            return wrapCallback {
                try self.pushNegotiationCallback?(updates)
            }
        }
    }
}

open class CloneOptions: GitCallbackOptions<git_clone_options> {
    public let checkoutBranch: String?
    public let fetchOptions: FetchOptions?
    public let checkoutOptions: CheckoutOptions?

    public enum LocalOptions: RawRepresentable {
        case auto
        case local
        case noLocal
        case localNoLinks

        public var rawValue: git_clone_local_t {
            switch self {
            case .auto:
                return GIT_CLONE_LOCAL_AUTO
            case .local:
                return GIT_CLONE_LOCAL
            case .noLocal:
                return GIT_CLONE_NO_LOCAL
            case .localNoLinks:
                return GIT_CLONE_LOCAL_NO_LINKS
            }
        }

        public init?(rawValue: git_clone_local_t) {
            switch rawValue {
            case GIT_CLONE_LOCAL_AUTO:
                self = .auto
            case GIT_CLONE_LOCAL:
                self = .local
            case GIT_CLONE_NO_LOCAL:
                self = .noLocal
            case GIT_CLONE_LOCAL_NO_LINKS:
                self = .localNoLinks
            default:
                return nil
            }
        }
    }

    public init(
        bare: Bool = false,
        checkoutBranch: String? = nil,
        localOptions: LocalOptions = .auto,
        fetchOptions: FetchOptions?,
        checkoutOptions: CheckoutOptions?
    ) throws {
        self.checkoutBranch = checkoutBranch
        self.fetchOptions = fetchOptions
        self.checkoutOptions = checkoutOptions
        try super.init()

        options.bare = bare ? 1 : 0
        options.local = localOptions.rawValue
        self.checkoutBranch?.withCString {
            options.checkout_branch = $0
        }

        if let fetchOptions {
            options.fetch_opts = fetchOptions.options
        }

        if let checkoutOptions {
            options.checkout_opts = checkoutOptions.options
        }
    }
}

open class PushOptions: GitCallbackOptions<git_push_options> {
    public var credentialsCallback: CredentialsCallback?
    public var remoteProgressCallback: RemoteProgressCallback?
    public var packerCallback: PackerProgressCallback?
    public var transferProgressCallback: TransferProgressCallback?
    public var updateTipsCallback: TipUpdateCallback?
    public var referenceUpdateCallback: RemoteReferenceUpdateCallback?
    public var remoteReadyCallback: RemoteReadyCallback?
    public var pushNegotiationCallback: PushNegotiationCallback?

    public static func setup(options: inout git_push_options) {
        options.callbacks.sideband_progress = { stringPointer, length, payload in
            guard let payload else { return -1 }
            let `self` = unsafeClassDereference(PushOptions.self, payload)

            guard let callback = self.remoteProgressCallback else {
                return GitError.Code.passthrough.int32Value
            }

            guard let stringPointer else { return 0 }

            let data = Data(
                bytesNoCopy: UnsafeMutableRawPointer(mutating: stringPointer),
                count: Int(length),
                deallocator: .none
            )

            guard let string = String(data: data, encoding: .utf8) else {
                return -1
            }

            return wrapCallback { try callback(string) }
        }

        options.callbacks.credentials = { cred, _, usernamePointer, _, payload in
            guard let payload else { return -1 }
            let `self` = unsafeClassDereference(PushOptions.self, payload)

            guard let callback = self.credentialsCallback else {
                return GitError.Code.passthrough.int32Value
            }

            guard let usernamePointer else { return -1 }

            return wrapCallback {
                cred?.pointee = try callback()?
                    .makeUnsafeCredential(username: String(cString: usernamePointer))
            }
        }

        options.callbacks.transfer_progress = { progressPointer, payload in
            guard let progressPointer, let payload else { return -1 }

            let `self` = unsafeClassDereference(PushOptions.self, payload)
            let progress = TransferProgress(progressPointer.pointee)
            return wrapCallback { try self.transferProgressCallback?(progress) }
        }

        options.callbacks.pack_progress = { stage, current, total, payload in
            guard let payload, let stage = PackBuilderStage(int32Value: stage) else { return -1 }
            let `self` = unsafeClassDereference(PushOptions.self, payload)

            return wrapCallback {
                try self.packerCallback?(stage, Int(current), Int(total))
            }
        }

        options.callbacks.push_update_reference = { refname, status, payload in
            guard let payload, let refname else { return -1 }
            let `self` = unsafeClassDereference(PushOptions.self, payload)

            let reference = String(cString: refname)
            var message: String?
            if let status {
                message = String(cString: status)
            }

            return wrapCallback {
                try self.referenceUpdateCallback?(reference, message)
            }
        }

        options.callbacks.update_tips = { refname, oldOid, newOid, payload in
            guard let payload, let refname, let oldOid, let newOid else { return -1 }
            let `self` = unsafeClassDereference(PushOptions.self, payload)

            let reference = String(cString: refname)
            return wrapCallback {
                try self.updateTipsCallback?(
                    reference,
                    OID(rawValue: oldOid.pointee),
                    OID(rawValue: newOid.pointee)
                )
            }
        }

        options.callbacks.remote_ready = { remote, direction, payload in
            guard let remotePointer = remote,
                  let direction = Remote.Direction(int32Value: direction),
                  let payload else { return -1 }
            let `self` = unsafeClassDereference(PushOptions.self, payload)

            return wrapCallback {
                try self.remoteReadyCallback?(Remote(remotePointer), direction)
            }
        }

        options.callbacks.push_negotiation = { updatesPointer, count, payload in
            guard let payload else { return -1 }
            let `self` = unsafeClassDereference(PushOptions.self, payload)
            let updatesPointer = UnsafeMutableBufferPointer(start: updatesPointer, count: count)
            let updates: [Remote.Update] = updatesPointer.compactMap { updatePointer in
                guard let updatePointer else { return nil }
                return .init(updatePointer.pointee)
            }

            return wrapCallback {
                try self.pushNegotiationCallback?(updates)
            }
        }
    }

    public override init() throws {
        try super.init()

        options.callbacks.payload = Unmanaged<PushOptions>.passUnretained(self).toOpaque()

        Self.setup(options: &options)
    }
}

/// A remote in a git repository.
public struct Remote: Hashable {
    /// The name of the remote.
    public let name: String

    /// The URL of the remote.
    ///
    /// This may be an SSH URL, which isn't representable using `NSURL`.
    public let URL: String

    /// Create an instance with a libgit2 `git_remote`.
    public init(_ pointer: OpaquePointer) {
        name = String(validatingUTF8: git_remote_name(pointer))!
        URL = String(validatingUTF8: git_remote_url(pointer))!
    }

    public enum Direction: RawRepresentable {
        case push
        case fetch

        public var rawValue: git_direction {
            switch self {
            case .fetch:
                return GIT_DIRECTION_FETCH
            case .push:
                return GIT_DIRECTION_PUSH
            }
        }

        public init?(rawValue: git_direction) {
            switch rawValue {
            case GIT_DIRECTION_FETCH:
                self = .fetch
            case GIT_DIRECTION_PUSH:
                self = .push
            default:
                return nil
            }
        }

        public init?(int32Value: Int32) {
            guard let value = Self(rawValue: .init(UInt32(int32Value))) else {
                return nil
            }
            self = value
        }
    }

    public struct Update {
        /// The source reference name
        public let source: String
        /// The destination reference name
        public let destination: String
        /// The current target of the reference
        public let currentTarget: OID
        /// The new target for the reference
        public let newTarget: OID
    }
}

extension Remote.Update {
    init(_ update: git_push_update) {
        self.init(
            source: String(cString: update.src_refname),
            destination: String(cString: update.dst_refname),
            currentTarget: OID(rawValue: update.src),
            newTarget: OID(rawValue: update.dst)
        )
    }
}
