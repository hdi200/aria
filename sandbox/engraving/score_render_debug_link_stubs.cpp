// Linker stubs for MuseScore layout debug hooks.
//
// engravingitem.cpp only defines these when NDEBUG is unset (Debug). The iOS
// render core and engraving static libs share one /tmp CMake build directory, so
// switching Xcode Debug/Release without a clean rebuild can leave Debug object
// files that call the hooks linked against a Release engravingitem.o that omits
// them. Providing no-op definitions whenever NDEBUG is set avoids that mismatch.

#include "engraving/dom/engravingitem.h"

#ifdef NDEBUG

namespace mu::engraving {

void EngravingItem::LayoutData::doSetPosDebugHook(double x, double y)
{
    (void)x;
    (void)y;
}

void EngravingItem::LayoutData::setWidthDebugHook(double w)
{
    (void)w;
}

} // namespace mu::engraving

#endif
