#pragma once

#include "CatBoostLibraryHandler.h"

#include <base/defines.h>
#include <Common/ExternalModelInfo.h>

#include <mutex>
#include <unordered_map>

namespace Poco
{
class Logger;
}


namespace DB
{

using LoggerPtr = std::shared_ptr<Poco::Logger>;

class CatBoostLibraryHandlerFactory final : private boost::noncopyable
{
public:
    static CatBoostLibraryHandlerFactory & instance();

    CatBoostLibraryHandlerFactory();

    CatBoostLibraryHandlerPtr tryGetModel(const String & model_path, const String & library_path, bool create_if_not_found);

    void removeModel(const String & model_path);
    void removeAllModels();

    ExternalModelInfos getModelInfos();

private:
    /// map: model path --> catboost library handler
    std::unordered_map<String, CatBoostLibraryHandlerPtr> library_handlers TSA_GUARDED_BY(mutex);
    std::mutex mutex;
    LoggerPtr log;
};

}
