//
//  Config.swift
//  
//
//  Created by John Biggs on 08.12.23.
//

import Foundation
import System
import Clibgit2

public final class Config {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        git_config_free(pointer)
    }

    public static func `default`() throws -> Self {
        var pointer: OpaquePointer?
        try calling(git_config_open_default(&pointer))

        guard let pointer else {
            throw GitError(code: .notFound, detail: .none, description: "No value returned for default config")
        }

        return Self(pointer: pointer)
    }

    public var global: Self {
        get throws {
            var pointer: OpaquePointer?

            try calling(git_config_open_global(&pointer, self.pointer))

            guard let pointer else {
                throw GitError(code: .notFound, detail: .none, description: "No value returned for global config")
            }

            return Self(pointer: pointer)
        }
    }

    public func get(_ type: Bool.Type, _ name: String) throws -> Bool {
        var out: Int32 = 0
        try calling(git_config_get_bool(&out, pointer, name))
        return out == 0
    }

    public func get(_ type: Int32.Type, _ name: String) throws -> Int32 {
        var out: Int32 = 0
        try calling(git_config_get_int32(&out, pointer, name))
        return out
    }

    public func get(_ type: Int64.Type, _ name: String) throws -> Int64 {
        var out: Int64 = 0
        try calling(git_config_get_int64(&out, pointer, name))
        return out
    }

    public func get(_ type: String.Type, _ name: String) throws -> String {
        var buf = git_buf()
        try calling(git_config_get_string_buf(&buf, pointer, name))
        defer { git_buf_free(&buf) }

        let data = Data(bytes: buf.ptr, count: strnlen(buf.ptr, buf.size))
        return String(data: data, encoding: .utf8) ?? ""
    }

    public func get(_ type: FilePath.Type, _ name: String) throws -> FilePath {
        var buf = git_buf()
        try calling(git_config_get_string_buf(&buf, pointer, name))
        defer { git_buf_free(&buf) }

        let data = Data(bytes: buf.ptr, count: strnlen(buf.ptr, buf.size))
        let string = String(data: data, encoding: .utf8) ?? ""
        return FilePath(string)
    }

    public func set(_ name: String, value: Bool) throws {
        try calling(git_config_set_bool(pointer, name, value == false ? 0 : 1))
    }

    public func set(_ name: String, value: Int32) throws {
        try calling(git_config_set_int32(pointer, name, value))
    }

    public func set(_ name: String, value: Int64) throws {
        try calling(git_config_set_int64(pointer, name, value))
    }

    public func set(_ name: String, value: String) throws {
        try calling(git_config_set_string(pointer, name, value))
    }
}
