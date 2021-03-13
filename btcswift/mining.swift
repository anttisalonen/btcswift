//
//  mining.swift
//  btcswift
//
//  Created by Antti Salonen on 09/03/2021.
//

import Foundation
import Crypto
import MetalKit

struct MetalContext {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState
    let threadGroupSize: MTLSize
}

func initMetal() -> MetalContext {
    let device = MTLCreateSystemDefaultDevice()!
    let queue = device.makeCommandQueue()!
    let library = device.makeDefaultLibrary()!
    let function = library.makeFunction(name: "sha256_double")!
    let pipelineState = try! device.makeComputePipelineState(function: function)
    let threads = pipelineState.maxTotalThreadsPerThreadgroup
    let thwidth = pipelineState.threadExecutionWidth
    let threadGroupSize = MTLSizeMake(threads, 1, 1)
    print("Number of threads: \(threads)")
    print("Thread width: \(thwidth)")
    return MetalContext(device: device,
                        queue: queue,
                        pipelineState: pipelineState,
                        threadGroupSize: threadGroupSize)
}

enum MineResult {
    case interrupted(UInt32, UInt32)
    case exhausted
    case found(UInt32, UInt32)
}

func readAndMine(ctxt: MetalContext, params: MineParameters, oistream: InputStream?, interruptData: (UInt32, UInt32)?, mining_mode: MiningMode) -> MineResult {
    assert(params.extranonce2_size >= 2)
    var extranon2_start = UInt32(0)
    var intdata2: UInt32? = nil
    if let intdata = interruptData {
        extranon2_start = intdata.0
        intdata2 = intdata.1
    }
    for extranon2 in extranon2_start..<0xffff {
        var extranonce2 = String(format: "%04x", extranon2)
        extranonce2 = extranonce2.leftPadding(toLength: params.extranonce2_size * 2, withPad: "0")
        assert(extranonce2.count == params.extranonce2_size * 2)
        print("\(Date()) - Extranonce2: \(extranonce2)")
        let coinbase = params.coinb1 + params.extranonce1 + extranonce2 + params.coinb2
        let coinbase_hash_bin = doubleSHA256(input: Data(hexString: coinbase)!)
        let merkle_root = getMerkleRoot(branches: params.merkle_branches, coinbase: coinbase_hash_bin)
        let nonce = "00000000"
        let headerWithoutPadding = flipIntBytes(inp: params.version + params.prevhash + flipIntBytes(inp: merkle_root) + params.ntime + params.nbits + nonce)
        let header = headerWithoutPadding + "800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000280"
        let header1 = String(header.prefix(128))
        let header2 = String(header.suffix(128))
        //print("Header without padding: \(headerWithoutPadding)")
        assert(header.count == 256)
        let (_, state, _) = sha256(input: [UInt8](Data(hexString: header1)!))
        let intresult = metalSha(metalctxt: ctxt, state: state, hash_input: [UInt8](Data(hexString: header2)!), difficulty: params.diff, oistream: oistream, interruptData: intdata2, mining_mode: mining_mode)
        switch intresult {
        case .interrupted(let intnonce): return .interrupted(extranon2, intnonce)
        case .found(let nonce): return .found(extranon2, nonce)
        case .exhausted: intdata2 = nil
        }
    }
    return .exhausted
}

enum IntermediateMineResult {
    case interrupted(UInt32)
    case exhausted
    case found(UInt32)
}

func metalSha(metalctxt: MetalContext, state: [UInt32], hash_input: [UInt8], difficulty: UInt64, oistream: InputStream?, interruptData: UInt32?, mining_mode: MiningMode) -> IntermediateMineResult {
    let maxtgt: UInt64 = 0xffff0000
    var tgtn: String
    if difficulty == 0 {
        let tgt: UInt64 = UInt64(Double(maxtgt) / 0.01)
        tgtn = String(format: "00000000%08x000000000000000000000000000000000000000000000000", tgt)
        //tgtn = String("00000063ff9c0000000000000000000000000000000000000000000000000000")
    } else {
        let tgt: UInt64 = maxtgt / difficulty
        tgtn = String(format: "00000000%08x000000000000000000000000000000000000000000000000", tgt)
    }
    //let tgtn = String(format: "0000000fffff0000000000000000000000000000000000000000000000000000")
    print("Difficulty: \(difficulty)")
    //print("Target: \(tgtn)")
    let target = [UInt8](Data(hexString: tgtn)!)
    //print("Target len: \(target.count)")
    var noncebase: [UInt32] = [0]
    if let intdata = interruptData {
        noncebase = [intdata]
    }
    let noncefound: [UInt32] = [0xffffffff]
    let output = [UInt8](repeating: 0xff, count: 32)
    let length = hash_input.count * MemoryLayout< UInt8 >.stride
    assert(length == 64)
    let inbuf = metalctxt.device.makeBuffer(bytes: hash_input, length: length, options: [MTLResourceOptions.storageModeManaged])
    let statebuf = metalctxt.device.makeBuffer(bytes: state, length: state.count * MemoryLayout<UInt32>.stride, options: [MTLResourceOptions.storageModeManaged])
    let noncebuf = metalctxt.device.makeBuffer(bytes: noncebase, length: MemoryLayout<UInt32>.stride, options: [MTLResourceOptions.storageModeShared])
    let targetbuf = metalctxt.device.makeBuffer(bytes: target, length: target.count * MemoryLayout<UInt8>.stride, options: [MTLResourceOptions.storageModeManaged])
    let outbuf = metalctxt.device.makeBuffer(bytes: output, length: 32, options: [MTLResourceOptions.storageModeManaged])
    let noncefoundbuf = metalctxt.device.makeBuffer(bytes: noncefound, length: MemoryLayout<UInt32>.stride, options: [MTLResourceOptions.storageModeManaged])

    let gridSize = MTLSizeMake(mining_mode == .full ? 65536 : 16384, 1, 1)
    let nonceloops: UInt32 = mining_mode == .full ? 0x100 : 0x400

    for i in UInt32(noncebase[0])..<nonceloops { // nonce from 0 to 0xffffffff
        noncebase[0] = i * 0x100 * UInt32(gridSize.width)
        noncebuf!.contents().copyMemory(from: noncebase, byteCount: MemoryLayout<UInt32>.stride)
        //if i % 10 == 0 {
        //    print("Iteration \(i): \(Date()) - \(String(format: "%08x", noncebase[0]))")
        //}

        autoreleasepool {
            let commandBuffer = metalctxt.queue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            commandEncoder.setComputePipelineState(metalctxt.pipelineState)
            commandEncoder.setBuffer(inbuf, offset: 0, index: 0)
            commandEncoder.setBuffer(statebuf, offset: 0, index: 1)
            commandEncoder.setBuffer(noncebuf, offset: 0, index: 2)
            commandEncoder.setBuffer(targetbuf, offset: 0, index: 3)
            commandEncoder.setBuffer(outbuf, offset: 0, index: 4)
            commandEncoder.setBuffer(noncefoundbuf, offset: 0, index: 5)
            commandEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: metalctxt.threadGroupSize)
            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        let nonce = noncefoundbuf!.contents().load(fromByteOffset: 0, as: UInt32.self)
        if nonce != 0xffffffff {
            print(String(format: "%08x", nonce))
            var outhash: [UInt8] = Array(repeating: 0xff, count: 32)
            for i in 0..<32 {
                outhash[i] = outbuf!.contents().load(fromByteOffset: i, as: UInt8.self)
            }
            let hashString = outhash.compactMap { String(format: "%02x", $0) }.reversed().joined()
            print(hashString)
            return .found(nonce)
        } else {
            if let istream = oistream {
                if istream.hasBytesAvailable {
                    return .interrupted(i)
                }
            }
        }
        
        if mining_mode == .background {
            usleep(100 * 1000) // 100 ms
        }
    }
    return .exhausted
}


func getMerkleRoot(branches: [String], coinbase: Data) -> String {
    var merkle_root = coinbase
    for branch in branches {
        merkle_root.append(Data(hexString: branch)!)
        merkle_root = doubleSHA256(input: merkle_root)
    }
    return merkle_root.compactMap { String(format: "%02x", $0) }.joined()
}

func doubleSHA256(input: Data) -> Data {
    let hashed = SHA256.hash(data: input)
    return Data(SHA256.hash(data: Data(hashed)))
}
