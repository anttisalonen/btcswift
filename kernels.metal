//
//  kernels.metal
//  btcswift
//
//  Created by Antti Salonen on 04/03/2021.
//

#include <metal_stdlib>
using namespace metal;

kernel void compute(texture2d<float, access::read> input [[texture(0)]],
                    texture2d<float, access::write> output [[texture(1)]],
                    uint2 id [[thread_position_in_grid]]) {
    uint2 index = uint2((id.x / 5) * 5, (id.y / 5) * 5);
    float4 color = input.read(index);
    output.write(color, id);
}

kernel void add_arrays(device const float* inA,
                       device const float* inB,
                       device float* result,
                       uint index [[thread_position_in_grid]])
{
    // the for-loop is replaced with a collection of threads, each of which
    // calls this function.
    result[index] = inA[index] + inB[index];
}

static uint32_t rotleft(uint32_t a, uint8_t b)
{
    return ((a << b)) | ((a >> (32 - b)));
}

static uint32_t rotright(uint32_t a, uint8_t b)
{
    return ((a >> b)) | ((a << (32 - b)));
}

static uint32_t ch(uint32_t x, uint32_t y, uint32_t z)
{
    return ((x) & (y)) ^ (~(x) & (z));
}

static uint32_t maj(uint32_t x, uint32_t y, uint32_t z)
{
    return ((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z));
}

static uint32_t ep0(uint32_t x)
{
    return rotright(x,2) ^ rotright(x,13) ^ rotright(x,22);
}

static uint32_t ep1(uint32_t x)
{
    return rotright(x,6) ^ rotright(x,11) ^ rotright(x,25);
}

static uint32_t sig0(uint32_t x)
{
    return rotright(x,7) ^ rotright(x,18) ^ ((x) >> 3);
}

static uint32_t sig1(uint32_t x)
{
    return rotright(x,17) ^ rotright(x,19) ^ ((x) >> 10);
}

constant uint32_t k[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

void sha256_transform(thread uint32_t* state, thread const uint8_t* data)
{
    uint32_t a, b, c, d, e, f, g, h, i, j, t1, t2, m[64];

    for (i = 0, j = 0; i < 16; ++i, j += 4)
        m[i] = (data[j] << 24) | (data[j + 1] << 16) | (data[j + 2] << 8) | (data[j + 3]);
    for ( ; i < 64; ++i)
        m[i] = sig1(m[i - 2]) + m[i - 7] + sig0(m[i - 15]) + m[i - 16];

    a = state[0];
    b = state[1];
    c = state[2];
    d = state[3];
    e = state[4];
    f = state[5];
    g = state[6];
    h = state[7];

    for (i = 0; i < 64; ++i) {
        t1 = h + ep1(e) + ch(e,f,g) + k[i] + m[i];
        t2 = ep0(a) + maj(a,b,c);
        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    state[5] += f;
    state[6] += g;
    state[7] += h;
}

kernel void sha256(device const uint8_t* input,
                   device const uint8_t* len,
                   device uint8_t* result)
{
    uint32_t state[8] = {
        0x6a09e667,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19,
    };
    uint32_t datalen = 0;
    uint64_t bitlen = 0;
    uint8_t data[64];
    for(int i = 0; i < len[0]; i++) {
        data[datalen] = input[i];
        datalen++;
        if(datalen == 64) {
            sha256_transform(state, data);
            bitlen += 512;
            datalen = 0;
        }
    }
    
    uint32_t it = datalen;
    if(datalen < 56) {
        data[it] = 0x80;
        it++;
        while(it < 56) {
            data[it] = 0x00;
            it++;
        }
    } else {
        data[it] = 0x80;
        it++;
        while(it < 64) {
            data[it] = 0x00;
            it++;
        }
        sha256_transform(state, data);
        for(int i = 0; i < 56; i++) {
            data[i] = 0;
        }
    }
    
    bitlen += datalen * 8;
    data[63] = uint8_t(bitlen);
    data[62] = uint8_t(bitlen >> 8);
    data[61] = uint8_t(bitlen >> 16);
    data[60] = uint8_t(bitlen >> 24);
    data[59] = uint8_t(bitlen >> 32);
    data[58] = uint8_t(bitlen >> 40);
    data[57] = uint8_t(bitlen >> 48);
    data[56] = uint8_t(bitlen >> 56);
    sha256_transform(state, data);
    
    for(int i = 0; i < 4; i++) {
        result[i]      = uint8_t((state[0] >> (24 - i * 8)) & 0x000000ff);
        result[i + 4]  = uint8_t((state[1] >> (24 - i * 8)) & 0x000000ff);
        result[i + 8]  = uint8_t((state[2] >> (24 - i * 8)) & 0x000000ff);
        result[i + 12] = uint8_t((state[3] >> (24 - i * 8)) & 0x000000ff);
        result[i + 16] = uint8_t((state[4] >> (24 - i * 8)) & 0x000000ff);
        result[i + 20] = uint8_t((state[5] >> (24 - i * 8)) & 0x000000ff);
        result[i + 24] = uint8_t((state[6] >> (24 - i * 8)) & 0x000000ff);
        result[i + 28] = uint8_t((state[7] >> (24 - i * 8)) & 0x000000ff);
    }
    
    /*
    result[0] = rotleft(len[0], 5);
    result[60] = (a >> 24) & 0xff;
    result[61] = (a >> 16) & 0xff;
    result[62] = (a >> 8) & 0xff;
    result[63] = (a >> 0) & 0xff;
     */
}
