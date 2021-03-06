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
    var buffer = [UInt8](repeating: 0, count: 16384)
    if !stream.hasBytesAvailable {
        return ""
    }
    let numBytesRead = stream.read(&buffer, maxLength: buffer.count)
    if numBytesRead > 0 {
        let dataIn = String(decoding: Data(buffer), as: UTF8.self)
        let data = dataIn.replacingOccurrences(of: "\0", with: "")
        print("Stratum IN:  \(String(data.prefix(100)))")
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
        sleep(1)
        let resp2 = readStr(stream: inputStream).components(separatedBy: "\n")
        let (octxt, _) = getMiningContext(jsondata: [resp1] + resp2, mprevContext: nil)
        let ctxt = octxt!
        if ctxt.mineparams.diff > 128 {
            writeStr(stream: outputStream, str: "{\"id\": 3, \"method\": \"mining.suggest_difficulty\", \"params\": [128]}")
        }
        return (Stratum(inputStream: inputStream, outputStream: outputStream, worker_name: worker_name, password: password), ctxt)
    }
    return nil
}

func getMiningContext(jsondata: [String], mprevContext: MiningContext?) -> (MiningContext?, Bool) {
    var extranonce1: String = ""
    var extranonce2_size: Int = 0
    
    var udiff: UInt64 = 0
    
    var job_id: String = ""
    var prevhash: String = ""
    var coinb1: String = ""
    var coinb2: String = ""
    var branches: [String] = []
    var version: String = ""
    var nbits: String = ""
    var ntime: String = ""
    var clean_jobs: Bool = false
    
    if let prevContext = mprevContext {
        extranonce1 = prevContext.mineparams.extranonce1
        extranonce2_size = prevContext.mineparams.extranonce2_size
        udiff = prevContext.mineparams.diff
    }
    
    for jsond in jsondata {
        if jsond == "" {
            continue
        }
        let json = try! JSONSerialization.jsonObject(with: Data(jsond.utf8), options: []) as! [String: Any]
        let optid = json["id"]
        if let id = optid as? Int {
            if id == 1 {
                let result = json["result"] as! [Any]
                extranonce1 = result[1] as! String
                extranonce2_size = result[2] as! Int
            }
        } else {
            if let method = json["method"] as? String {
                if method == "mining.set_difficulty" {
                    let diff = (json["params"] as! [Double])[0]
                    udiff = diff < 1.0 ? UInt64(0) : UInt64(diff)
                } else if method == "mining.notify" {
                    let jsonparams = json["params"] as! [Any]
                    job_id = jsonparams[0] as! String
                    prevhash = jsonparams[1] as! String
                    coinb1 = jsonparams[2] as! String
                    coinb2 = jsonparams[3] as! String
                    branches = jsonparams[4] as! [String]
                    version = jsonparams[5] as! String
                    nbits = jsonparams[6] as! String
                    ntime = jsonparams[7] as! String
                    clean_jobs = jsonparams[8] as! Bool
                }
            }
        }
    }
    
    if extranonce2_size == 0 || ntime == "" {
        return (nil, false)
    }

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
    return (MiningContext(jobid: job_id, mineparams: params), clean_jobs)
}

func submitShare(stratum: Stratum, next_id: Int, jobid: String, extranonce2: UInt32, extranonce2_size: Int, ntime: String, nonce: UInt32) {
    let fmtstr = String(format: "%%0%dx", extranonce2_size * 2)
    writeStr(stream: stratum.outputStream, str: "{\"params\": [\"\(stratum.worker_name)\", \"\(jobid)\", \"\(String(format: fmtstr, extranonce2))\", \"\(ntime)\", \"\(String(format: "%08x", nonce))\"], \"id\": \(next_id), \"method\": \"mining.submit\"}\n")
    _ = readStr(stream: stratum.inputStream)
}

func handleStratumInterrupt(stratum: Stratum, prevContext: MiningContext, waiting: Bool) -> MiningContext? {
    print("!! Stratum message interrupts mining")
    let indata = readStr(stream: stratum.inputStream).components(separatedBy: "\n")
    let (newctxt, do_clean) = getMiningContext(jsondata: indata, mprevContext: prevContext)
    if let ctxt = newctxt {
        if do_clean || waiting || ctxt.mineparams.diff != prevContext.mineparams.diff {
            return ctxt
        }
    }
    return nil
}
