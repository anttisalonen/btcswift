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

func testMetal() {
    let device = MTLCreateSystemDefaultDevice()!
    let queue = device.makeCommandQueue()!
    let library = device.makeDefaultLibrary()!
    let function = library.makeFunction(name: "add_arrays")!
    let pipelineState = try! device.makeComputePipelineState(function: function)
    
    let count = 1500
    let vec1 = [Float](repeating: 3, count: count)
    let vec2 = [Float](repeating: 5, count: count)
    let vec3 = [Float](repeating: 0, count: count)
    let length = count * MemoryLayout< Float >.stride
    let buf1 = device.makeBuffer(bytes: vec1, length: length, options: [MTLResourceOptions.storageModeShared])
    let buf2 = device.makeBuffer(bytes: vec2, length: length, options: [MTLResourceOptions.storageModeShared])
    let buf3 = device.makeBuffer(bytes: vec3, length: length, options: [MTLResourceOptions.storageModeShared])

    let commandBuffer = queue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    commandEncoder.setComputePipelineState(pipelineState)
    commandEncoder.setBuffer(buf1, offset: 0, index: 0)
    commandEncoder.setBuffer(buf2, offset: 0, index: 1)
    commandEncoder.setBuffer(buf3, offset: 0, index: 2)

    let gridSize = MTLSizeMake(count, 1, 1)
    let threadGroupSize = MTLSizeMake(min(count, pipelineState.maxTotalThreadsPerThreadgroup), 1, 1)
    // let width = pipelineState.threadExecutionWidth
    // let height = pipelineState.maxTotalThreadsPerThreadgroup / width
    // let threadsPerGroup = MTLSizeMake(width, height, 1)
    // let threadsPerGrid = MTLSizeMake(width, height, 1)
    commandEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
    
    commandEncoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
    print(buf3!.contents().load(fromByteOffset: 0, as: Float.self))
}

func testMetalSha() {
    let device = MTLCreateSystemDefaultDevice()!
    let queue = device.makeCommandQueue()!
    let library = device.makeDefaultLibrary()!
    let function = library.makeFunction(name: "sha256")!
    let pipelineState = try! device.makeComputePipelineState(function: function)
    
    // let input: Array<UInt8> = [0x61, 0x62, 0x63] // "abc"
    let input = [UInt8](repeating: 0x61, count: 160)
    let output = [UInt8](repeating: 0, count: 32)
    let length = input.count * MemoryLayout< UInt8 >.stride
    let lenarr: Array<UInt8> = [UInt8(length)]
    let inbuf = device.makeBuffer(bytes: input, length: length, options: [MTLResourceOptions.storageModeShared])
    let lenbuf = device.makeBuffer(bytes: lenarr, length: MemoryLayout<UInt8>.stride, options: [MTLResourceOptions.storageModeShared])
    let outbuf = device.makeBuffer(bytes: output, length: 64, options: [MTLResourceOptions.storageModeShared])

    let commandBuffer = queue.makeCommandBuffer()!
    let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
    commandEncoder.setComputePipelineState(pipelineState)
    commandEncoder.setBuffer(inbuf, offset: 0, index: 0)
    commandEncoder.setBuffer(lenbuf, offset: 0, index: 1)
    commandEncoder.setBuffer(outbuf, offset: 0, index: 2)

    let gridSize = MTLSizeMake(1, 1, 1)
    let threadGroupSize = MTLSizeMake(1, 1, 1)
    commandEncoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
    
    commandEncoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    
    print(String(format: "%02x", outbuf!.contents().load(fromByteOffset: 0, as: UInt8.self)))
    print(String(format: "%02x", outbuf!.contents().load(fromByteOffset: 1, as: UInt8.self)))
    print(String(format: "%02x", outbuf!.contents().load(fromByteOffset: 28, as: UInt8.self)))
    print(String(format: "%02x", outbuf!.contents().load(fromByteOffset: 29, as: UInt8.self)))
    print(String(format: "%02x", outbuf!.contents().load(fromByteOffset: 30, as: UInt8.self)))
    print(String(format: "%02x", outbuf!.contents().load(fromByteOffset: 31, as: UInt8.self)))
}

testHash()

// testStratum()

testJSON()

// testMetal()

testMetalSha()

"""
{"id":2,"result":true,"error":null}
{"id":null,"method":"mining.set_difficulty","params":[65536]}
{"id":null,"method":"mining.notify","params":["B8jXUJ1l0","37b402e08e42e39e009f5470251d4f75607313f6000c9f850000000000000000","01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff64031b450a2cfabe6d6d3b021eb18efc4ee2d0aa627af7130f86abf4288d83b9441015a1a2fe752527e810000000f09f909f082f4632506f6f6c2f0e4d696e656420627920616e74746900000000000000000000000000000000000000000005","0443b27b29000000001976a914c825a1ecf2a6830c4401620c3a16f1995057c2ab88ac00000000000000002f6a24aa21a9ed550ae1fec3b1e0da653968d9903bd25d8d14b62e2d1657c2e57da0916b4dd35208000000000000000000000000000000002c6a4c2952534b424c4f434b3a46836ee1f6b21aaaec920d6ff751b62d8f42b0e3af37490dbc861a23002fcd020000000000000000266a24b9e11b6d9dba9e17e0d5b3a113458f47bb5ea2cd6301d2c489a5aca4d77a6d14e8699d9d7c2cc739",["000ba37c5fc781774502ed6634d55ee2101598de818632a4fbf2d8fa3b66a9ae","f4ea1e236526258294ee075c6aaedb76da94953a0fc665f827be6a6c91be02fc","d567a93c80be6a3425ac4e9ff1c657bcd2657122e5766e35b7f8a76764f6ffb6","3ecc37a3189037cd0831fdc2403b86dbf5352578aced55ed9c23c6b6304abee7","326dcdd35adaf3dc56ab9033f5db119cd2863c513b7ef617bc94e8e1c49cd499","067af004f8af8ec73551d8a0c775fafc99ff60c5b2709a9d0e0291ed7460a69b","d32916d50c00d607d3b40b2dcc092dbcc15822a619fae1638e2eeb7ed5d9d4b8","ff1b12356da0d6d7919f89dd0f5434388faa036b361b8567fc2b0870256f7f27","158a53e7c82823c13f089f2283ced9f890c64421ef60a99560148a1d1f8fb9e6","2292818446b1e7354e7c09ca7225944633c301fe158e142972969352a9890ed8","e89c9ea3cd706fda19c1458602653f2eb53520c1cba4adef92615678711d456d","f96cd98cbc17c1a4e8913ce48ffcaaa7ca105a70885698388c4cd5c0c27b78a7"],"20000000","170cf4e3","604015a8",true]}
"""
