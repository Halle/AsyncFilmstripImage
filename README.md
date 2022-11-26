# AsyncFilmstripImage
A SwiftUI view that asynchronously and progressively loads a composed filmstrip image from
media with a URL in the local filesystem, supporting the use of a progress indicator or other
temporary view until it is complete or fails. It optionally supports threadsafe image caching and
cache fetching when passed an instance of a class conforming to **AtomicImageCaching**,
which enforces atomicity.
