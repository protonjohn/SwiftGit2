//
//  Transport.swift
//
//  Created by John Biggs on 10.01.24.
//

import Foundation
import Clibgit2

/// Private index of registered transports
fileprivate var transports: [Int: (Transport.Type, UnsafeMutablePointer<git_smart_subtransport_definition>)] = [:]

extension UnsafeMutablePointer {
    fileprivate func withMemoryRebound<T, Result>(
        to type: T.Type,
        offset: KeyPath<T, Pointee>,
        _ body: (_ pointer: UnsafeMutablePointer<T>) throws -> Result) rethrows -> Result {
            guard let offset = MemoryLayout<T>.offset(of: offset), offset > 0 else {
                return try withMemoryRebound(to: type, capacity: 1, body)
            }
            return try UnsafeMutableRawPointer(self)
                .advanced(by: -offset)
                .withMemoryRebound(to: T.self, capacity: 1, body)
        }
}

open class Transport {
    class var isStateless: Bool {
        return false
    }

    public enum Action: RawRepresentable {
        case uploadPack
        case receivePack
        case uploadPackLs
        case receivePackLs

        public var rawValue: git_smart_service_t {
            switch self {
            case .uploadPack:
                return GIT_SERVICE_UPLOADPACK
            case .uploadPackLs:
                return GIT_SERVICE_UPLOADPACK_LS
            case .receivePack:
                return GIT_SERVICE_RECEIVEPACK
            case .receivePackLs:
                return GIT_SERVICE_RECEIVEPACK_LS
            }
        }

        public init?(rawValue: git_smart_service_t) {
            switch rawValue {
            case GIT_SERVICE_UPLOADPACK:
                self = .uploadPack
            case GIT_SERVICE_UPLOADPACK_LS:
                self = .uploadPackLs
            case GIT_SERVICE_RECEIVEPACK:
                self = .receivePack
            case GIT_SERVICE_RECEIVEPACK_LS:
                self = .receivePackLs
            default:
                return nil
            }
        }
    }

    open class Stream {
        let stream: UnsafeMutablePointer<git_smart_subtransport_stream_swift>

        init(stream: UnsafeMutablePointer<git_smart_subtransport_stream_swift>) {
            self.stream = stream
        }

        public init(transport: Transport) {
            self.stream = .allocate(capacity: 1)
            stream.pointee = .init()
            stream.pointee.context = Unmanaged<Stream>.passRetained(self).toOpaque()
            withUnsafeMutablePointer(to: &transport.transport.pointee.parent) {
                stream.pointee.parent.subtransport = $0
            }
            Self.setup(stream)
        }

        private static func setup(_ stream: UnsafeMutablePointer<git_smart_subtransport_stream_swift>) {
            stream.pointee.parent.read = { stream, buffer, size, countPtr in
                guard let stream else { return 1 }

                return stream.withMemoryRebound(to: git_smart_subtransport_stream_swift.self, offset: \.parent) { stream in
                    let `self` = Unmanaged<Stream>.fromOpaque(stream.pointee.context).takeUnretainedValue()

                    let result = self.read(length: size)
                    switch result {
                    case .success(let data):
                        countPtr?.pointee = data.count
                        _ = data.withUnsafeBytes { dataPtr in
                            memcpy(buffer, dataPtr.baseAddress, data.count)
                        }
                        return GitError.Code.ok.int32Value
                    case .failure(let error):
                        return error.code.int32Value
                    }
                }
            }

            stream.pointee.parent.write = { stream, buffer, count in
                guard let buffer, let stream else {
                    return 1
                }

                return stream.withMemoryRebound(to: git_smart_subtransport_stream_swift.self, offset: \.parent) { stream in
                    let `self` = Unmanaged<Stream>.fromOpaque(stream.pointee.context).takeUnretainedValue()
                    let pointer = UnsafeMutableRawPointer(mutating: buffer)
                    let data = Data(bytesNoCopy: pointer, count: count, deallocator: .none)

                    let result = self.write(data: data)
                    switch result {
                    case .success:
                        return GitError.Code.ok.int32Value
                    case .failure(let error):
                        return error.code.int32Value
                    }
                }
            }

            stream.pointee.parent.free = { stream in
                stream?.withMemoryRebound(to: git_smart_subtransport_stream_swift.self, offset: \.parent) { stream in
                    // Consume unbalanced retain
                    _ = Unmanaged<Stream>.fromOpaque(stream.pointee.context).takeRetainedValue()
                }
            }
        }

        open func read(length: Int) -> Result<Data, GitError> {
            return .success(Data())
        }

        open func write(data: Data) -> Result<(), GitError> {
            return .success(())
        }

        deinit {
            stream.deallocate()
        }
    }

    let transport: UnsafeMutablePointer<git_smart_subtransport_swift>

    public var stream: Stream?
    public var lastAction: Action?

    public required init() {
        self.transport = .allocate(capacity: 1)
        transport.initialize(to: .init())
        transport.pointee.context = Unmanaged<Transport>.passRetained(self).toOpaque()

        Self.setup(transport)
    }

    private static func setup(_ transport: UnsafeMutablePointer<git_smart_subtransport_swift>) {
        transport.pointee.parent.action = { out, transport, urlCString, rawAction in
            guard let action = Action(rawValue: rawAction),
                  let out,
                  let transport,
                  let urlCString else {
                return GitError.Code.error.int32Value
            }

            return transport.withMemoryRebound(to: git_smart_subtransport_swift.self, offset: \.parent) { transport in
                let `self` = Unmanaged<Transport>.fromOpaque(transport.pointee.context).takeUnretainedValue()

                defer {
                    if let stream = self.stream {
                        if let pointer = out.pointee, pointer == stream.stream {} else {
                            withUnsafeMutablePointer(to: &stream.stream.pointee.parent) {
                                out.pointee = $0
                            }
                        }
                    }
                    self.lastAction = action
                }

                let urlString = String(cString: urlCString)
                let result = self.action(action, urlString: urlString)
                switch result {
                case .success:
                    return GitError.Code.ok.int32Value
                case .failure(let error):
                    return error.code.int32Value
                }
            }
        }

        transport.pointee.parent.close = { transport in
            guard let transport else {
                return GitError.Code.error.int32Value
            }

            return transport.withMemoryRebound(to: git_smart_subtransport_swift.self, offset: \.parent) { transport in
                let `self` = Unmanaged<Transport>.fromOpaque(transport.pointee.context).takeUnretainedValue()

                let result = self.close()
                switch result {
                case .success:
                    return GitError.Code.ok.int32Value
                case .failure(let error):
                    return error.code.int32Value
                }
            }
        }

        transport.pointee.parent.free = { transport in
            guard let transport else {
                return
            }

            transport.withMemoryRebound(to: git_smart_subtransport_swift.self, offset: \.parent) { transport in
                _ = Unmanaged<Transport>.fromOpaque(transport.pointee.context).takeRetainedValue()
            }
        }
    }

    open func action(_ action: Action, urlString: String) -> Result<(), GitError> {
        switch action {
        case .uploadPackLs, .receivePackLs:
            guard stream == nil, lastAction == nil else {
                return .failure(.init(
                    code: .invalid,
                    detail: .net,
                    description: "Invalid connection state: stream already initialized"
                ))
            }

            return connect(urlString, action: action).map { newStream in
                stream = newStream
            }

        case .uploadPack, .receivePack:
            let expected: Action = action == .uploadPack ? .uploadPackLs : .receivePackLs

            guard lastAction == expected else {
                return .failure(.init(
                    code: .invalid,
                    detail: .net,
                    description: "Invalid connection state"
                ))
            }

            return .success(()) // If it's a simple tunnel, we shouldn't need to do anything to reset the connection
        }
    }

    open func connect(_ urlString: String, action: Action) -> Result<Stream, GitError> {
        .success(Stream(transport: self))
    }

    open func close() -> Result<(), GitError> {
        return .success(())
    }

    deinit {
        transport.deallocate()
    }

    /// Register a new transport with libgit2 using a `git_smart_transport_subdefinition` callback struct.
    ///
    /// This lets libgit2 do most of the heavy lifting while letting us focus on the pipe itself.
    public static func register<T: Transport>(_ transport: T.Type, for scheme: String) throws {
        let pointer: UnsafeMutablePointer<git_smart_subtransport_definition> = .allocate(capacity: 1)
        transports[scheme.hashValue] = (T.self, pointer)

        pointer.pointee.callback = { out, transport, param in
            guard let out, let transport, let param else { return -1 }
            guard let (type, _) = transports[Int(bitPattern: param)] else { return -1 }

            let subtransport = type.init()
            subtransport.transport.pointee.owner = transport
            withUnsafeMutablePointer(to: &subtransport.transport.pointee.parent) {
                out.pointee = $0
            }

            return 0
        }
        pointer.pointee.param = .init(bitPattern: scheme.hashValue)
        pointer.pointee.rpc = transport.isStateless ? 1 : 0

        do {
            try calling(git_transport_register(
                scheme,
                git_transport_smart,
                pointer /* git_transport_smart expects a git_smart_subtransport_definition pointer as its context */
            ))
        } catch {
            pointer.deallocate()
            throw error
        }
    }

    public static func unregister(scheme: String) throws {
        try calling(git_transport_unregister(scheme))
        transports.removeValue(forKey: scheme.hashValue)
    }
}
