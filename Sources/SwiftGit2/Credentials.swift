//
//  Credentials.swift
//  SwiftGit2
//
//  Created by Tom Booth on 29/02/2016.
//  Copyright © 2016 GitHub, Inc. All rights reserved.
//

import Clibgit2

private class Wrapper<T> {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

public enum Credentials {
    /// Note: `default` here refers to a default credential used for Kerberos or NTLM. Make sure the library is linked.
    case `default`
    case sshAgent
    case plaintext(username: String, password: String)
    case sshMemory(privateKey: String, passphrase: String)
    case sshPath(publicKeyPath: String, privateKeyPath: String, passphrase: String)

    private static var previouslyUsedPointer: String? = nil
    private static var previouslyUsedCredentials: Credentials? = nil

    internal static func fromPointer(_ pointer: UnsafeMutableRawPointer) -> Credentials {
        // check if we had just seen this pointer
        if pointer.debugDescription == previouslyUsedPointer {
            // we have already used this pointer, so it is likely that libgit2
            // has already freed the memory and using Unmanaged<>.fromOpaque will
            // result in a BAD_ACCESS crash
            return previouslyUsedCredentials!
        } else {
            // mark that we have used this pointer so that
            // later attempts to use it in this function will
            // be blocked
            previouslyUsedPointer = pointer.debugDescription
            previouslyUsedCredentials = Unmanaged<Wrapper<Credentials>>.fromOpaque(UnsafeRawPointer(pointer)).takeRetainedValue().value
            // access the pointer and convert it into a
            // Credentials Swift object
            return previouslyUsedCredentials!
        }
    }

    internal func toPointer() -> UnsafeMutableRawPointer {
        return Unmanaged.passRetained(Wrapper(self)).toOpaque()
    }
}

/// Handle the request of credentials, passing through to a wrapped block after converting the arguments.
/// Converts the result to the correct error code required by libgit2 (0 = success, 1 = rejected setting creds,
/// -1 = error)
internal func credentialsCallback(
    cred: UnsafeMutablePointer<UnsafeMutablePointer<git_cred>?>?,
    url: UnsafePointer<CChar>?,
    username: UnsafePointer<CChar>?,
    _: UInt32,
    payload: UnsafeMutableRawPointer?
) -> Int32 {
    let result: Int32

    let credential = Credentials.fromPointer(payload!)

    switch credential {
    case .default:
        result = git_credential_default_new(cred)
    case .sshAgent:
        result = git_credential_ssh_key_from_agent(cred, username)
    case .plaintext(let username, let password):
        result = git_credential_userpass_plaintext_new(cred, username, password)
    case .sshMemory(let privateKey, let passphrase):
        result = git_credential_ssh_key_memory_new(cred, username, nil, privateKey, passphrase)
    case let .sshPath(publicKeyPath, privateKeyPath, passphrase):
        result = git_credential_ssh_key_new(cred, username, publicKeyPath, privateKeyPath, passphrase)
    }

    return (result != GIT_OK.rawValue) ? -1 : 0
}
