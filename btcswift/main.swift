//
//  main.swift
//  btcswift
//
//  Created by Antti Salonen on 03/03/2021.
//

import Foundation

main()

enum MiningMode {
    case full
    case background
}

func main() {
    let HOST = CommandLine.arguments[1]
    let PORT = Int(CommandLine.arguments[2])!
    let worker_name = CommandLine.arguments[3]
    let password = CommandLine.arguments[4]
    let mmstr = CommandLine.arguments[5]
    var mining_mode: MiningMode
    switch mmstr {
    case "full": mining_mode = .full
    case "background": mining_mode = .background
    default: mining_mode = .full
    }
    
    let metalctxt = initMetal()
    
    //let HOST = "eu.stratum.slushpool.com"
    //let PORT = 3333
    //let worker_name = "anttifoobar.001"
    //let password = "anything"
    
    //let HOST = "btc.f2pool.com"
    //let PORT = 1314
    //let worker_name = "antti.001"
    //let password = "21235365876986800"

    // testnet
    //let HOST = "pool.bitcoincloud.net"
    //let PORT = 4008
    //let worker_name = "2N16oE62ZjAPup985dFBQYAuy5zpDraH7Hk"
    //let password = "anything"
    
    // test
    //print(stratumparams)
    //let testresult = readAndMine(ctxt: metalctxt, params: stratumparams, oistream: nil, interruptData: nil)
    //switch testresult {
    //case .found(let test_extranonce2, let test_nonce): assert(test_extranonce2 == 0x00000000 && test_nonce == 0x013817dd)
    //default: assert(false)
    //}

    var (stratum, miningctxt) = connectStratum(host: HOST, port: PORT, worker_name: worker_name, password: password)!
    var interruptData: (UInt32, UInt32)? = nil
    var finished = false
    var curr_id = 4
    var is_open = true
    while is_open {
        var result: MineResult
        if !finished {
            result = readAndMine(ctxt: metalctxt, params: miningctxt.mineparams, oistream: stratum.inputStream, interruptData: interruptData, mining_mode: mining_mode)
        } else {
            sleep(1)
            if stratum.inputStream.hasBytesAvailable {
                result = .interrupted(0, 0)
            } else {
                result = .exhausted
            }
        }
        switch result {
        case .found(let extranonce2, let nonce):
            submitShare(stratum: stratum, next_id: curr_id, jobid: miningctxt.jobid, extranonce2: extranonce2, extranonce2_size: miningctxt.mineparams.extranonce2_size, ntime: miningctxt.mineparams.ntime, nonce: nonce)
            curr_id += 1
            sleep(1)
            finished = true
        case .exhausted:
            print("Not found")
            finished = true
        case .interrupted(let int1, let int2):
            interruptData = (int1, int2)
            let maybeNewMiningCtxt = handleStratumInterrupt(stratum: stratum, prevContext: miningctxt, waiting: finished)
            if let newMiningCtxt = maybeNewMiningCtxt {
                print("Got new mining context")
                miningctxt = newMiningCtxt
                interruptData = nil
                finished = false
            }
            if stratum.inputStream.streamStatus == .atEnd || stratum.inputStream.streamStatus == .closed || stratum.inputStream.streamStatus == .error {
                is_open = false
            }
        }
    }
}
