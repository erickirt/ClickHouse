#include <gtest/gtest.h>

#include <IO/CompressionMethod.h>

using namespace DB;

TEST(ChooseHTTPCompressionMethod, PrefersServerOrder)
{
    EXPECT_EQ(chooseHTTPCompressionMethod("zstd, gzip, br"), CompressionMethod::Zstd);
    EXPECT_EQ(chooseHTTPCompressionMethod("br, gzip"), CompressionMethod::Brotli);
    EXPECT_EQ(chooseHTTPCompressionMethod("gzip"), CompressionMethod::Gzip);
}

TEST(ChooseHTTPCompressionMethod, SkipsZeroQValue)
{
    EXPECT_EQ(chooseHTTPCompressionMethod("br;q=0, gzip"), CompressionMethod::Gzip);
    EXPECT_EQ(chooseHTTPCompressionMethod("zstd;q=0"), CompressionMethod::None);
    EXPECT_EQ(chooseHTTPCompressionMethod("gzip;q=0.0"), CompressionMethod::None);
    EXPECT_EQ(chooseHTTPCompressionMethod("zstd;q=0, br;q=0.000"), CompressionMethod::None);
}

TEST(ChooseHTTPCompressionMethod, HandlesDefaultQValue)
{
    EXPECT_EQ(chooseHTTPCompressionMethod("gzip;q=0.5, zstd"), CompressionMethod::Zstd);
    EXPECT_EQ(chooseHTTPCompressionMethod("zstd;q=0.1, br;q=1"), CompressionMethod::Zstd);
}

TEST(ChooseHTTPCompressionMethod, NoSubstringFalsePositives)
{
    EXPECT_EQ(chooseHTTPCompressionMethod("X-gzip-custom"), CompressionMethod::None);
    EXPECT_EQ(chooseHTTPCompressionMethod("my-br-extra, gzip"), CompressionMethod::Gzip);
}

TEST(ChooseHTTPCompressionMethod, IgnoresWhitespace)
{
    EXPECT_EQ(chooseHTTPCompressionMethod("  gzip, zstd  "), CompressionMethod::Zstd);
    EXPECT_EQ(chooseHTTPCompressionMethod("zstd; q=0, gzip ; q=1"), CompressionMethod::Gzip);
}

TEST(ChooseHTTPCompressionMethod, Empty)
{
    EXPECT_EQ(chooseHTTPCompressionMethod(""), CompressionMethod::None);
}
