Android-only stand-ins for Apple modules the shared iOS files import (`import UIKit`, ...),
so those files build unchanged. Each re-exports Skip's or Foundation's equivalents and adds
what the shared code uses. They are only built for Android (see Package.swift).
