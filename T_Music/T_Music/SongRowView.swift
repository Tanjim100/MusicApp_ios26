import SwiftUI
import UIKit

struct SongRowView: View {
    let song: Song
    let artworkURL: URL?
    let isCurrentSong: Bool
    let isPlaying: Bool

    let playlists: [Playlist]
//    let currentSongID: UUID
    let currentPlaylistID: UUID?

    let onTap: () -> Void
    let onAddToQueue: (Song) -> Void
    let onAddToPlaylist: (Song, UUID) -> Void
    let onRemoveFromPlaylist: (Song, UUID) -> Void
    let onDeleteSong: (Song) -> Void
    let isLibrary: Bool

    @State private var showActions = false
    @State private var showPlaylistPicker = false
    @State private var message: String?
    @State private var addedPlaylistIDs: Set<UUID> = []

    private var isActivelyPlaying: Bool {
        isCurrentSong && isPlaying
    }

    private var artistName: String {
        guard let artist = song.artist?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !artist.isEmpty else {
            return "Unknown Artist"
        }

        return artist
    }

    var body: some View {
        HStack(spacing: 12) {
            artworkView
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(
                            isActivelyPlaying ? Color.mint : Color.secondary
                        )
                        .frame(width: 20)
                        .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: isActivelyPlaying)
//                        .symbolEffect(.draw, value: isActivelyPlaying)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title)
                            .font(.headline)
                            .foregroundStyle(
                                isActivelyPlaying ? Color.mint : Color.primary
                            )
                            .lineLimit(1)

                        Text(artistName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showActions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Song actions")
        }
        .padding(.vertical, 5)
        .sheet(isPresented: $showActions) {
            actionsSheet
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
            
//            Button {
//                showActions = false
//                showPlaylistPicker = true
//            } label: {
//                Label("Add to Playlist", systemImage: "minus")
//            }
        }
        .sheet(isPresented: $showPlaylistPicker) {
            NavigationStack {
                List {
                    ForEach(playlists.filter { playlist in
                        !playlist.songIDs.contains(song.id)
                    }) { playlist in
                        Button {
                            onAddToPlaylist(song, playlist.id)

                            addedPlaylistIDs.insert(playlist.id)
                            showPlaylistPicker = false
                        } label: {
                            HStack {
                                Text(playlist.name)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Image(
                                    systemName: addedPlaylistIDs.contains(playlist.id)
                                        ? "checkmark.circle.fill"
                                        : "plus.circle"
                                )
                                .foregroundStyle(.mint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .navigationTitle("Add to Playlist")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showPlaylistPicker = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "T_Music",
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                message = nil
            }
        } message: {
            Text(message ?? "")
        }
    }

    private var actionsSheet: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                artworkView
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(artistName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            actionButton(
                title: "Add to Queue",
                systemImage: "text.badge.plus"
            ) {
                onAddToQueue(song)
                showActions = false
                message = "Added to queue."
            }

            actionButton(
                title: "Add to Playlist",
//                systemImage: "music.note.list"
                systemImage: "plus.circle"
            ) {
                showActions = false

                // Open the playlist picker after the action sheet closes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showPlaylistPicker = true
                }
            }
            
            if isLibrary {
                actionButton(
                    title: "Delete Song",
                    systemImage: "trash",
                    isDestructive: true
                ) {
                    showActions = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onDeleteSong(song)
                    }
                }
            }

            if let playlistID = currentPlaylistID {
                actionButton(
                    title: "Remove from this Playlist",
                    systemImage: "minus.circle",
                    isDestructive: true
                ) {
                    onRemoveFromPlaylist(song, playlistID)
                    showActions = false
                    message = "Removed from this playlist."
                }
            }

            Spacer(minLength: 8)
        }
    }

    private var playlistPickerSheet: some View {
        NavigationStack {
            Group {
                if playlists.isEmpty {
                    ContentUnavailableView(
                        "No Playlists Yet",
                        systemImage: "music.note.list",
                        description: Text(
                            "Create a playlist before adding songs."
                        )
                    )
                } else {
                    List(playlists) { playlist in
                        Button {
                            onAddToPlaylist(song, playlist.id)
                            showPlaylistPicker = false
                            message = "Added to \(playlist.name)."
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.mint)

                                Text(playlist.name)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if playlist.id == currentPlaylistID {
                                    Text("Current")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.mint)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showPlaylistPicker = false
                    }
                    .tint(.mint)
                }
            }
            .overlay {
                if playlists.allSatisfy({
                    $0.songIDs.contains(song.id)
                }) {
                    ContentUnavailableView(
                        "No Available Playlists",
                        systemImage: "music.note.list",
                        description: Text(
                            "This song is already in every playlist."
                        )
                    )
                }
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .frame(width: 24)

                Text(title)

                Spacer()
            }
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artworkURL,
           let image = UIImage(contentsOfFile: artworkURL.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.mint.opacity(0.12))

                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.mint)
            }
        }
    }
}
