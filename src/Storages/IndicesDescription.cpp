#include <Interpreters/ExpressionAnalyzer.h>
#include <Interpreters/ExpressionActions.h>
#include <Interpreters/TreeRewriter.h>
#include <Storages/IndicesDescription.h>

#include <Parsers/ASTFunction.h>
#include <Parsers/ASTIdentifier.h>
#include <Parsers/ASTIndexDeclaration.h>
#include <Parsers/ASTLiteral.h>
#include <Parsers/ParserCreateQuery.h>
#include <Parsers/parseQuery.h>
#include <Storages/extractKeyExpressionList.h>

#include <Storages/ReplaceAliasByExpressionVisitor.h>

#include <Core/Defines.h>
#include <Common/Exception.h>


namespace DB
{
namespace ErrorCodes
{
    extern const int INCORRECT_QUERY;
    extern const int LOGICAL_ERROR;
}

namespace
{
using ReplaceAliasToExprVisitor = InDepthNodeVisitor<ReplaceAliasByExpressionMatcher, true>;


Tuple parseGinIndexArgumentFromAST(const ASTPtr & arguments)
{
    const auto & identifier = arguments->children[0]->template as<ASTIdentifier>();
    if (identifier == nullptr)
        throw Exception(ErrorCodes::INCORRECT_QUERY, "Expected identifier");

    const auto & literal = arguments->children[1]->template as<ASTLiteral>();
    if (literal == nullptr)
        throw Exception(ErrorCodes::INCORRECT_QUERY, "Expected literal");

    Tuple key_value_pair{};
    key_value_pair.emplace_back(identifier->name());
    key_value_pair.emplace_back(literal->value);
    return key_value_pair;
}

bool parseGinIndexArgumentsFromAST(const ASTPtr & arguments, FieldVector & parsed_arguments)
{
    parsed_arguments.reserve(arguments->children.size());

    for (const auto & argument : arguments->children)
    {
        if (const auto * ast_function = argument->template as<ASTFunction>();
            ast_function && ast_function->name == "equals" && ast_function->arguments->children.size() == 2)
        {
            parsed_arguments.emplace_back(parseGinIndexArgumentFromAST(ast_function->arguments));
        }
        else
        {
            if (!parsed_arguments.empty())
                throw Exception(ErrorCodes::INCORRECT_QUERY, "Cannot mix key-value pair and single argument as GIN index arguments");
            return false;
        }
    }

    return true;
}
}

IndexDescription::IndexDescription(const IndexDescription & other)
    : definition_ast(other.definition_ast ? other.definition_ast->clone() : nullptr)
    , expression_list_ast(other.expression_list_ast ? other.expression_list_ast->clone() : nullptr)
    , name(other.name)
    , type(other.type)
    , arguments(other.arguments)
    , column_names(other.column_names)
    , data_types(other.data_types)
    , sample_block(other.sample_block)
    , granularity(other.granularity)
{
    if (other.expression)
        expression = other.expression->clone();
}


IndexDescription & IndexDescription::operator=(const IndexDescription & other)
{
    if (&other == this)
        return *this;

    if (other.definition_ast)
        definition_ast = other.definition_ast->clone();
    else
        definition_ast.reset();

    if (other.expression_list_ast)
        expression_list_ast = other.expression_list_ast->clone();
    else
        expression_list_ast.reset();

    name = other.name;
    type = other.type;

    if (other.expression)
        expression = other.expression->clone();
    else
        expression.reset();

    arguments = other.arguments;
    column_names = other.column_names;
    data_types = other.data_types;
    sample_block = other.sample_block;
    granularity = other.granularity;
    return *this;
}

IndexDescription IndexDescription::getIndexFromAST(const ASTPtr & definition_ast, const ColumnsDescription & columns, ContextPtr context)
{
    const auto * index_definition = definition_ast->as<ASTIndexDeclaration>();
    if (!index_definition)
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Cannot create skip index from non ASTIndexDeclaration AST");

    if (index_definition->name.empty())
        throw Exception(ErrorCodes::INCORRECT_QUERY, "Skip index must have name in definition.");

    auto index_type = index_definition->getType();
    if (!index_type)
        throw Exception(ErrorCodes::INCORRECT_QUERY, "TYPE is required for index");

    if (index_type->parameters && !index_type->parameters->children.empty())
        throw Exception(ErrorCodes::INCORRECT_QUERY, "Index type cannot have parameters");

    IndexDescription result;
    result.definition_ast = index_definition->clone();
    result.name = index_definition->name;
    result.type = Poco::toLower(index_type->name);
    result.granularity = index_definition->granularity;

    ASTPtr expr_list;
    if (auto index_expression = index_definition->getExpression())
    {
        expr_list = extractKeyExpressionList(index_expression);

        ReplaceAliasToExprVisitor::Data data{columns};
        ReplaceAliasToExprVisitor{data}.visit(expr_list);

        result.expression_list_ast = expr_list->clone();
    }
    else
    {
        throw Exception(ErrorCodes::LOGICAL_ERROR, "Expression is not set");
    }

    auto syntax = TreeRewriter(context).analyze(expr_list, columns.get(GetColumnsOptions(GetColumnsOptions::AllPhysical).withSubcolumns()));
    result.expression = ExpressionAnalyzer(expr_list, syntax, context).getActions(true);
    result.sample_block = result.expression->getSampleBlock();

    for (auto & elem : result.sample_block)
    {
        if (!elem.column)
            elem.column = elem.type->createColumn();

        result.column_names.push_back(elem.name);
        result.data_types.push_back(elem.type);
    }

    if (index_type && index_type->arguments)
    {
        bool is_text_index = index_type->name == "text";
        bool is_legacy_text_index = index_type->name == "gin" || index_type->name == "inverted" || index_type->name == "full_text";
        if ((is_text_index || is_legacy_text_index) && parseGinIndexArgumentsFromAST(index_type->arguments, result.arguments))
            return result;

        for (size_t i = 0; i < index_type->arguments->children.size(); ++i)
        {
            const auto & child = index_type->arguments->children[i];
            if (const auto * ast_literal = child->as<ASTLiteral>(); ast_literal != nullptr)
                /// E.g. INDEX index_name column_name TYPE vector_similarity('hnsw', 'f32')
                result.arguments.emplace_back(ast_literal->value);
            else if (const auto * ast_identifier = child->as<ASTIdentifier>(); ast_identifier != nullptr)
                /// E.g. INDEX index_name column_name TYPE vector_similarity(hnsw, f32)
                result.arguments.emplace_back(ast_identifier->name());
            else
                throw Exception(ErrorCodes::INCORRECT_QUERY, "Only literals can be skip index arguments");
        }
    }

    return result;
}

void IndexDescription::recalculateWithNewColumns(const ColumnsDescription & new_columns, ContextPtr context)
{
    *this = getIndexFromAST(definition_ast, new_columns, context);
}

bool IndicesDescription::has(const String & name) const
{
    for (const auto & index : *this)
        if (index.name == name)
            return true;
    return false;
}

bool IndicesDescription::hasType(const String & type) const
{
    for (const auto & index : *this)
        if (index.type == type)
            return true;
    return false;
}

String IndicesDescription::toString() const
{
    if (empty())
        return {};

    ASTExpressionList list;
    for (const auto & index : *this)
        list.children.push_back(index.definition_ast);

    return list.formatWithSecretsOneLine();
}


IndicesDescription IndicesDescription::parse(const String & str, const ColumnsDescription & columns, ContextPtr context)
{
    IndicesDescription result;
    if (str.empty())
        return result;

    ParserIndexDeclarationList parser;
    ASTPtr list = parseQuery(parser, str, 0, DBMS_DEFAULT_MAX_PARSER_DEPTH, DBMS_DEFAULT_MAX_PARSER_BACKTRACKS);

    for (const auto & index : list->children)
        result.emplace_back(IndexDescription::getIndexFromAST(index, columns, context));

    return result;
}


ExpressionActionsPtr IndicesDescription::getSingleExpressionForIndices(const ColumnsDescription & columns, ContextPtr context) const
{
    ASTPtr combined_expr_list = std::make_shared<ASTExpressionList>();
    for (const auto & index : *this)
        for (const auto & index_expr : index.expression_list_ast->children)
            combined_expr_list->children.push_back(index_expr->clone());

    auto syntax_result = TreeRewriter(context).analyze(combined_expr_list, columns.get(GetColumnsOptions(GetColumnsOptions::AllPhysical).withSubcolumns()));
    return ExpressionAnalyzer(combined_expr_list, syntax_result, context).getActions(false);
}

Names IndicesDescription::getAllRegisteredNames() const
{
    Names result;
    for (const auto & index : *this)
    {
        result.emplace_back(index.name);
    }
    return result;
}
}
