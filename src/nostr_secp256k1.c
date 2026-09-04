#include "nostr_secp256k1.h"

#include <stdlib.h>

#include <openssl/crypto.h>
#include <openssl/rand.h>

#include <secp256k1.h>
#include <secp256k1_extrakeys.h>

struct nostr_secp256k1
{
    secp256k1_context* ctx;
};

nostr_secp256k1* nostr_secp256k1_create(void)
{
    nostr_secp256k1* wrapper = malloc(sizeof(nostr_secp256k1));
    if (wrapper == NULL) return NULL;

    wrapper->ctx = secp256k1_context_create(SECP256K1_CONTEXT_NONE);
    if (wrapper->ctx == NULL)
    {
        free(wrapper);
        return NULL;
    }

    uint8_t seed[32];
    int have_seed = RAND_bytes(seed, sizeof(seed)) == 1;
    int randomized = have_seed && secp256k1_context_randomize(wrapper->ctx, seed);
    OPENSSL_cleanse(seed, sizeof(seed));

    if (!randomized)
    {
        secp256k1_context_destroy(wrapper->ctx);
        free(wrapper);
        return NULL;
    }

    return wrapper;
}

void nostr_secp256k1_destroy(nostr_secp256k1* wrapper)
{
    if (wrapper == NULL) return;
    secp256k1_context_destroy(wrapper->ctx);
    free(wrapper);
}

int nostr_secp256k1_pubkey_from_seckey(
    nostr_secp256k1* wrapper,
    const uint8_t seckey32[32],
    uint8_t pubkey32_out[32])
{
    if (wrapper == NULL || seckey32 == NULL || pubkey32_out == NULL) return 0;

    secp256k1_keypair keypair;
    secp256k1_xonly_pubkey xonly_pubkey;

    int ok = secp256k1_ec_seckey_verify(wrapper->ctx, seckey32) && secp256k1_keypair_create(wrapper->ctx, &keypair, seckey32) && secp256k1_keypair_xonly_pub(wrapper->ctx, &xonly_pubkey, NULL, &keypair) && secp256k1_xonly_pubkey_serialize(wrapper->ctx, pubkey32_out, &xonly_pubkey);

    OPENSSL_cleanse(&keypair, sizeof(keypair));
    return ok;
}

int nostr_secp256k1_generate_keypair(
    nostr_secp256k1* wrapper,
    uint8_t seckey32_out[32],
    uint8_t pubkey32_out[32])
{
    if (wrapper == NULL || seckey32_out == NULL || pubkey32_out == NULL) return 0;

    do
    {
        if (RAND_bytes(seckey32_out, 32) != 1) return 0;
    } while (!secp256k1_ec_seckey_verify(wrapper->ctx, seckey32_out));

    return nostr_secp256k1_pubkey_from_seckey(wrapper, seckey32_out, pubkey32_out);
}
