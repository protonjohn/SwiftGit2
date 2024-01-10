import Foundation
import Clibgit2

/// Attempt to call a libgit2 function, and throw an error if it returns an error code other than GIT_OK.
@discardableResult
func calling(
    _ function: @autoclosure () -> Int32,
    caller: StaticString = #function,
    file: StaticString = #file,
    line: Int = #line
) throws -> Int32 {
    let returnValue = function()

    guard returnValue >= GitError.Code.ok.int32Value else {
        let result = GitError.Code(int32Value: function())
        throw GitError.lastError(with: result, caller: caller, file: file, line: line)
    }

    return returnValue
}

public struct GitError: CustomNSError, CustomStringConvertible {
    public static var errorDomain: String = "org.libgit2.libgit2"

    public enum Code: RawRepresentable {
        case ok
        case error
        case notFound
        case exists
        case ambiguous
        case buffer
        case user
        case bareRepo
        case unbornBranch
        case unmerged
        case nonFastForward
        case invalidSpec
        case conflict
        case locked
        case modified
        case auth
        case certificate
        case applied
        case peel
        case eof
        case invalid
        case uncommitted
        case directory
        case mergeConflict
        case passthrough
        case endIteration
        case retry
        case mismatch
        case indexDirty
        case applyFail
        case owner
        case timeout

        public var rawValue: git_error_code {
            switch self {
            case .ok:
                return GIT_OK
            case .error:
                return GIT_ERROR
            case .notFound:
                return GIT_ENOTFOUND
            case .exists:
                return GIT_EEXISTS
            case .ambiguous:
                return GIT_EAMBIGUOUS
            case .buffer:
                return GIT_EBUFS
            case .user:
                return GIT_EUSER
            case .bareRepo:
                return GIT_EBAREREPO
            case .unbornBranch:
                return GIT_EUNBORNBRANCH
            case .unmerged:
                return GIT_EUNMERGED
            case .nonFastForward:
                return GIT_ENONFASTFORWARD
            case .invalidSpec:
                return GIT_EINVALIDSPEC
            case .conflict:
                return GIT_ECONFLICT
            case .locked:
                return GIT_ELOCKED
            case .modified:
                return GIT_EMODIFIED
            case .auth:
                return GIT_EAUTH
            case .certificate:
                return GIT_ECERTIFICATE
            case .applied:
                return GIT_EAPPLIED
            case .peel:
                return GIT_EPEEL
            case .eof:
                return GIT_EEOF
            case .invalid:
                return GIT_EINVALID
            case .uncommitted:
                return GIT_EUNCOMMITTED
            case .directory:
                return GIT_EDIRECTORY
            case .mergeConflict:
                return GIT_EMERGECONFLICT
            case .passthrough:
               return GIT_PASSTHROUGH
            case .endIteration:
                return GIT_ITEROVER
            case .retry:
                return GIT_RETRY
            case .mismatch:
                return GIT_EMISMATCH
            case .indexDirty:
                return GIT_EINDEXDIRTY
            case .applyFail:
                return GIT_EAPPLYFAIL
            case .owner:
                return GIT_EOWNER
            case .timeout:
                return GIT_TIMEOUT
            }
        }

        public var int32Value: Int32 {
            rawValue.rawValue
        }

        public init(rawValue: git_error_code) {
            switch rawValue {
            case GIT_OK:
                self = .ok
            case GIT_ENOTFOUND:
                self = .notFound
            case GIT_EEXISTS:
                self = .exists
            case GIT_EAMBIGUOUS:
                self = .ambiguous
            case GIT_EBUFS:
                self = .buffer
            case GIT_EUSER:
                self = .user
            case GIT_EBAREREPO:
                self = .bareRepo
            case GIT_EUNBORNBRANCH:
                self = .unbornBranch
            case GIT_EUNMERGED:
                self = .unmerged
            case GIT_ENONFASTFORWARD:
                self = .nonFastForward
            case GIT_EINVALIDSPEC:
                self = .invalidSpec
            case GIT_ECONFLICT:
                self = .conflict
            case GIT_ELOCKED:
                self = .locked
            case GIT_EMODIFIED:
                self = .modified
            case GIT_EAUTH:
                self = .auth
            case GIT_ECERTIFICATE:
                self = .certificate
            case GIT_EAPPLIED:
                self = .applied
            case GIT_EPEEL:
                self = .peel
            case GIT_EEOF:
                self = .eof
            case GIT_EINVALID:
                self = .invalid
            case GIT_EUNCOMMITTED:
                self = .uncommitted
            case GIT_EDIRECTORY:
                self = .directory
            case GIT_EMERGECONFLICT:
                self = .mergeConflict
            case GIT_PASSTHROUGH:
                self = .passthrough
            case GIT_ITEROVER:
                self = .endIteration
            case GIT_RETRY:
                self = .retry
            case GIT_EMISMATCH:
                self = .mismatch
            case GIT_EINDEXDIRTY:
                self = .indexDirty
            case GIT_EAPPLYFAIL:
                self = .applyFail
            case GIT_EOWNER:
                self = .owner
            case GIT_TIMEOUT:
                self = .timeout
            case GIT_ERROR:
                fallthrough
            default:
                self = .error
            }
        }

        public init(int32Value: Int32) {
            self = .init(rawValue: .init(int32Value))
        }
    }

    public enum Detail: RawRepresentable {
        case none
        case noMemory
        case operatingSystem
        case invalid
        case reference
        case zlib
        case repository
        case config
        case regex
        case objectDb
        case index
        case object
        case net
        case tag
        case tree
        case indexer
        case ssl
        case submodule
        case thread
        case stash
        case checkout
        case fetchHead
        case merge
        case ssh
        case filter
        case revert
        case callback
        case cherryPick
        case describe
        case rebase
        case fileSystem
        case patch
        case worktree
        case sha
        case http
        case `internal`
        case grafts

        public var rawValue: git_error_t {
            switch self {
            case .none:
                return GIT_ERROR_NONE
            case .noMemory:
                return GIT_ERROR_NOMEMORY
            case .operatingSystem:
                return GIT_ERROR_OS
            case .invalid:
                return GIT_ERROR_INVALID
            case .reference:
                return GIT_ERROR_REFERENCE
            case .zlib:
                return GIT_ERROR_ZLIB
            case .repository:
                return GIT_ERROR_REPOSITORY
            case .config:
                return GIT_ERROR_CONFIG
            case .regex:
                return GIT_ERROR_REGEX
            case .objectDb:
                return GIT_ERROR_ODB
            case .index:
                return GIT_ERROR_INDEX
            case .object:
                return GIT_ERROR_OBJECT
            case .net:
                return GIT_ERROR_NET
            case .tag:
                return GIT_ERROR_TAG
            case .tree:
                return GIT_ERROR_TREE
            case .indexer:
                return GIT_ERROR_INDEXER
            case .ssl:
                return GIT_ERROR_SSL
            case .submodule:
                return GIT_ERROR_SUBMODULE
            case .thread:
                return GIT_ERROR_THREAD
            case .stash:
                return GIT_ERROR_STASH
            case .checkout:
                return GIT_ERROR_CHECKOUT
            case .fetchHead:
                return GIT_ERROR_FETCHHEAD
            case .merge:
                return GIT_ERROR_MERGE
            case .ssh:
                return GIT_ERROR_SSH
            case .filter:
                return GIT_ERROR_FILTER
            case .revert:
                return GIT_ERROR_REVERT
            case .callback:
                return GIT_ERROR_CALLBACK
            case .cherryPick:
                return GIT_ERROR_CHERRYPICK
            case .describe:
                return GIT_ERROR_DESCRIBE
            case .rebase:
                return GIT_ERROR_REBASE
            case .fileSystem:
                return GIT_ERROR_FILESYSTEM
            case .patch:
                return GIT_ERROR_PATCH
            case .worktree:
                return GIT_ERROR_WORKTREE
            case .sha:
                return GIT_ERROR_SHA
            case .http:
                return GIT_ERROR_HTTP
            case .`internal`:
                return GIT_ERROR_INTERNAL
            case .grafts:
                return GIT_ERROR_GRAFTS
            }
        }

        public var int32Value: Int32 {
            Int32(rawValue.rawValue)
        }

        public init(rawValue: git_error_t) {
            switch rawValue {
            case GIT_ERROR_NOMEMORY:
                self = .noMemory
            case GIT_ERROR_OS:
                self = .operatingSystem
            case GIT_ERROR_INVALID:
                self = .invalid
            case GIT_ERROR_REFERENCE:
                self = .reference
            case GIT_ERROR_ZLIB:
                self = .zlib
            case GIT_ERROR_REPOSITORY:
                self = .repository
            case GIT_ERROR_CONFIG:
                self = .config
            case GIT_ERROR_REGEX:
                self = .regex
            case GIT_ERROR_ODB:
                self = .objectDb
            case GIT_ERROR_INDEX:
                self = .index
            case GIT_ERROR_OBJECT:
                self = .object
            case GIT_ERROR_NET:
                self = .net
            case GIT_ERROR_TAG:
                self = .tag
            case GIT_ERROR_TREE:
                self = .tree
            case GIT_ERROR_INDEXER:
                self = .indexer
            case GIT_ERROR_SSL:
                self = .ssl
            case GIT_ERROR_SUBMODULE:
                self = .submodule
            case GIT_ERROR_THREAD:
                self = .thread
            case GIT_ERROR_STASH:
                self = .stash
            case GIT_ERROR_CHECKOUT:
                self = .checkout
            case GIT_ERROR_FETCHHEAD:
                self = .fetchHead
            case GIT_ERROR_MERGE:
                self = .merge
            case GIT_ERROR_SSH:
                self = .ssh
            case GIT_ERROR_FILTER:
                self = .filter
            case GIT_ERROR_REVERT:
                self = .revert
            case GIT_ERROR_CALLBACK:
                self = .callback
            case GIT_ERROR_CHERRYPICK:
                self = .cherryPick
            case GIT_ERROR_DESCRIBE:
                self = .describe
            case GIT_ERROR_REBASE:
                self = .rebase
            case GIT_ERROR_FILESYSTEM:
                self = .fileSystem
            case GIT_ERROR_PATCH:
                self = .patch
            case GIT_ERROR_WORKTREE:
                self = .worktree
            case GIT_ERROR_SHA:
                self = .sha
            case GIT_ERROR_HTTP:
                self = .http
            case GIT_ERROR_INTERNAL:
                self = .`internal`
            case GIT_ERROR_GRAFTS:
                self = .grafts
            case GIT_ERROR_NONE:
                fallthrough
            default:
                self = .none
            }
        }

        public init(int32Value: Int32) {
            self = .init(rawValue: .init(UInt32(int32Value)))
        }
    }

    public let code: Code
    public let detail: Detail
    public let description: String
    public let errorUserInfo: [String: Any]

    public var errorCode: Int {
        Int(code.int32Value)
    }

    public init(
        code: Code,
        detail: Detail,
        description: String,
        userInfo: [String: Any] = [:],
        caller: StaticString = #function,
        file: StaticString = #file,
        line: Int = #line
    ) {
        var userInfo = userInfo
        if userInfo[NSDebugDescriptionErrorKey] == nil {
            userInfo[NSDebugDescriptionErrorKey] = "In \(file):\(line) (\(caller))"
        }

        self.code = code
        self.detail = detail
        self.description = description
        self.errorUserInfo = userInfo
    }

    public static func lastError(
        with code: Code,
        caller: StaticString = #function,
        file: StaticString = #file,
        line: Int = #line
    ) -> Self {
        let detail: Detail
        var userInfo: [String: Any] = [:]

        let errorString: String
        if let pointer = git_error_last() {
            detail = Detail(int32Value: pointer.pointee.klass)

            if detail == .operatingSystem, let errorCode = POSIXErrorCode(rawValue: errno) {
                userInfo[NSUnderlyingErrorKey] = POSIXError(errorCode)
            }

            errorString = String(cString: pointer.pointee.message)
        } else {
            detail = .none
            errorString = ""
        }

        return Self(
            code: code,
            detail: detail,
            description: errorString,
            userInfo: userInfo,
            caller: caller,
            file: file,
            line: line
        )
    }
}
