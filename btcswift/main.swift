//
//  main.swift
//  btcswift
//
//  Created by Antti Salonen on 03/03/2021.
//

import Foundation

main()

func main() {
    let metalctxt = initMetal()
    
    let HOST = "btc.f2pool.com"
    let PORT = 1314
    let worker_name = "antti.001"
    let password = "21235365876986800"

    // testnet
    //let HOST = "pool.bitcoincloud.net"
    //let PORT = 4008
    //let worker_name = "2N16oE62ZjAPup985dFBQYAuy5zpDraH7Hk"
    //let password = "anything"
    
    // test
    print(stratumparams)
    let (test_extranonce2, test_nonce) = readAndMine(ctxt: metalctxt, params: stratumparams)!
    assert(test_extranonce2 == 0x00000000 && test_nonce == 0x013817dd)

    let (stratum, miningctxt) = connectStratum(host: HOST, port: PORT, worker_name: worker_name, password: password)!
    let (extranonce2, nonce) = readAndMine(ctxt: metalctxt, params: miningctxt.mineparams)!
    submitShare(stratum: stratum, next_id: 3, jobid: miningctxt.jobid, extranonce2: extranonce2, extranonce2_size: miningctxt.mineparams.extranonce2_size, ntime: miningctxt.mineparams.ntime, nonce: nonce)
    sleep(1)
    _ = readStr(stream: stratum.inputStream)
}
