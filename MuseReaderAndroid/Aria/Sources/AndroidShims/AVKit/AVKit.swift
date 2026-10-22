// Android stand-in for AVKit: the shared code only reaches AVFoundation through it.
#if os(Android)
@_exported import AVFoundation
#endif
