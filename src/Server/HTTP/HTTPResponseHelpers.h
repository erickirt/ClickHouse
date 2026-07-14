#pragma once

#include <IO/CompressionMethod.h>
#include <Server/HTTP/HTTPServerRequest.h>
#include <Server/HTTP/WriteBufferFromHTTPServerResponse.h>
#include <base/defines.h>

#include <Poco/String.h>

#include <memory>


namespace DB
{

/// Holds an HTTP response buffer optionally wrapped with a compression
/// layer. Write to get(); finalize get(). The compression layer (if any)
/// will be flushed and the inner buffer finalized automatically.
struct ResponseOutput
{
    std::unique_ptr<WriteBufferFromHTTPServerResponse> response_holder;
    std::unique_ptr<WriteBuffer> compression_holder;

    explicit ResponseOutput(std::unique_ptr<WriteBufferFromHTTPServerResponse> && buf)
        : response_holder(std::move(buf))
    {
    }

    void setCompressedOut(std::unique_ptr<WriteBuffer> && buf)
    {
        chassert(response_holder);
        chassert(!compression_holder);
        compression_holder = std::move(buf);
    }

    WriteBuffer * get() const
    {
        if (compression_holder)
            return compression_holder.get();
        return response_holder.get();
    }
};

/// Advertise that the response varies by the given request header field, merging with
/// any `Vary` value that may already be present (e.g. from configured response headers).
inline void addVaryField(HTTPServerResponse & response, const String & field)
{
    if (!response.has("Vary"))
    {
        response.set("Vary", field);
        return;
    }

    String existing = response.get("Vary");

    /// "*" already means the response varies on everything, so there is nothing to add.
    if (existing == "*")
        return;

    /// Do not add the field twice (header field names are case-insensitive).
    if (Poco::toLower(existing).find(Poco::toLower(field)) != String::npos)
        return;

    response.set("Vary", existing + ", " + field);
}

/// Create a write buffer for an HTTP response, optionally wrapped with
/// compression negotiated from the request's Accept-Encoding header.
///
/// If skip_compression is true (e.g. the response is already compressed),
/// or if Content-Encoding is already set on the response, no compression
/// is applied regardless of the Accept-Encoding header.
inline ResponseOutput responseWriteBuffer(const HTTPServerRequest & request, HTTPServerResponse & response)
{
    ResponseOutput result(std::make_unique<WriteBufferFromHTTPServerResponse>(
        response, request.getMethod() == HTTPRequest::HTTP_HEAD));

    // In case response already has encoding set, then return response raw.
    if (response.has("Content-Encoding"))
        return result;

    /// The representation is content-negotiated on Accept-Encoding, so a shared cache in front of
    /// the server must key on that header to avoid serving one client's variant to another. Emit
    /// this even when we end up not compressing, because the uncompressed variant is still selected
    /// based on Accept-Encoding.
    addVaryField(response, "Accept-Encoding");

    String accept_encoding = request.get("Accept-Encoding", "");
    if (accept_encoding.empty())
        return result;

    CompressionMethod method = chooseHTTPCompressionMethod(accept_encoding);
    if (method == CompressionMethod::None)
        return result;

    response.set("Content-Encoding", toContentEncodingName(method));
    result.setCompressedOut(wrapWriteBufferWithCompressionMethod(
        result.response_holder.get(), method, 1, 0));

    return result;
}

}
