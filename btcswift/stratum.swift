//
//  stratum.swift
//  btcswift
//
//  Created by Antti Salonen on 09/03/2021.
//

import Foundation

func writeStr(stream: OutputStream, str: String) {
    let dataOut = Data(str.utf8)
    dataOut.withUnsafeBytes { stream.write($0, maxLength: dataOut.count)}
    print("Stratum OUT: \(str)")
}

func readStr(stream: InputStream) -> String {
    var buffer = [UInt8](repeating: 0, count: 4096)
    let numBytesRead = stream.read(&buffer, maxLength: buffer.count)
    if numBytesRead > 0 {
        let dataIn = String(decoding: Data(buffer), as: UTF8.self)
        let data = dataIn.replacingOccurrences(of: "\0", with: "")
        print("Stratum IN:  \(data)")
        return data
    }
    return ""
}

func connectStratum(host: String, port: Int, worker_name: String, password: String) -> (Stratum, MiningContext)? {
    var inp : InputStream?
    var out : OutputStream?
    
    Stream.getStreamsToHost(withName: host, port: port, inputStream: &inp, outputStream: &out)
    
    if inp == nil || out == nil {
        print("Could not initialise socket")
        return nil
    }
    
    let inputStream : InputStream = inp!
    let outputStream : OutputStream = out!
    inputStream.open()
    outputStream.open()
    
    if outputStream.streamError != nil || inputStream.streamError != nil {
        print("Could not initialise stream")
        return nil
    }
    
    if outputStream.streamError == nil && inputStream.streamError == nil {
        writeStr(stream: outputStream, str: "{\"id\": 1, \"method\": \"mining.subscribe\", \"params\": []}\n")
        let resp1 = readStr(stream: inputStream)
        writeStr(stream: outputStream, str: "{\"params\": [\"\(worker_name)\", \"\(password)\"], \"id\": 2, \"method\": \"mining.authorize\"}\n")
        let resp2 = readStr(stream: inputStream).components(separatedBy: "\n")
        let ctxt = getMiningContext(data1: resp1, data2: resp2[0], data3: resp2[1])
        sleep(1)
        readStr(stream: inputStream)
        return (Stratum(inputStream: inputStream, outputStream: outputStream, worker_name: worker_name, password: password), ctxt)
    }
    return nil
}

func getMiningContext(data1: String, data2: String, data3: String) -> MiningContext {
    let json = try! JSONSerialization.jsonObject(with: Data(data1.utf8), options: []) as! [String: Any]
    let result = json["result"] as! [Any]
    let extranonce1 = result[1] as! String
    let extranonce2_size = result[2] as! Int

    let json2 = try! JSONSerialization.jsonObject(with: Data(data2.utf8), options: []) as! [String: Any]
    let diff = (json2["params"] as! [Double])[0]
    let udiff = diff < 1.0 ? UInt64(0) : UInt64(diff)

    let json3 = try! JSONSerialization.jsonObject(with: Data(data3.utf8), options: []) as! [String: Any]
    let jsonparams = json3["params"] as! [Any]
    let job_id = jsonparams[0] as! String
    let prevhash = jsonparams[1] as! String
    let coinb1 = jsonparams[2] as! String
    let coinb2 = jsonparams[3] as! String
    let branches = jsonparams[4] as! [String]
    let version = jsonparams[5] as! String
    let nbits = jsonparams[6] as! String
    let ntime = jsonparams[7] as! String

    let params: MineParameters = MineParameters(
        extranonce1: extranonce1,
        extranonce2_size: extranonce2_size,
        diff: udiff,
        prevhash: prevhash,
        coinb1: coinb1,
        coinb2: coinb2,
        merkle_branches: branches,
        version: version,
        nbits: nbits,
        ntime: ntime)
    print(params)
    return MiningContext(jobid: job_id, mineparams: params)
}

func submitShare(stratum: Stratum, next_id: Int, jobid: String, extranonce2: UInt32, extranonce2_size: Int, ntime: String, nonce: UInt32) {
    let fmtstr = String(format: "%%0%dx", extranonce2_size * 2)
    writeStr(stream: stratum.outputStream, str: "{\"params\": [\"\(stratum.worker_name)\", \"\(jobid)\", \"\(String(format: fmtstr, extranonce2))\", \"\(ntime)\", \"\(String(format: "%08x", nonce))\"], \"id\": \(next_id), \"method\": \"mining.submit\"}\n")
    _ = readStr(stream: stratum.inputStream)
}
