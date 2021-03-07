//
//  main.swift
//  btcswift
//
//  Created by Antti Salonen on 03/03/2021.
//

import Foundation
import Crypto
import MetalKit

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}

extension String {
    func split(by length: Int) -> [String] {
        var startIndex = self.startIndex
        var results = [Substring]()
        
        while startIndex < self.endIndex {
            let endIndex = self.index(startIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            results.append(self[startIndex..<endIndex])
            startIndex = endIndex
        }
        
        return results.map { String($0) }
    }
}

func strToLittleEndian(inp: String) -> String {
    return inp.split(by: 2).reversed().joined()
}

let HOST = "btc.f2pool.com"
let PORT = 1314

let DIFFICULTY_BASE = "0x0000FFFF00000000000000000000000000000000000000000000000000000000"

extension NSDecimalNumber {
    convenience init(string: String, base: Int) {
        guard base >= 2 && base <= 16 else { fatalError("Invalid base") }

        let digits = "0123456789abcdef"
        let baseNum = NSDecimalNumber(value: base)

        var res = NSDecimalNumber(value: 0)
        for ch in string {
            let index = digits.firstIndex(of: ch)!
            let digit = digits.distance(from: digits.startIndex, to: index)
            res = res.multiplying(by: baseNum).adding(NSDecimalNumber(value: digit))
        }

        self.init(decimal: res.decimalValue)
    }

    func toBase(_ base: Int) -> String {
        guard base >= 2 && base <= 16 else { fatalError("Invalid base") }

        // Support higher bases by added more digits
        let digits = "0123456789abcdef"
        let rounding = NSDecimalNumberHandler(roundingMode: .down, scale: 0, raiseOnExactness: false, raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false)
        let baseNum = NSDecimalNumber(value: base)

        var res = ""
        var val = self
        while val.compare(0) == .orderedDescending {
            let next = val.dividing(by: baseNum, withBehavior: rounding)
            let round = next.multiplying(by: baseNum)
            let diff = val.subtracting(round)
            let digit = diff.intValue
            let index = digits.index(digits.startIndex, offsetBy: digit)
            res.insert(digits[index], at: res.startIndex)

            val = next
        }

        return res
    }
}

func testHash() {
    let version = String(format: "%08x", UInt32(bigEndian: 1).littleEndian)
    let prevBlock = strToLittleEndian(inp: "00000000000008a3a41b85b8b29ad444def299fee21793cd8b9e567eab02cd81")
    let merkleRoot = strToLittleEndian(inp: "2b12fcf1b09288fcaff797d71e950e71ae42b91e8bdb2304758dfcffc2b620e3")
    let timestamp = String(format: "%08x", UInt32(bigEndian: 1305998791).littleEndian)
    let bits = String(format: "%08x", UInt32(bigEndian: 440711666).littleEndian)
    let nonce = String(format: "%08x", UInt32(bigEndian: 2504433986).littleEndian)
    
    let headerHex = version + prevBlock + merkleRoot + timestamp + bits + nonce
    print(headerHex)
    
    let inputData = Data(hexString: headerHex)!
    let hashed = SHA256.hash(data: inputData)
    let hashed2 = SHA256.hash(data: Data(hashed))
    let hashString = hashed2.compactMap { String(format: "%02x", $0) }.reversed().joined()
    
    print(hashString)
}

struct NotifyMsg: Decodable {
    let id: Int
    let result: [NotifyResult]?
}

struct NotifyResult: Decodable {
    
}

func writeStr(stream: OutputStream, str: String) {
    let dataOut = Data(str.utf8)
    dataOut.withUnsafeBytes { stream.write($0, maxLength: dataOut.count)}
}

func readStr(stream: InputStream) -> String {
    var buffer = [UInt8](repeating: 0, count: 4096)
    let numBytesRead = stream.read(&buffer, maxLength: buffer.count)
    if numBytesRead > 0 {
        let dataIn = String(decoding: Data(buffer), as: UTF8.self)
        return dataIn
    }
    return ""
}

func testStratum() {
    var inp : InputStream?
    var out : OutputStream?
    
    Stream.getStreamsToHost(withName: HOST, port: PORT, inputStream: &inp, outputStream: &out)
    
    if inp == nil || out == nil {
        print("Could not initialise socket")
        return
    }
    
    let inputStream : InputStream = inp!
    let outputStream : OutputStream = out!
    inputStream.open()
    outputStream.open()
    
    if outputStream.streamError != nil || inputStream.streamError != nil {
        print("Could not initialise stream")
        return
    }
    
    if outputStream.streamError == nil && inputStream.streamError == nil {
        writeStr(stream: outputStream, str: "{\"id\": 1, \"method\": \"mining.subscribe\", \"params\": []}\n")
        let resp1 = readStr(stream: inputStream)
        print(resp1)
        writeStr(stream: outputStream, str: "{\"params\": [\"antti.001\", \"21235365876986800\"], \"id\": 2, \"method\": \"mining.authorize\"}\n")
        let resp2 = readStr(stream: inputStream)
        print(resp2)
    }
}

func testJSON() {
    let data = Data("""
    {"id":1,"result":[[["mining.notify","mining.notify"],["mining.set_difficulty","mining.set_difficulty"]],"00",8],"error":null}
    """.utf8)
    
    do {
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
            if let result = json["result"] as? [Any] {
                print(result[0])
                print(result[1])
                print(result[2])
            }
        }
    } catch let error {
        print("Failed to read JSON: \(error.localizedDescription)")
    }
}

func metalSha(state: [UInt32], hash_input: [UInt8]) {
    let device = MTLCreateSystemDefaultDevice()!
    let queue = device.makeCommandQueue()!
    let library = device.makeDefaultLibrary()!
    let function = library.makeFunction(name: "sha256_double")!
    let pipelineState = try! device.makeComputePipelineState(function: function)
    
    let threads = pipelineState.maxTotalThreadsPerThreadgroup
    let thwidth = pipelineState.threadExecutionWidth
    print("Number of threads: \(threads)")
    print("Thread width: \(thwidth)")
    let tgtnum: UInt64 = 1
    let maxtgt: UInt64 = 0xffff0000
    let tgt: UInt64 = maxtgt / tgtnum
    // let tgtn = String(format: "000000%08x00000000000000000000000000000000000000000000000000", tgt)
    let tgtn = String(format: "00000005ffff0000000000000000000000000000000000000000000000000000")
    print("Target: \(maxtgt)")
    print("Target: \(tgtnum)")
    print("Target: \(tgt)")
    print("Target: \(tgtn)")
    let target = [UInt8](Data(hexString: tgtn)!)
    print("Target len: \(target.count)")
    var noncebase: [UInt32] = [0]
    let noncefound: [UInt32] = [0xffffffff]
    let output = [UInt8](repeating: 0xff, count: 32)
    let length = hash_input.count * MemoryLayout< UInt8 >.stride
    let inbuf = device.makeBuffer(bytes: hash_input, length: length, options: [MTLResourceOptions.storageModeManaged])
    let statebuf = device.makeBuffer(bytes: state, length: state.count * MemoryLayout<UInt32>.stride, options: [MTLResourceOptions.storageModeManaged])
    let noncebuf = device.makeBuffer(bytes: noncebase, length: MemoryLayout<UInt32>.stride, options: [MTLResourceOptions.storageModeShared])
    let targetbuf = device.makeBuffer(bytes: target, length: target.count * MemoryLayout<UInt8>.stride, options: [MTLResourceOptions.storageModeManaged])
    let outbuf = device.makeBuffer(bytes: output, length: 32, options: [MTLResourceOptions.storageModeManaged])
    let noncefoundbuf = device.makeBuffer(bytes: noncefound, length: MemoryLayout<UInt32>.stride, options: [MTLResourceOptions.storageModeManaged])

    let gridSize = MTLSizeMake(65536, 1, 1)
    let threadGroupSize = MTLSizeMake(threads, 1, 1)

    for i in 0..<0x100 { // nonce from 0 to 0xffffffff
        noncebase[0] = UInt32(i) * 0x100 * UInt32(gridSize.width)
        noncebuf!.contents().copyMemory(from: noncebase, byteCount: MemoryLayout<UInt32>.stride)
        if i % 10 == 0 {
            print("Iteration \(i): \(Date()) - \(noncebase[0])")
        }

        autoreleasepool {
            let commandBuffer = queue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
            commandEncoder.setComputePipelineState(pipelineState)
            commandEncoder.setBuffer(inbuf, offset: 0, index: 0)
            commandEncoder.setBuffer(statebuf, offset: 0, index: 1)
            commandEncoder.setBuffer(noncebuf, offset: 0, index: 2)
            commandEncoder.setBuffer(targetbuf, offset: 0, index: 3)
            commandEncoder.setBuffer(outbuf, offset: 0, index: 4)
            commandEncoder.setBuffer(noncefoundbuf, offset: 0, index: 5)
            commandEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
        
        let nonce = noncefoundbuf!.contents().load(fromByteOffset: 0, as: UInt32.self)
        if nonce != 0xffffffff {
            print(String(format: "%08x", nonce))
            print(String(format: "%02x", outbuf!.contents().load(fromByteOffset: 0, as: UInt8.self)))
            print(String(format: "%02x", outbuf!.contents().load(fromByteOffset: 1, as: UInt8.self)))
            print(String(format: "%02x", outbuf!.contents().load(fromByteOffset: 28, as: UInt8.self)))
            print(String(format: "%02x", outbuf!.contents().load(fromByteOffset: 29, as: UInt8.self)))
            print(String(format: "%02x", outbuf!.contents().load(fromByteOffset: 30, as: UInt8.self)))
            print(String(format: "%02x", outbuf!.contents().load(fromByteOffset: 31, as: UInt8.self)))
            break
        }
    }
}

func rotright(a: UInt32, b: UInt32) -> UInt32
{
    return ((a >> b)) | ((a << (32 - b)))
}

func ch(x: UInt32, y: UInt32, z: UInt32) -> UInt32
{
    return ((x) & (y)) ^ (~(x) & (z))
}

func maj(x: UInt32, y: UInt32, z: UInt32) -> UInt32
{
    return ((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z))
}

func ep0(x: UInt32) -> UInt32
{
    return rotright(a: x,b: 2) ^ rotright(a: x,b: 13) ^ rotright(a: x,b: 22)
}

func ep1(x: UInt32) -> UInt32
{
    return rotright(a: x, b: 6) ^ rotright(a: x, b: 11) ^ rotright(a: x,b: 25)
}

func sig0(x: UInt32) -> UInt32
{
    return rotright(a: x, b: 7) ^ rotright(a: x, b: 18) ^ ((x) >> 3)
}

func sig1(x: UInt32) -> UInt32
{
    return rotright(a: x, b: 17) ^ rotright(a: x, b: 19) ^ ((x) >> 10)
}

let k: Array<UInt32> = [
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
]

func sha256_transform(state: [UInt32], data: [UInt8]) -> [UInt32]
{
    var m = [UInt32](repeating: 0, count: 64)
    var j = 0
    for i in 0..<16 {
        let m1: UInt32 = UInt32(data[j + 3])
        let m2: UInt32 = UInt32(data[j + 2]) << 8
        let m3: UInt32 = UInt32(data[j + 1]) << 16
        let m4: UInt32 = UInt32(data[j + 0]) << 24
        m[i] = m1 | m2 | m3 | m4
        j += 4
    }
    for i in 16..<64 {
        m[i] = sig1(x: m[i - 2]) &+ m[i - 7] &+ sig0(x: m[i - 15]) &+ m[i - 16]
    }

    var a = state[0]
    var b = state[1]
    var c = state[2]
    var d = state[3]
    var e = state[4]
    var f = state[5]
    var g = state[6]
    var h = state[7]
    
    for i in 0..<64 {
        let t1: UInt32 = h &+ ep1(x: e) &+ ch(x: e, y: f, z: g) &+ k[i] &+ m[i]
        let t2: UInt32 = ep0(x: a) &+ maj(x: a, y: b, z: c)
        h = g
        g = f
        f = e
        e = d &+ t1
        d = c
        c = b
        b = a
        a = t1 &+ t2
    }
    
    return [state[0] &+ a,
    state[1] &+ b,
    state[2] &+ c,
    state[3] &+ d,
    state[4] &+ e,
    state[5] &+ f,
    state[6] &+ g,
    state[7] &+ h]
}

func sha256(input: [UInt8]) -> ([UInt8], [UInt32], UInt64)
{
    var state: [UInt32] = [
        0x6a09e667,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19,
    ]
    var datalen: Int = 0
    var bitlen: UInt64 = 0
    var data = [UInt8](repeating: 0, count: 64)
    for i in 0..<input.count {
        data[datalen] = input[i]
        datalen += 1
        if datalen == 64 {
            state = sha256_transform(state: state, data: data)
            bitlen += 512
            datalen = 0
        }
    }
    
    var it = datalen
    if datalen < 56 {
        data[Int(it)] = 0x80
        it += 1
        while it < 56 {
            data[Int(it)] = 0x00
            it += 1
        }
    } else {
        data[Int(it)] = 0x80
        it += 1
        while it < 64  {
            data[Int(it)] = 0x00
            it += 1
        }
        state = sha256_transform(state: state, data: data)
        for i in 0..<56 {
            data[i] = 0
        }
    }
    let penultimate_state = state
    
    bitlen = bitlen + UInt64(datalen) * 8
    data[63] = UInt8(bitlen & 0xff)
    data[62] = UInt8((bitlen >> 8) & 0xff)
    data[61] = UInt8((bitlen >> 16) & 0xff)
    data[60] = UInt8((bitlen >> 24) & 0xff)
    data[59] = UInt8((bitlen >> 32) & 0xff)
    data[58] = UInt8((bitlen >> 40) & 0xff)
    data[57] = UInt8((bitlen >> 48) & 0xff)
    data[56] = UInt8((bitlen >> 56) & 0xff)
    state = sha256_transform(state: state, data: data)
    
    var result = [UInt8](repeating: 0, count: 32)
    for i in 0..<4 {
        result[i]      = UInt8((state[0] >> (24 - i * 8)) & 0x000000ff)
        result[i + 4]  = UInt8((state[1] >> (24 - i * 8)) & 0x000000ff)
        result[i + 8]  = UInt8((state[2] >> (24 - i * 8)) & 0x000000ff)
        result[i + 12] = UInt8((state[3] >> (24 - i * 8)) & 0x000000ff)
        result[i + 16] = UInt8((state[4] >> (24 - i * 8)) & 0x000000ff)
        result[i + 20] = UInt8((state[5] >> (24 - i * 8)) & 0x000000ff)
        result[i + 24] = UInt8((state[6] >> (24 - i * 8)) & 0x000000ff)
        result[i + 28] = UInt8((state[7] >> (24 - i * 8)) & 0x000000ff)
    }
    return (result, penultimate_state, bitlen)
}

func getShaState(input: String) -> ([UInt32], UInt64) {
//    let res = sha256(input: [UInt8](Data(hexString: input)!))
    let (res, state, bitlen) = sha256(input: [UInt8](Data(hexString: input)!))
    print(res)
    for i in 0..<8 {
        print(String(format: "%08x", state[i]))
    }
    print(bitlen)
    return (state, bitlen)
}

func testPartialSha() {
    // let input = "0000002063bf28417b38570f415be2007eb71b9d36407e66e8fed8a756010000000000009b9c9ab0b1c92844e4fed3f895f9443fefcda5ae02cc5a8ad4444f9303081a238c8a145e98b0021a"
    let input = "0000002063bf28417b38570f415be2007eb71b9d36407e66e8fed8a756010000000000009b9c9ab0b1c92844e4fed3f895f9443fefcda5ae02cc5a8ad4444f93"
    let (state, bitlen) = getShaState(input: input)
    let nonce = "d0cf1040"
    let hash_input = "03081a238c8a145e98b0021ad0cf1040800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000280"
    metalSha(state: state, hash_input: [UInt8](Data(hexString: hash_input)!))
}

testHash()

// testStratum()

testJSON()

// testMetalSha()

testPartialSha()

"""
{"id":2,"result":true,"error":null}
{"id":null,"method":"mining.set_difficulty","params":[65536]}
{"id":null,"method":"mining.notify","params":["B8jXUJ1l0","37b402e08e42e39e009f5470251d4f75607313f6000c9f850000000000000000","01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff64031b450a2cfabe6d6d3b021eb18efc4ee2d0aa627af7130f86abf4288d83b9441015a1a2fe752527e810000000f09f909f082f4632506f6f6c2f0e4d696e656420627920616e74746900000000000000000000000000000000000000000005","0443b27b29000000001976a914c825a1ecf2a6830c4401620c3a16f1995057c2ab88ac00000000000000002f6a24aa21a9ed550ae1fec3b1e0da653968d9903bd25d8d14b62e2d1657c2e57da0916b4dd35208000000000000000000000000000000002c6a4c2952534b424c4f434b3a46836ee1f6b21aaaec920d6ff751b62d8f42b0e3af37490dbc861a23002fcd020000000000000000266a24b9e11b6d9dba9e17e0d5b3a113458f47bb5ea2cd6301d2c489a5aca4d77a6d14e8699d9d7c2cc739",["000ba37c5fc781774502ed6634d55ee2101598de818632a4fbf2d8fa3b66a9ae","f4ea1e236526258294ee075c6aaedb76da94953a0fc665f827be6a6c91be02fc","d567a93c80be6a3425ac4e9ff1c657bcd2657122e5766e35b7f8a76764f6ffb6","3ecc37a3189037cd0831fdc2403b86dbf5352578aced55ed9c23c6b6304abee7","326dcdd35adaf3dc56ab9033f5db119cd2863c513b7ef617bc94e8e1c49cd499","067af004f8af8ec73551d8a0c775fafc99ff60c5b2709a9d0e0291ed7460a69b","d32916d50c00d607d3b40b2dcc092dbcc15822a619fae1638e2eeb7ed5d9d4b8","ff1b12356da0d6d7919f89dd0f5434388faa036b361b8567fc2b0870256f7f27","158a53e7c82823c13f089f2283ced9f890c64421ef60a99560148a1d1f8fb9e6","2292818446b1e7354e7c09ca7225944633c301fe158e142972969352a9890ed8","e89c9ea3cd706fda19c1458602653f2eb53520c1cba4adef92615678711d456d","f96cd98cbc17c1a4e8913ce48ffcaaa7ca105a70885698388c4cd5c0c27b78a7"],"20000000","170cf4e3","604015a8",true]}
"""
