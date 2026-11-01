/*
 * cellar-recvtos — hands Wine the TOS byte of a received UDP packet in the shape Wine expects.
 *
 * Steam's networking (SteamNetworkingSockets, inside steam.exe and inside every game that loads
 * steamclient) asks Windows for each UDP packet's TOS byte: it sets IP_RECVTOS on the socket and
 * reads the IP_TOS control message WSARecvMsg returns. If the socket option succeeded and no such
 * message arrives, it asserts — "No control data returned even though we asked for TOS?" — and
 * Steam's error reporter comes up over the game.
 *
 * Wine forwards IP_RECVTOS to the host and translates what comes back, but its translation only
 * knows Linux's spelling: Linux labels the received TOS byte `IP_TOS`. macOS (like the BSDs) labels
 * it `IP_RECVTOS`, so Wine's ntdll logs "Unhandled IPPROTO_IP message header type 27" and drops it,
 * and Steam asserts. Valve's own code spells out the same difference for its native Mac build.
 *
 * Wine reads received packets with the host's recvmsg(), so this file interposes recvmsg() and
 * relabels that one control message to the Linux spelling Wine handles. The payload is already the
 * same — one unsigned byte on both systems, and Wine's IP_TOS branch reads one unsigned byte — so
 * only the type changes. Nothing else is touched: no other message, no other level, no other call.
 *
 * It is part of the Dock shim's library because that library is already inserted into every Wine
 * process Cellar starts for a game (Steam's to keep it out of the Dock, the game's to give it its
 * name), not because it has anything to do with the Dock. It does not read the shim's variables and
 * does not depend on them: in any process the library is in, received TOS bytes reach Wine.
 */

#include <stddef.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>

/* Relabel every IPPROTO_IP/IP_RECVTOS control message in `msg` as IP_TOS. Returns how many it
 * changed. Exposed (not static) so app/tests/Shim can check it without a network. */
int cellar_recvtos_relabel(struct msghdr *msg)
{
    int changed = 0;
#if defined(IP_RECVTOS) && defined(IP_TOS) && IP_RECVTOS != IP_TOS
    if (!msg || !msg->msg_control || msg->msg_controllen < sizeof(struct cmsghdr)) return 0;
    for (struct cmsghdr *cmsg = CMSG_FIRSTHDR(msg); cmsg; cmsg = CMSG_NXTHDR(msg, cmsg)) {
        if (cmsg->cmsg_level == IPPROTO_IP && cmsg->cmsg_type == IP_RECVTOS) {
            cmsg->cmsg_type = IP_TOS;
            changed++;
        }
    }
#else
    (void)msg;
#endif
    return changed;
}

#if defined(__APPLE__) && !defined(CELLAR_RECVTOS_NO_INTERPOSE)
/* dyld's interposing: every image in the process that calls recvmsg() — Wine's ntdll.so above all,
 * which is loaded long after this library — calls cellar_recvmsg instead, and the call below from
 * inside this library still reaches the real one. */
static ssize_t cellar_recvmsg(int fd, struct msghdr *msg, int flags)
{
    ssize_t received = recvmsg(fd, msg, flags);
    if (received >= 0 && msg && msg->msg_controllen > 0) cellar_recvtos_relabel(msg);
    return received;
}

__attribute__((used)) static const struct { const void *replacement; const void *replacee; }
cellar_recvmsg_interpose __attribute__((section("__DATA,__interpose"))) = {
    (const void *)cellar_recvmsg, (const void *)recvmsg
};
#endif
