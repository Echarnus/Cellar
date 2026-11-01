/*
 * Checks app/Shim/cellar-recvtos.c: a received UDP packet's TOS byte reaches Wine labelled IP_TOS.
 *
 * Built and run by Scripts/test-shim.sh, twice:
 *   - linked against the built shim library (CELLAR_TEST_SHIM_LOADED=1): recvmsg() is the shim's,
 *     so a real loopback packet must arrive with an IP_TOS message carrying the byte that was sent;
 *   - without it: on macOS the same packet arrives labelled IP_RECVTOS. That is the behaviour the
 *     shim exists for, so if a future macOS changes it this test says so instead of passing quietly.
 * Both also check the relabelling itself on hand-built control data, with no network.
 */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

int cellar_recvtos_relabel(struct msghdr *msg);

static int failures = 0;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; printf("FAIL: " __VA_ARGS__); printf("\n"); } \
                              else { printf("ok: " __VA_ARGS__); printf("\n"); } } while (0)

static void add_cmsg(struct msghdr *msg, struct cmsghdr **cursor, int level, int type, unsigned char byte)
{
    struct cmsghdr *c = *cursor;
    c->cmsg_level = level;
    c->cmsg_type = type;
    c->cmsg_len = CMSG_LEN(sizeof(unsigned char));
    *CMSG_DATA(c) = byte;
    msg->msg_controllen += CMSG_SPACE(sizeof(unsigned char));
    *cursor = (struct cmsghdr *)((char *)c + CMSG_SPACE(sizeof(unsigned char)));
}

/* The relabelling alone: only IPPROTO_IP/IP_RECVTOS changes, and its byte is kept. */
static void relabels_only_the_tos_message(void)
{
    union { struct cmsghdr align; char buf[256]; } control;
    memset(&control, 0, sizeof(control));
    struct msghdr msg;
    memset(&msg, 0, sizeof(msg));
    msg.msg_control = control.buf;
    struct cmsghdr *cursor = (struct cmsghdr *)control.buf;
    add_cmsg(&msg, &cursor, IPPROTO_IP, IP_TTL, 64);
    add_cmsg(&msg, &cursor, IPPROTO_IP, IP_RECVTOS, 0x2e);
    add_cmsg(&msg, &cursor, IPPROTO_IPV6, IP_RECVTOS, 7);   /* same number, other level */

    int changed = cellar_recvtos_relabel(&msg);
    struct cmsghdr *ttl = CMSG_FIRSTHDR(&msg);
    struct cmsghdr *tos = CMSG_NXTHDR(&msg, ttl);
    struct cmsghdr *v6 = CMSG_NXTHDR(&msg, tos);
    CHECK(changed == 1, "exactly one control message relabelled (got %d)", changed);
    CHECK(ttl->cmsg_type == IP_TTL && *CMSG_DATA(ttl) == 64, "IP_TTL left alone");
    CHECK(tos->cmsg_level == IPPROTO_IP && tos->cmsg_type == IP_TOS, "IP_RECVTOS relabelled IP_TOS (type %d)", tos->cmsg_type);
    CHECK(*CMSG_DATA(tos) == 0x2e && tos->cmsg_len == CMSG_LEN(1), "its TOS byte and length kept");
    CHECK(v6->cmsg_level == IPPROTO_IPV6 && v6->cmsg_type == IP_RECVTOS, "an IPv6 message with the same number left alone");

    struct msghdr empty;
    memset(&empty, 0, sizeof(empty));
    CHECK(cellar_recvtos_relabel(&empty) == 0 && cellar_recvtos_relabel(NULL) == 0, "no control data, nothing done");
}

/* A real packet over loopback, read the way Wine reads it. */
static void real_packet(int shim_loaded)
{
    int rx = socket(AF_INET, SOCK_DGRAM, 0), tx = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t len = sizeof(addr);
    int on = 1, tos = 0x20;
    struct timeval timeout = { 5, 0 };
    if (rx < 0 || tx < 0 || bind(rx, (struct sockaddr *)&addr, sizeof(addr)) != 0
        || getsockname(rx, (struct sockaddr *)&addr, &len) != 0
        || setsockopt(rx, IPPROTO_IP, IP_RECVTOS, &on, sizeof(on)) != 0
        || setsockopt(rx, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) != 0
        || setsockopt(tx, IPPROTO_IP, IP_TOS, &tos, sizeof(tos)) != 0) {
        CHECK(0, "set up a loopback UDP pair with IP_RECVTOS");
        return;
    }
    CHECK(sendto(tx, "x", 1, 0, (struct sockaddr *)&addr, sizeof(addr)) == 1, "sent a packet with TOS 0x20");

    char data[16];
    union { struct cmsghdr align; char buf[256]; } control;
    struct iovec iov = { data, sizeof(data) };
    struct msghdr msg;
    memset(&msg, 0, sizeof(msg));
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = control.buf;
    msg.msg_controllen = sizeof(control.buf);
    CHECK(recvmsg(rx, &msg, 0) == 1, "received it");

    int type = -1, byte = -1;
    for (struct cmsghdr *c = CMSG_FIRSTHDR(&msg); c; c = CMSG_NXTHDR(&msg, c)) {
        if (c->cmsg_level == IPPROTO_IP && (c->cmsg_type == IP_TOS || c->cmsg_type == IP_RECVTOS)) {
            type = c->cmsg_type;
            byte = *CMSG_DATA(c);
        }
    }
#ifdef __APPLE__
    int expected = shim_loaded ? IP_TOS : IP_RECVTOS;
#else
    int expected = IP_TOS;   /* Linux already says IP_TOS; the shim is only ever loaded on macOS */
    (void)shim_loaded;
#endif
    CHECK(type == expected, "the TOS message is labelled %s (got type %d)",
          expected == IP_TOS ? "IP_TOS, the label Wine translates" : "IP_RECVTOS by macOS itself", type);
    CHECK(byte == 0x20, "it carries the byte that was sent (got 0x%x)", byte);
    close(rx);
    close(tx);
}

int main(void)
{
    const char *loaded = getenv("CELLAR_TEST_SHIM_LOADED");
    int shim_loaded = loaded && strcmp(loaded, "1") == 0;
    printf("recvtos-test (%s)\n", shim_loaded ? "through the shim" : "plain libc");
    relabels_only_the_tos_message();
    real_packet(shim_loaded);
    printf("%s\n", failures ? "FAILED" : "passed");
    return failures ? 1 : 0;
}
