//
//  struct.swift
//  btcswift
//
//  Created by Antti Salonen on 09/03/2021.
//

import Foundation

struct MineParameters {
    let extranonce1: String
    let extranonce2_size: Int
    let diff: UInt64
    let prevhash: String
    let coinb1: String
    let coinb2: String
    let merkle_branches: [String]
    let version: String
    let nbits: String
    let ntime: String
}

struct MiningContext {
    let jobid: String
    let mineparams: MineParameters
}

struct Stratum {
    let inputStream: InputStream
    let outputStream: OutputStream
    let worker_name: String
    let password: String
}
