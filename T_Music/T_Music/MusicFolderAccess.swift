//
//  MusicFolderAccess.swift
//  T_Music
//
//  Created by Tanjim Haider on 26/10/26.
//


import Foundation
import UniformTypeIdentifiers
import Combine

@MainActor
final class MusicFolderAccess: ObservableObject {

    // Selected MyMusic folder URL
    @Published private(set) var folderURL: URL?

    // Folder selection status message
    @Published var statusMessage = "Choose your MyMusic folder."

    private let bookmarkKey = "MyMusicFolderBookmark"

    // MARK: - Save selected folder

    func saveFolderAccess(_ url: URL) {
        let hasAccess = url.startAccessingSecurityScopedResource()

        do {
            // Save a bookmark so we can reopen the folder later.
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            folderURL = url
            statusMessage = "Folder connected: \(url.lastPathComponent)"

        } catch {
            statusMessage = "Could not save folder access: \(error.localizedDescription)"
        }

        // Release the temporary access obtained from the picker.
        if hasAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Restore saved folder

    func restoreFolderAccess() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            statusMessage = "Choose On My iPhone/MyMusic to get started."
            return
        }

        do {
            var isStale = false

            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            folderURL = url
            statusMessage = "Saved folder found: \(url.lastPathComponent)"

            if isStale {
                saveFolderAccess(url)
            }

        } catch {
            folderURL = nil
            statusMessage = "Folder access expired. Please choose the folder again."
        }
    }
}
