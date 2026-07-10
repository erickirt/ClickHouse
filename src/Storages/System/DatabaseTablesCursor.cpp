#include <Storages/System/DatabaseTablesCursor.h>

#include <Columns/IColumn.h>
#include <Databases/IDatabase.h>
#include <Interpreters/DatabaseCatalog.h>
#include <base/defines.h>

namespace DB
{

DatabaseTablesCursor::DatabaseTablesCursor(ColumnPtr database_names_)
    : database_names(std::move(database_names_))
{
}

DatabaseTablesCursor::~DatabaseTablesCursor() = default;

bool DatabaseTablesCursor::advanceToDatabase()
{
    /// Consume the exhausted iterator, otherwise it could advance the position twice.
    if (tables_it && !tables_it->isValid())
        advancePastDatabase();

    /// A valid iterator means the previous block ended mid-database; stay on it.
    if (tables_it)
        return true;

    while (database_idx < database_names->size())
    {
        database_name = database_names->getDataAt(database_idx);
        database = DatabaseCatalog::instance().tryGetDatabase(database_name);
        if (database)
            return true;

        /// Database was deleted just now or the user has no access.
        ++database_idx;
    }
    return false;
}

void DatabaseTablesCursor::advancePastDatabase()
{
    ++database_idx;
    tables_it.reset();
}

void DatabaseTablesCursor::setTablesIterator(DatabaseTablesIteratorPtr tables_it_)
{
    chassert(database && !tables_it);
    tables_it = std::move(tables_it_);
}

IDatabaseTablesIterator & DatabaseTablesCursor::getTablesIterator() const
{
    chassert(tables_it);
    return *tables_it;
}

}
