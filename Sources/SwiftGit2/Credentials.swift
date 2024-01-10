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

    func makeUnsafeCredential(username: String) throws -> UnsafeMutablePointer<git_cred> {
        var cred: UnsafeMutablePointer<git_cred>?
        let result: Int32

        switch self {
        case .default:
            result = git_credential_default_new(&cred)
        case .sshAgent:
            result = git_credential_ssh_key_from_agent(&cred, username)
        case .plaintext(let username, let password):
            result = git_credential_userpass_plaintext_new(&cred, username, password)
        case .sshMemory(let privateKey, let passphrase):
            result = git_credential_ssh_key_memory_new(&cred, username, nil, privateKey, passphrase)
        case let .sshPath(publicKeyPath, privateKeyPath, passphrase):
            result = git_credential_ssh_key_new(&cred, username, publicKeyPath, privateKeyPath, passphrase)
        }

        let code = GitError.Code(int32Value: result)
        guard code == .ok, let cred else {
            throw GitError.lastError(with: code)
        }

        return cred
    }
}
