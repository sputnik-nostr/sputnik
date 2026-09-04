#include "nostr_secp256k1.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <secp256k1.h>
#include <secp256k1_extrakeys.h>

struct nostr_secp256k1
{
    secp256k1_context* ctx;
};

static int nostr_secure_random(uint8_t* buf, size_t len)
{
    size_t filled = 0;
    while (filled < len)
    {
#if defined(SYS_getrandom)
        long ret = syscall(SYS_getrandom, buf + filled, len - filled, 0);
#else
        long ret = -1;
        errno = ENOSYS;
#endif
        if (ret < 0)
        {
            if (errno == EINTR) continue;
            if (errno != ENOSYS) return 0;
            break;
        }
        filled += (size_t)ret;
    }

    if (filled == len) return 1;

    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) return 0;

    while (filled < len)
    {
        ssize_t ret = read(fd, buf + filled, len - filled);
        if (ret < 0)
        {
            if (errno == EINTR) continue;
            close(fd);
            return 0;
        }
        filled += (size_t)ret;
    }

    close(fd);
    return 1;
}

static void nostr_secure_cleanse(void* ptr, size_t len)
{
    volatile uint8_t* p = (volatile uint8_t*)ptr;
    while (len--) *p++ = 0;
}

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
    int have_seed = nostr_secure_random(seed, sizeof(seed));
    int randomized = have_seed && secp256k1_context_randomize(wrapper->ctx, seed);
    nostr_secure_cleanse(seed, sizeof(seed));

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

    nostr_secure_cleanse(&keypair, sizeof(keypair));
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
        if (!nostr_secure_random(seckey32_out, 32)) return 0;
    } while (!secp256k1_ec_seckey_verify(wrapper->ctx, seckey32_out));

    return nostr_secp256k1_pubkey_from_seckey(wrapper, seckey32_out, pubkey32_out);
}
