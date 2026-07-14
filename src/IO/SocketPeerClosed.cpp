#include <IO/SocketPeerClosed.h>

#include <Poco/Net/StreamSocket.h>
#include <Poco/Net/SocketImpl.h>

#include <sys/socket.h>
#include <cerrno>

#if USE_SSL
#include <Poco/Net/SecureStreamSocketImpl.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <fcntl.h>
#endif

namespace DB
{

bool isSocketPeerClosed(int fd)
{
    if (fd < 0)
        return true;

    char c = 0;
    ssize_t res = 0;
    do
        res = ::recv(fd, &c, 1, MSG_PEEK | MSG_DONTWAIT);
    while (res < 0 && errno == EINTR);

    if (res > 0)
        return false;   /// Bytes are waiting: the peer is alive.
    if (res == 0)
        return true;    /// Orderly shutdown: the peer sent a FIN, the next read would return EOF.

    /// res < 0
    if (errno == EAGAIN || errno == EWOULDBLOCK)
        return false;   /// Nothing to read and no FIN: a healthy idle connection.
    return true;        /// Any other error (e.g. ECONNRESET): treat as closed/broken.
}

#if USE_SSL

bool isSslPeerClosed(ssl_st * ssl)
{
    /// `SSL_peek` decrypts just enough of the pending records to tell real application data and
    /// harmless post-handshake messages (session tickets, `KeyUpdate`) apart from a `close_notify`.
    /// It does not consume application data. The socket is non-blocking, so this never blocks.
    ///
    /// The error queue must be empty before the call for `SSL_get_error` to be meaningful.
    ERR_clear_error();
    char c = 0;
    int res = SSL_peek(ssl, &c, 1);
    if (res > 0)
        return false;   /// Application data is waiting: the peer is alive.

    switch (SSL_get_error(ssl, res))
    {
        case SSL_ERROR_WANT_READ:  [[fallthrough]];
        case SSL_ERROR_WANT_WRITE:
            /// No application data is pending. Any session ticket / `KeyUpdate` on the wire was
            /// processed by `SSL_peek` without surfacing as data: a healthy idle connection.
            return false;
        case SSL_ERROR_ZERO_RETURN:
            return true;    /// The peer sent `close_notify`: an orderly TLS shutdown.
        default:
            /// A FIN without `close_notify` (`SSL_ERROR_SYSCALL`), a protocol error (`SSL_ERROR_SSL`),
            /// or anything else: treat as closed/broken.
            return true;
    }
}

namespace
{

/// Force the socket into non-blocking mode for the duration of a call, restoring the original
/// flags afterwards, so that `SSL_peek` on an idle pooled connection can never block.
class ScopedNonBlocking
{
public:
    explicit ScopedNonBlocking(int fd_) : fd(fd_), flags(::fcntl(fd_, F_GETFL, 0))
    {
        if (flags >= 0 && !(flags & O_NONBLOCK))
            ::fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }

    ~ScopedNonBlocking()
    {
        if (flags >= 0 && !(flags & O_NONBLOCK))
            ::fcntl(fd, F_SETFL, flags);
    }

    ScopedNonBlocking(const ScopedNonBlocking &) = delete;
    ScopedNonBlocking & operator=(const ScopedNonBlocking &) = delete;

private:
    int fd;
    int flags;
};

}

#endif

bool isSocketPeerClosed(const Poco::Net::StreamSocket & socket)
{
#if USE_SSL
    if (auto * secure = dynamic_cast<Poco::Net::SecureStreamSocketImpl *>(socket.impl()))
    {
        /// A connected secure socket has a live `SSL` object; the null case (handshake not yet
        /// performed) has no TLS state to inspect, so fall back to the raw file-descriptor check.
        if (auto * ssl = secure->ssl())
        {
            ScopedNonBlocking non_blocking(secure->sockfd());
            return isSslPeerClosed(ssl);
        }
    }
#endif
    return isSocketPeerClosed(socket.impl()->sockfd());
}

}
