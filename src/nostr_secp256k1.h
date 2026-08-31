#pragma once

#include <stdint.h>

typedef struct nostr_secp256k1 nostr_secp256k1;

nostr_secp256k1* nostr_secp256k1_create(void);

void nostr_secp256k1_destroy(nostr_secp256k1* wrapper);

int nostr_secp256k1_pubkey_from_seckey(
    nostr_secp256k1* wrapper,
    const uint8_t seckey32[32],
    uint8_t pubkey32_out[32]);

int nostr_secp256k1_generate_keypair(
    nostr_secp256k1* wrapper,
    uint8_t seckey32_out[32],
    uint8_t pubkey32_out[32]);
