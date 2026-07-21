#include <gtest/gtest.h>

#include <Parsers/ASTWindowDefinition.h>
#include <Common/Exception.h>
#include <IO/WriteBufferFromString.h>
#include <IO/Operators.h>

using namespace DB;

/// `ASTWindowListElement::definition` is a required child. If a malformed tree leaves it null,
/// clone() and formatImpl() must throw UNEXPECTED_AST_STRUCTURE instead of dereferencing it.

TEST(ASTWindowListElement, CloneWithNullDefinitionThrowsInsteadOfCrashing)
{
    auto elem = make_intrusive<ASTWindowListElement>();
    elem->name = "w";
    ASSERT_EQ(elem->definition, nullptr);

    EXPECT_THROW(elem->clone(), DB::Exception);

    WriteBufferFromOwnString buf;
    EXPECT_THROW(elem->format(buf, IAST::FormatSettings(/*one_line=*/true)), DB::Exception);
}

TEST(ASTWindowListElement, CloneWithDefinitionRoundTrips)
{
    auto def = make_intrusive<ASTWindowDefinition>();
    auto elem = make_intrusive<ASTWindowListElement>();
    elem->name = "w";
    elem->definition = def;
    elem->children.push_back(elem->definition);

    ASTPtr cloned = elem->clone();
    const auto & cloned_elem = cloned->as<const ASTWindowListElement &>();
    EXPECT_EQ(cloned_elem.name, "w");
    ASSERT_NE(cloned_elem.definition, nullptr);
    ASSERT_EQ(cloned_elem.children.size(), 1u);
    EXPECT_EQ(cloned_elem.children[0].get(), cloned_elem.definition.get());

    WriteBufferFromOwnString buf;
    elem->format(buf, IAST::FormatSettings(/*one_line=*/true));
    EXPECT_EQ(buf.str(), "w AS ()");
}
