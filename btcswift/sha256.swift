//
//  sha256.swift
//  btcswift
//
//  Created by Antti Salonen on 08/03/2021.
//

import Foundation


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

