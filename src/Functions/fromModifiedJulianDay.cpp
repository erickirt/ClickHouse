#include <Columns/ColumnNullable.h>
#include <Columns/ColumnString.h>
#include <Columns/ColumnVector.h>
#include <Columns/ColumnsNumber.h>
#include <Core/callOnTypeIndex.h>
#include <DataTypes/DataTypeString.h>
#include <DataTypes/DataTypeNullable.h>
#include <DataTypes/DataTypesNumber.h>
#include <DataTypes/IDataType.h>
#include <Functions/IFunction.h>
#include <Functions/FunctionFactory.h>
#include <Functions/GregorianDate.h>
#include <IO/WriteBufferFromVector.h>
#include <IO/WriteHelpers.h>


namespace DB
{

    namespace ErrorCodes
    {
        extern const int ILLEGAL_TYPE_OF_ARGUMENT;
    }

    template <typename Name, typename FromDataType, bool nullOnErrors>
    class ExecutableFunctionFromModifiedJulianDay : public IExecutableFunction
    {
    public:
        String getName() const override
        {
            return Name::name;
        }

        ColumnPtr executeImpl(const ColumnsWithTypeAndName & arguments, const DataTypePtr &, size_t input_rows_count) const override
        {
            using ColVecType = typename FromDataType::ColumnType;
            const ColVecType & col_from = checkAndGetColumn<ColVecType>(*arguments[0].column);
            const typename ColVecType::Container & vec_from = col_from.getData();

            auto col_to = ColumnString::create();
            ColumnString::Chars & data_to = col_to->getChars();
            ColumnString::Offsets & offsets_to = col_to->getOffsets();
            data_to.resize(input_rows_count * strlen("YYYY-MM-DD") + 1);
            offsets_to.resize(input_rows_count);

            ColumnUInt8::MutablePtr col_null_map_to;
            ColumnUInt8::Container * vec_null_map_to [[maybe_unused]] = nullptr;
            if constexpr (nullOnErrors)
            {
                col_null_map_to = ColumnUInt8::create(input_rows_count);
                vec_null_map_to = &col_null_map_to->getData();
            }

            WriteBufferFromVector<ColumnString::Chars> write_buffer(data_to);
            for (size_t i = 0; i < input_rows_count; ++i)
            {
                if constexpr (nullOnErrors)
                {
                    GregorianDate gd;
                    (*vec_null_map_to)[i] = !(gd.tryInit(vec_from[i]) && gd.tryWrite(write_buffer));
                    writeChar(0, write_buffer);
                    offsets_to[i] = write_buffer.count();
                }
                else
                {
                    GregorianDate gd(vec_from[i]);
                    gd.write(write_buffer);
                    writeChar(0, write_buffer);
                    offsets_to[i] = write_buffer.count();
                }
            }
            write_buffer.finalize();

            if constexpr (nullOnErrors)
                return ColumnNullable::create(std::move(col_to), std::move(col_null_map_to));
            else
                return col_to;
        }

        bool useDefaultImplementationForConstants() const override
        {
            return true;
        }
    };

    template <typename Name, typename FromDataType, bool nullOnErrors>
    class FunctionBaseFromModifiedJulianDay : public IFunctionBase
    {
    public:
        explicit FunctionBaseFromModifiedJulianDay(DataTypes argument_types_, DataTypePtr return_type_)
            : argument_types(std::move(argument_types_))
            , return_type(std::move(return_type_)) {}

        String getName() const override
        {
            return Name::name;
        }

        const DataTypes & getArgumentTypes() const override
        {
            return argument_types;
        }

        const DataTypePtr & getResultType() const override
        {
            return return_type;
        }

        ExecutableFunctionPtr prepare(const ColumnsWithTypeAndName &) const override
        {
            return std::make_unique<ExecutableFunctionFromModifiedJulianDay<Name, FromDataType, nullOnErrors>>();
        }

        bool isInjective(const ColumnsWithTypeAndName &) const override
        {
            return true;
        }

        bool isSuitableForShortCircuitArgumentsExecution(const DataTypesWithConstInfo & /*arguments*/) const override
        {
            return true;
        }

        bool hasInformationAboutMonotonicity() const override
        {
            return true;
        }

        Monotonicity getMonotonicityForRange(const IDataType &, const Field &, const Field &) const override
        {
            return { .is_monotonic = true, .is_always_monotonic = true, .is_strict = true, };
        }

    private:
        DataTypes argument_types;
        DataTypePtr return_type;
    };

    template <typename Name, bool nullOnErrors>
    class FromModifiedJulianDayOverloadResolver : public IFunctionOverloadResolver
    {
    public:
        static constexpr auto name = Name::name;

        static FunctionOverloadResolverPtr create(ContextPtr)
        {
            return std::make_unique<FromModifiedJulianDayOverloadResolver<Name, nullOnErrors>>();
        }

        String getName() const override
        {
            return Name::name;
        }

        FunctionBasePtr buildImpl(const ColumnsWithTypeAndName & arguments, const DataTypePtr & return_type) const override
        {
            DataTypes argument_types = { arguments[0].type };
            const DataTypePtr & from_type_not_null = removeNullable(arguments[0].type);

            FunctionBasePtr base;
            auto call = [&](const auto & types) -> bool
            {
                using Types = std::decay_t<decltype(types)>;
                using FromIntType = typename Types::RightType;
                using FromDataType = DataTypeNumber<FromIntType>;

                base = std::make_unique<FunctionBaseFromModifiedJulianDay<Name, FromDataType, nullOnErrors>>(argument_types, return_type);
                return true;
            };
            bool built = callOnBasicType<void, true, false, false, false>(from_type_not_null->getTypeId(), call);
            if (built)
                return base;

            /* When the argument is a NULL constant, the resulting
                * function base will not be actually called but it
                * will still be inspected. Returning a NULL pointer
                * here causes a SEGV. So we must somehow create a
                * dummy implementation and return it.
                */
            if (WhichDataType(from_type_not_null).isNothing()) // Nullable(Nothing)
                return std::make_unique<FunctionBaseFromModifiedJulianDay<Name, DataTypeInt32, nullOnErrors>>(argument_types, return_type);
            // Should not happen.
            throw Exception(ErrorCodes::ILLEGAL_TYPE_OF_ARGUMENT, "The argument of function {} must be integral", getName());
        }

        DataTypePtr getReturnTypeImpl(const DataTypes & arguments) const override
        {
            if (!isInteger(arguments[0]))
            {
                throw Exception(ErrorCodes::ILLEGAL_TYPE_OF_ARGUMENT, "The argument of function {} must be integral", getName());
            }

            DataTypePtr base_type = std::make_shared<DataTypeString>();
            if constexpr (nullOnErrors)
                return std::make_shared<DataTypeNullable>(base_type);
            else
                return base_type;
        }

        size_t getNumberOfArguments() const override
        {
            return 1;
        }

        bool isInjective(const ColumnsWithTypeAndName &) const override
        {
            return true;
        }
    };

    struct NameFromModifiedJulianDay
    {
        static constexpr auto name = "fromModifiedJulianDay";
    };

    struct NameFromModifiedJulianDayOrNull
    {
        static constexpr auto name = "fromModifiedJulianDayOrNull";
    };

    REGISTER_FUNCTION(FromModifiedJulianDay)
    {
        FunctionDocumentation::Description description_fromModifiedJulianDay = R"(
Converts a [Modified Julian Day](https://en.wikipedia.org/wiki/Julian_day#Variants) number to a [Proleptic Gregorian calendar](https://en.wikipedia.org/wiki/Proleptic_Gregorian_calendar) date in text form `YYYY-MM-DD`. This function supports day number from `-678941` to `2973483` (which represent 0000-01-01 and 9999-12-31 respectively). It raises an exception if the day number is outside of the supported range.
    )";
        FunctionDocumentation::Syntax syntax_fromModifiedJulianDay = R"(
fromModifiedJulianDay(day)
    )";
        FunctionDocumentation::Arguments arguments_fromModifiedJulianDay = {{"day", "Modified Julian Day number.", {"(U)Int*"}}};
        FunctionDocumentation::ReturnedValue returned_value_fromModifiedJulianDay = {"Returns date in text form.", {"String"}};
        FunctionDocumentation::Examples examples_fromModifiedJulianDay =
        {
            {"Convert Modified Julian Day to date", R"(
SELECT fromModifiedJulianDay(58849)
        )",
            R"(
┌─fromModifiedJulianDay(58849)─┐
│ 2020-01-01                   │
└──────────────────────────────┘
        )"}
        };
        FunctionDocumentation::IntroducedIn introduced_in_fromModifiedJulianDay = {21, 1};
        FunctionDocumentation::Category category_fromModifiedJulianDay = FunctionDocumentation::Category::DateAndTime;
        FunctionDocumentation documentation_fromModifiedJulianDay = {description_fromModifiedJulianDay, syntax_fromModifiedJulianDay, arguments_fromModifiedJulianDay, returned_value_fromModifiedJulianDay, examples_fromModifiedJulianDay, introduced_in_fromModifiedJulianDay, category_fromModifiedJulianDay};

        factory.registerFunction<FromModifiedJulianDayOverloadResolver<NameFromModifiedJulianDay, false>>(documentation_fromModifiedJulianDay);

        FunctionDocumentation::Description description_fromModifiedJulianDayOrNull = R"(
Similar to [`fromModifiedJulianDay()`](#frommodifiedjulianday), but instead of raising exceptions it returns `NULL`.
    )";
        FunctionDocumentation::Syntax syntax_fromModifiedJulianDayOrNull = R"(
fromModifiedJulianDayOrNull(day)
    )";
        FunctionDocumentation::Arguments arguments_fromModifiedJulianDayOrNull = {{"day", "Modified Julian Day number.", {"(U)Int*"}}};
        FunctionDocumentation::ReturnedValue returned_value_fromModifiedJulianDayOrNull = {"Returns date in text form for valid `day` argument, otherwise `null`.", {"Nullable(String)"}};
        FunctionDocumentation::Examples examples_fromModifiedJulianDayOrNull =
        {
            {"Convert Modified Julian Day to date with null handling", R"(
SELECT fromModifiedJulianDayOrNull(58849);
SELECT fromModifiedJulianDayOrNull(60000000); -- invalid argument, returns NULL
        )",
            R"(
┌─fromModified⋯Null(58849)─┐
│ 2020-01-01               │
└──────────────────────────┘
┌─fromModified⋯l(60000000)─┐
│ ᴺᵁᴸᴸ                     │
└──────────────────────────┘
        )"}
        };
        FunctionDocumentation::IntroducedIn introduced_in_fromModifiedJulianDayOrNull = {21, 1};
        FunctionDocumentation::Category category_fromModifiedJulianDayOrNull = FunctionDocumentation::Category::DateAndTime;
        FunctionDocumentation documentation_fromModifiedJulianDayOrNull = {description_fromModifiedJulianDayOrNull, syntax_fromModifiedJulianDayOrNull, arguments_fromModifiedJulianDayOrNull, returned_value_fromModifiedJulianDayOrNull, examples_fromModifiedJulianDayOrNull, introduced_in_fromModifiedJulianDayOrNull, category_fromModifiedJulianDayOrNull};

        factory.registerFunction<FromModifiedJulianDayOverloadResolver<NameFromModifiedJulianDayOrNull, true>>(documentation_fromModifiedJulianDayOrNull);
    }
}
