#pragma once

#include "config.h"

namespace Poco::Net { class StreamSocket; }

#if USE_SSL
struct ssl_st;
#endif

namespace DB
{

/// Non-blocking, non-destructive check of whether the remote peer has closed the connection.
///
/// Performs a single `recv(..., MSG_PEEK | MSG_DONTWAIT)` on the file descriptor:
///   - returns true  if the peer performed an orderly shutdown (a FIN was received, so the next
///     read would return 0/EOF) or the socket is in an error state (e.g. RST -> `ECONNRESET`);
///   - returns false if the connection is alive, whether or not there are bytes waiting to be read.
///
/// This is a raw (TLS-unaware) check on the plain socket; on a TLS connection use the
/// `StreamSocket` overload below, which is TLS-aware.
bool isSocketPeerClosed(int fd);

/// Same as above for a Poco socket.
///
/// For a plain socket this checks the underlying file descriptor. For a TLS (`SecureStreamSocket`)
/// socket it uses `SSL_peek` instead, because a raw `MSG_PEEK` cannot tell TLS records apart:
///   - a `poll(SELECT_READ)` + `available()` (`SSL_pending`) check misfires on an unread TLS
///     post-handshake record (a session ticket or `KeyUpdate`), reporting a live connection as
///     closed - the false positive this replaces;
///   - a raw `MSG_PEEK` would misfire the other way, reporting an unread `close_notify` (an orderly
///     TLS shutdown) as live, so the pool would hand out a dead connection.
/// `SSL_peek` decrypts just enough to distinguish real application data and harmless post-handshake
/// messages (alive) from a `close_notify` (closed), without consuming application data.
///
/// Intended for connection-pool reuse checks, where the socket is expected to be idle: a live idle
/// connection returns false, a connection the peer has dropped returns true.
bool isSocketPeerClosed(const Poco::Net::StreamSocket & socket);

#if USE_SSL
/// TLS-aware core of the check, exposed for testing. The socket underlying `ssl` MUST be in
/// non-blocking mode (the caller guarantees this) so that `SSL_peek` cannot block.
///
/// Returns true iff the peer performed an orderly TLS shutdown (`close_notify`) or the SSL
/// connection is otherwise broken; false for a live connection, including one carrying only an
/// unread session ticket / `KeyUpdate`.
bool isSslPeerClosed(ssl_st * ssl);
#endif

}
