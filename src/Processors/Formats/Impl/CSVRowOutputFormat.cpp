#include <Processors/Formats/Impl/CSVRowOutputFormat.h>

#include <DataTypes/Serializations/ISerialization.h>
#include <Formats/FormatFactory.h>
#include <Formats/registerWithNamesAndTypes.h>
#include <IO/WriteHelpers.h>
#include <Processors/Port.h>

namespace DB
{


CSVRowOutputFormat::CSVRowOutputFormat(WriteBuffer & out_, SharedHeader header_, bool with_names_, bool with_types_, const FormatSettings & format_settings_)
    : IRowOutputFormat(header_, out_), with_names(with_names_), with_types(with_types_), format_settings(format_settings_)
{
    const auto & sample = getPort(PortKind::Main).getHeader();
    size_t columns = sample.columns();
    data_types.resize(columns);
    for (size_t i = 0; i < columns; ++i)
        data_types[i] = sample.safeGetByPosition(i).type;
}

void CSVRowOutputFormat::writeLine(const std::vector<String> & values)
{
    for (size_t i = 0; i < values.size(); ++i)
    {
        writeCSVString(values[i], out);
        if (i + 1 != values.size())
            writeFieldDelimiter();
    }
    writeRowEndDelimiter();
}

void CSVRowOutputFormat::writePrefix()
{
    const auto & sample = getPort(PortKind::Main).getHeader();

    if (with_names)
        writeLine(sample.getNames());

    if (with_types)
        writeLine(sample.getDataTypeNames());
}


void CSVRowOutputFormat::writeField(const IColumn & column, const ISerialization & serialization, size_t row_num)
{
    serialization.serializeTextCSV(column, row_num, out, format_settings);
}


void CSVRowOutputFormat::writeFieldDelimiter()
{
    writeChar(format_settings.csv.delimiter, out);
}


void CSVRowOutputFormat::writeRowEndDelimiter()
{
    if (format_settings.csv.crlf_end_of_line)
        writeChar('\r', out);
    writeChar('\n', out);
}

void CSVRowOutputFormat::writeBeforeTotals()
{
    writeChar('\n', out);
}

void CSVRowOutputFormat::writeBeforeExtremes()
{
    writeChar('\n', out);
}


void registerOutputFormatCSV(FormatFactory & factory)
{
    auto register_func = [&](const String & format_name, bool with_names, bool with_types)
    {
        factory.registerOutputFormat(format_name, [with_names, with_types](
                   WriteBuffer & buf,
                   const Block & sample,
                   const FormatSettings & format_settings)
        {
            return std::make_shared<CSVRowOutputFormat>(buf, std::make_shared<const Block>(sample), with_names, with_types, format_settings);
        });
        factory.markOutputFormatSupportsParallelFormatting(format_name);
        /// https://www.iana.org/assignments/media-types/text/csv
        factory.setContentType(format_name, String("text/csv; charset=UTF-8; header=") + (with_names ? "present" : "absent"));
    };

    registerWithNamesAndTypes("CSV", register_func);
}

}
