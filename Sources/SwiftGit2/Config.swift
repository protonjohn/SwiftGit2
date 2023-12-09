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
        let result = git_config_open_default(&pointer)
        guard let pointer, result == GIT_OK.rawValue else {
            throw NSError(gitError: result, pointOfFailure: "git_config_open_default")
        }
        return Self(pointer: pointer)
    }

    public var global: Self {
        get throws {
            var pointer: OpaquePointer?

            let result = git_config_open_global(&pointer, self.pointer)
            guard let pointer, result == GIT_OK.rawValue else {
                throw NSError(gitError: result, pointOfFailure: "git_config_open_global")
            }
            return Self(pointer: pointer)
        }
    }

    public func get(_ type: Bool.Type, _ name: String) -> Result<Bool, NSError> {
        var out: Int32 = 0
        let result = git_config_get_bool(&out, pointer, name)
        guard result == GIT_OK.rawValue else {
            return .failure(NSError(gitError: result, pointOfFailure: "git_config_get_bool"))
        }
        return .success(out == 0)
    }

    public func get(_ type: Int32.Type, _ name: String) -> Result<Int32, NSError> {
        var out: Int32 = 0
        let result = git_config_get_int32(&out, pointer, name)
        guard result == GIT_OK.rawValue else {
            return .failure(NSError(gitError: result, pointOfFailure: "git_config_get_int32"))
        }
        return .success(out)
    }

    public func get(_ type: Int64.Type, _ name: String) -> Result<Int64, NSError> {
        var out: Int64 = 0
        let result = git_config_get_int64(&out, pointer, name)
        guard result == GIT_OK.rawValue else {
            return .failure(NSError(gitError: result, pointOfFailure: "git_config_get_int64"))
        }
        return .success(out)
    }

    public func get(_ type: String.Type, _ name: String) -> Result<String, NSError> {
        var buf = git_buf()
        let result = git_config_get_string_buf(&buf, pointer, name)
        guard result == GIT_OK.rawValue else {
            return .failure(NSError(gitError: result, pointOfFailure: "git_config_get_string"))
        }

        defer { git_buf_free(&buf) }
        let data = Data(bytes: buf.ptr, count: strnlen(buf.ptr, buf.size))
        return .success(String(data: data, encoding: .utf8) ?? "")
    }

    public func get(_ type: FilePath.Type, _ name: String) -> Result<FilePath, NSError> {
        var buf = git_buf()
        let result = git_config_get_string_buf(&buf, pointer, name)
        guard result == GIT_OK.rawValue else {
            return .failure(NSError(gitError: result, pointOfFailure: "git_config_get_path"))
        }

        defer { git_buf_free(&buf) }
        let data = Data(bytes: buf.ptr, count: strnlen(buf.ptr, buf.size))
        let string = String(data: data, encoding: .utf8) ?? ""
        return .success(FilePath(string))
    }

    public func set(_ name: String, value: Bool) -> Result<(), NSError> {
        let result = git_config_set_bool(pointer, name, value == false ? 0 : 1)
        guard result == GIT_OK.rawValue else {
            return .failure(NSError(gitError: result, pointOfFailure: "git_config_set_bool"))
        }
        return .success(())
    }

    public func set(_ name: String, value: Int32) -> Result<(), NSError> {
        let result = git_config_set_int32(pointer, name, value)
        guard result == GIT_OK.rawValue else {
            return .failure(NSError(gitError: result, pointOfFailure: "git_config_set_int32"))
        }
        return .success(())
    }

    public func set(_ name: String, value: Int64) -> Result<(), NSError> {
        let result = git_config_set_int64(pointer, name, value)
        guard result == GIT_OK.rawValue else {
            return .failure(NSError(gitError: result, pointOfFailure: "git_config_set_int64"))
        }
        return .success(())
    }

    public func set(_ name: String, value: String) -> Result<(), NSError> {
        let result = git_config_set_string(pointer, name, value)
        guard result == GIT_OK.rawValue else {
            return .failure(NSError(gitError: result, pointOfFailure: "git_config_set_string"))
        }
        return .success(())
    }
}
