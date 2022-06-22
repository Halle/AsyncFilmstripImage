//
//  SwiftUI Asynchronous Image with filmstrip from filesystem item
//
//  Created by Halle Winkler on Mar/12/22.
//

import AVFoundation
import SwiftUI

// MARK: - AsyncFilmstripImage

/* A SwiftUI view that asynchronously and progressively loads a composed filmstrip image from
a **Media** with a URL in the local filesystem, supporting the use of a progress indicator or other
temporary view until it is complete or fails. It optionally supports threadsafe image caching and
cache fetching when passed an instance of a class conforming to **AtomicImageCaching**,
which enforces atomicity. */
///
/// In the case of a **Media** URL pointing to a locally-downloaded movie, it will load a filmstrip image that
/// is a rows by columns matrix of stills from the movie, taken from equally-spaced time intervals
/// amounting to (rows x columns) intervals in total. This lets the user visually preview the contents of a
/// captured trail camera video without watching the video.
///
/// If it is called on an image downloaded to the filesystem, rather than a movie, it returns the image content
/// in stillSize. If it is called omitting rows and columns, it returns a single still or image in stillSize.
/// Provides a simpler, more flexible alternative to QLThumbnailGenerator for thumbnailing.
///
/// **Usage example in SwiftUI for an async thumbnail, without optional caching:**
///
/// AsyncFilmstripImage(fromMedia: media, stillSize: thumbnailSize, content: { phase in
/// switch phase {
///     case .empty:
///         ProgressView()
///         .frame(width: thumbnailSize.width, height: thumbnailSize.height)
///     case .success(let image):
///         image
///     case .failure:
///         Image(systemName: "photo")
///     @unknown default:
///         EmptyView()
///     }
/// })
///
/// **Usage example in SwiftUI for an async movie filmstrip with a 3 x 4 matrix of stills, with caching support:**
///
/// AsyncFilmstripImage(fromMedia: media, withCachingSupport: filmstripCachingSupport, rows: 3, columns: 4, stillSize: filmstripSize, content: { phase in
/// switch phase {
///     case .empty:
///         ProgressView()
///             .frame(width: filmstripSize.width, height: filmstripSize.height)
///     case .success(let image):
///         image
///     case .failure:
///         Image(systemName: "photo")
///     @unknown default:
///         EmptyView()
///     }
/// })

struct AsyncFilmstripImage<Content: View>: View {
    // MARK: Lifecycle

    /// Creates an **AsyncFilmstripImage** from a **Media** whose **URL** points  to a local
    /// filesystem location, with optional threadsafe caching from an instance whose class conforms
    /// to **AtomicImageCaching**, in an optional **rows** x **columns** matrix, where each still in the
    /// matrix (or the single resulting image when no matrix is requested) is displayed at size **stillSize**

    init(
        fromMedia media: Media,
        withCachingSupport cachingSupport: AtomicImageCaching? = nil,
        rows: Int = 1,
        columns: Int = 1,
        stillSize: NSSize,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.media = media
        self.content = content
        self.stillSize = stillSize
        self.rows = rows
        self.columns = columns
        self.cachingSupport = cachingSupport
    }

    // MARK: Internal

    var body: some View {
        content(phase)
            .task {
                await requestFilmstrip(media: media, stillSize: stillSize, rows: rows, columns: columns)
            }
    }

    // MARK: Private

    @State private var phase: AsyncImagePhase = .empty
    private let content: (AsyncImagePhase) -> Content
    private let media: Media
    private let stillSize: NSSize
    private let rows: Int
    private let columns: Int
    private let cachingSupport: AtomicImageCaching?

    private func requestFilmstrip(media: Media, stillSize: NSSize, rows: Int, columns: Int) async {
        Task {
            let image = Image(
                filmstripFromMedia: media,
                withCachingSupport: cachingSupport,
                rows: rows,
                columns: columns,
                stillSize: stillSize
            )
            phase = .success(image)
        }
    }
}

// MARK: - Image extension supporting filmstrip initialization

/// This is an extension on Image, rather than a View which happens to return an Image,
/// because it allows us to use AsyncImagePhase in the async filmstrip loader without reimplementation.
/// This new Image init is also convenient, since we can use the initialized system image as
/// the placeholder we return in case of failure.

extension Image {
    // MARK: Private

    /// Synchronously creates an **Image** from a **Media** whose **URL** points  to a local
    /// filesystem location, with optional threadsafe caching from an instance whose class conforms
    /// to **AtomicImageCaching**, in an optional **rows** x **columns** matrix, where each still in the
    /// matrix (or the single resulting image when no matrix is requested) is displayed at size **stillSize**

    fileprivate init(
        filmstripFromMedia media: Media,
        withCachingSupport cachingSupport: AtomicImageCaching? = nil,
        rows: Int = 1,
        columns: Int = 1,
        stillSize: NSSize
    ) {
        self.init(systemName: "photo")
        self = filmstripImage(
            media: media,
            withCachingSupport: cachingSupport,
            rows: rows,
            columns: columns,
            stillSize: stillSize
        )
    }

    private enum FilmstripImageError: Error {
        case videoUnplayable
        case imageDataUnloadable
    }

    /// If the **Media** happens to represent a local image file and not a movie file, we can return its contents as an image early.

    private func imageFromImageFile(media: Media, stillSize: NSSize, cachingSupport: AtomicImageCaching?) throws -> Image {
        guard let imageData = try? Data(contentsOf: media.url), let nsImage = NSImage(data: imageData) else {
            throw FilmstripImageError.imageDataUnloadable
        }
        nsImage.size = stillSize
        let image = Image(nsImage: nsImage)
        cachingSupport?.cacheImage(id: media.id, image: image)
        return image
    }

    /// Synchronously generates an **Image** from a **Media** whose **URL** points  to a local
    /// filesystem location, with optional threadsafe caching from an instance whose class conforms
    /// to **AtomicImageCaching**, in an optional **rows** x **columns** matrix, where each still in the
    /// matrix (or the single resulting image when no matrix is requested) is displayed at size **stillSize**

    private func filmstripImage(
        media: Media,
        withCachingSupport cachingSupport: AtomicImageCaching? = nil,
        rows: Int = 1,
        columns: Int = 1,
        stillSize: NSSize
    ) -> Image {
        let placeholderImage = self // Stash placeholder used in the init to return in case of error
        if let cachedImage = cachingSupport?.fetchImageFromCache(id: media.id) { // Early return cached image if it exists
            return cachedImage
        }

        do {
            if media.url.isImage { // early return image file contents if this URL points to an image UTI,
                return try imageFromImageFile(media: media, stillSize: stillSize, cachingSupport: cachingSupport)
            }
            // otherwise it's a video and not in the cache,
            let asset = AVAsset(url: media.url) // and we generate a still or filmstrip of stills to return as image
            if asset.isNotPlayable() {
                throw FilmstripImageError.videoUnplayable
            }

            let runningTimeInSeconds = Double(asset.duration.seconds)
            let preferredTimescale: Int32 = 600
            let timeslice = runningTimeInSeconds / Double(rows * columns) // rows * columns == total filmstrip images
            let assetImgGenerate = AVAssetImageGenerator(asset: asset)
            
            let composedImage = NSImage(size: NSSize( // Make the full-sized workspace
                width: stillSize.width * Double(columns),
                height: stillSize.height * Double(rows)
            ))
            composedImage.lockFocus()

            var index = 0
            for row in 0 ..< rows { // Tile across and down the following:
                for column in 0 ..< columns {
                    let time = CMTimeMakeWithSeconds(timeslice * Double(index), preferredTimescale: preferredTimescale)
                    // A cgImage frame from the video at a progressively-increasing time,
                    let cgImage = try assetImgGenerate.copyCGImage(at: time, actualTime: nil)
                    var rect: CGRect = .zero
                    rect.size = stillSize // at the targeted small rect.
                    let multiplierX = Double(column) // Moving x origin left->right means its value must increase,
                    // but moving y origin progressively downwards means its value has to decrease.
                    let multiplierY = Double(rows - 1) - Double(row)
                    // So move the origin accordingly,
                    rect.origin = CGPoint(
                        x: stillSize.width * multiplierX,
                        y: stillSize.height * multiplierY
                    )
                    NSImage(cgImage: cgImage, size: stillSize).draw(in: rect) // then draw.
                    index += 1
                }
            }

            composedImage.unlockFocus()
            let image = Image(nsImage: composedImage)
            cachingSupport?.cacheImage(id: media.id, image: image) // Cache if uncached
            return image

        } catch { // Not fatal, but the display of this placeholder image indicates an issue to track down.
            switch error {
            case FilmstripImageError.videoUnplayable:
                print("Video at \(media.url) appears to be corrupted: \(error)")
            case FilmstripImageError.imageDataUnloadable:
                print("Image could not be loaded from \(media.url) due to error: \(error)")
            default:
                print("Unable to load media due to error: \(error)")
            }
            return placeholderImage
        }
    }
}
