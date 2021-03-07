//
//  kernels.metal
//  btcswift
//
//  Created by Antti Salonen on 04/03/2021.
//

#include <metal_stdlib>
using namespace metal;

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

void sha256_transform(thread uint32_t* state,
                      thread const uint8_t* data)
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

void sha256(thread const uint8_t* input,
                   thread uint8_t* result,
                   thread uint32_t* state)
{
    uint8_t data[64];
    for(int i = 0; i < 32; i++) {
        data[i] = input[i];
    }
    
    data[32] = 0x80;
    for(int i = 33; i < 64; i++) {
        data[i] = 0x00;
    }
    data[62] = 0x01; // bitlen = 256 = 0x0100
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
}

void reverse_byte_order(thread uint8_t* input, thread uint8_t* output)
{
    for(int i = 0; i < 4; i++) {
        output[i * 8 + 0] = input[31 - i * 8];
        output[i * 8 + 1] = input[30 - i * 8];
        output[i * 8 + 2] = input[29 - i * 8];
        output[i * 8 + 3] = input[28 - i * 8];
        output[i * 8 + 4] = input[27 - i * 8];
        output[i * 8 + 5] = input[26 - i * 8];
        output[i * 8 + 6] = input[25 - i * 8];
        output[i * 8 + 7] = input[24 - i * 8];
    }
}

kernel void sha256_double(device const uint8_t* input,
                          device const uint32_t* in_state,
                          device const uint32_t* nonce_base,
                          device const uint8_t* target,
                          device uint8_t* result,
                          device uint32_t* nonce_found,
                          uint position [[thread_position_in_grid]])
{
    uint8_t intermediate[32];
    uint8_t final_result[32];
    uint8_t working_input[64];
    uint32_t working_state[8];
    uint32_t my_base = nonce_base[0] + position * 0x100;
    for(int i = 0; i < 64; i++) {
        working_input[i] = input[i];
    }
    for(uint32_t nonce = my_base; nonce < my_base + 0xff; nonce++) {
        working_input[15] = uint8_t((nonce >> 0) & 0xff);
        working_input[14] = uint8_t((nonce >> 8) & 0xff);
        working_input[13] = uint8_t((nonce >> 16) & 0xff);
        working_input[12] = uint8_t((nonce >> 24) & 0xff);
        for(int i = 0; i < 8; i++) {
            working_state[i] = in_state[i];
        }
        sha256_transform(working_state, working_input);
        
        for(int i = 0; i < 4; i++) {
            intermediate[i]      = uint8_t((working_state[0] >> (24 - i * 8)) & 0x000000ff);
            intermediate[i + 4]  = uint8_t((working_state[1] >> (24 - i * 8)) & 0x000000ff);
            intermediate[i + 8]  = uint8_t((working_state[2] >> (24 - i * 8)) & 0x000000ff);
            intermediate[i + 12] = uint8_t((working_state[3] >> (24 - i * 8)) & 0x000000ff);
            intermediate[i + 16] = uint8_t((working_state[4] >> (24 - i * 8)) & 0x000000ff);
            intermediate[i + 20] = uint8_t((working_state[5] >> (24 - i * 8)) & 0x000000ff);
            intermediate[i + 24] = uint8_t((working_state[6] >> (24 - i * 8)) & 0x000000ff);
            intermediate[i + 28] = uint8_t((working_state[7] >> (24 - i * 8)) & 0x000000ff);
        }
        uint32_t real_state[8] = {
            0x6a09e667,
            0xbb67ae85,
            0x3c6ef372,
            0xa54ff53a,
            0x510e527f,
            0x9b05688c,
            0x1f83d9ab,
            0x5be0cd19,
        };
        sha256(intermediate, final_result, real_state);
        int found = 0;
        for(int i = 0; i < 32; i++) {
            if(final_result[31 - i] > target[i])
                break;
            if(final_result[31 - i] < target[i]) {
                found = 1;
                break;
            }
        }
        if(found) {
            nonce_found[0] = nonce;
            for(int i = 0; i < 32; i++) {
                result[i] = final_result[i];
            }
            break;
        }
    }
}

