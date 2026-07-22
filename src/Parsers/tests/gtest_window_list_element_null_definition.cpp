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

/// `definition` is registered as a child (since #110506). When a visitor rewrites that child via
/// `updatePointerToChild`, the `forEachPointerToChild` override must keep the `definition` member in
/// sync with `children[0]`. Consumers read `elem.definition` directly (e.g. QueryTreeBuilder::buildWindow),
/// so a desync would leave them looking at stale state while the null-guard tests above stay green.
TEST(ASTWindowListElement, UpdatePointerToChildKeepsDefinitionInSync)
{
    auto old_def = make_intrusive<ASTWindowDefinition>();
    auto elem = make_intrusive<ASTWindowListElement>();
    elem->name = "w";
    elem->definition = old_def;
    elem->children.push_back(elem->definition);

    ASSERT_EQ(elem->children.size(), 1u);
    ASSERT_EQ(elem->definition.get(), old_def.get());

    /// Mimic a visitor: swap the children[] entry, then sync member pointers via updatePointerToChild.
    /// `old_def` stays alive for the whole test, so old_ptr is never a recycled address.
    auto new_def = make_intrusive<ASTWindowDefinition>();
    const IAST * old_ptr = elem->children[0].get();
    elem->children[0] = new_def;
    elem->updatePointerToChild(old_ptr, new_def);

    EXPECT_EQ(elem->definition.get(), new_def.get());
    EXPECT_EQ(elem->children[0].get(), new_def.get());
    EXPECT_NE(elem->definition.get(), old_def.get());
}
