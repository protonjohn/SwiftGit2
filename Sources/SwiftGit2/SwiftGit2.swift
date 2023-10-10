//
//  SwiftGit2.swift
//  
//
//  Created by John Biggs on 06.10.23.
//

import Foundation
import Clibgit2

public enum SwiftGit2 {
    public static func initialize() {
        _ = git_libgit2_init()
    }
}
