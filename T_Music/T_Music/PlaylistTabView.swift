
import SwiftUI
import UIKit

struct PlaylistTabView: View {
    let playlists: [Playlist]
    let songs: [Song]
    let favouriteSongIDs: Set<UUID>
    
    let currentSongID: UUID?
    let isPlaying: Bool
    
    let artworkURL: (Song) -> URL?

    let onCreate: (String) -> Void
    let onAddSong: (Song, UUID) -> Void
    let onRemoveSong: (Song, UUID) -> Void
    let onDeletePlaylist: (UUID) -> Void
    let onPlaySong: (Song, UUID) -> Void
    let onPlayFavouriteSong: (Song) -> Void
    
    let onAddToQueue: (Song) -> Void
    let isShuffleEnabled: Bool
    let onShuffle: () -> Void
    

    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var selectedPlaylistID: UUID?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Group {
                if playlists.isEmpty {
                    ContentUnavailableView {
                        Label("No Playlists Yet", systemImage: "music.note.list")
                    } description: {
                        Text("Create a playlist for your favourite songs.")
                    } actions: {
                        Button("Create Playlist") {
                            newPlaylistName = ""
                            showCreatePlaylist = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.mint)
                    }
                } else {
                    List {
                        // Favourites — always pinned at the top
                        NavigationLink {
                            FavouritesDetailView(
                                songs: songs.filter { favouriteSongIDs.contains($0.id) },
                                allSongs: songs,
                                artworkURL: artworkURL,
                                currentSongID: currentSongID,
                                isPlaying: isPlaying,
                                playlists: playlists,
                                onPlaySong: { song in
                                    onPlayFavouriteSong(song)
                                },
                                onAddToQueue: onAddToQueue,
                                onAddToPlaylist: onAddSong,
                                onRemoveFromPlaylist: onRemoveSong,
                                isShuffleEnabled: isShuffleEnabled,
                                onShuffle: onShuffle
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "heart.fill")
                                    .font(.title2)
                                    .foregroundStyle(.pink)
                                    .frame(width: 54, height: 54)
                                    .background(
                                        .pink.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )

                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Favourites")
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text("\(favouriteSongIDs.intersection(Set(songs.map(\.id))).count) songs")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        
                        ForEach(playlists) { playlist in
                            NavigationLink(value: playlist.id) {
                                HStack(spacing: 12) {
                                    Image(systemName: "music.note.list")
                                        .font(.title2)
                                        .foregroundStyle(.mint)
                                        .frame(width: 54, height: 54)
                                        .background(
                                            .mint.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 10)
                                        )

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(playlist.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        let playlistSongIDs = Set(playlist.songIDs)

                                        let count = songs.filter { song in
                                            playlistSongIDs.contains(song.id)
                                        }.count

                                        Text("\(count) songs")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete { offsets in
                            for offset in offsets {
                                onDeletePlaylist(playlists[offset].id)
                                message = "Playlist deleted"
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newPlaylistName = ""
                        showCreatePlaylist = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(.mint)
                    }
                    .accessibilityLabel("Create Playlist")
                }
            }
            .navigationDestination(for: UUID.self) { playlistID in
                if let playlist = playlists.first(where: { $0.id == playlistID }) {
                    PlaylistDetailView(
                        playlist: playlist,
                        songs: songs,
                        artworkURL: artworkURL,
                        onAddSong: { song in
                            onAddSong(song, playlist.id)
                        },
                        onRemoveSong: { song in
                            onRemoveSong(song, playlist.id)
                        },
                        onPlaySong: onPlaySong,
                        currentSongID: currentSongID,
                        isPlaying: isPlaying,
                        playlists: playlists,
                        onAddToQueue: onAddToQueue,
                        onAddToPlaylist: onAddSong,
                        onRemoveFromPlaylist: onRemoveSong,
                        isShuffleEnabled: isShuffleEnabled,
                        onShuffle: onShuffle,
                    )
                } else {
                    ContentUnavailableView(
                        "Playlist Not Found",
                        systemImage: "music.note.list"
                    )
                }
            }
            .sheet(isPresented: $showCreatePlaylist) {
                NavigationStack {
                    Form {
                        Section("Playlist Details") {
                            TextField("Playlist name", text: $newPlaylistName)
                                .submitLabel(.done)
                        }
                    }
                    .navigationTitle("New Playlist")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showCreatePlaylist = false
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Create") {
                                let name = newPlaylistName.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )

                                guard !name.isEmpty else {
                                    message = "Enter a playlist name"
                                    return
                                }

                                onCreate(name)
                                showCreatePlaylist = false
                                message = "Playlist created"
                            }
                            .disabled(
                                newPlaylistName.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                            )
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .alert(
                "Playlist",
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
    }
}

// MARK: - Playlist Detail

private struct PlaylistDetailView: View {
    let playlist: Playlist
    let songs: [Song]
    let artworkURL: (Song) -> URL?
    let onAddSong: (Song) -> Void
    let onRemoveSong: (Song) -> Void
    let onPlaySong: (Song, UUID) -> Void
    let currentSongID: UUID?
    let isPlaying: Bool
    let playlists: [Playlist]
    let onAddToQueue: (Song) -> Void
    let onAddToPlaylist: (Song, UUID) -> Void
    let onRemoveFromPlaylist: (Song, UUID) -> Void
    let isShuffleEnabled: Bool
    let onShuffle: () -> Void

    @State private var showSongPicker = false
    @State private var isEditing = false
    @State private var showingAddSongs = false

    private var playlistSongs: [Song] {
        playlist.songIDs.compactMap { id in
            songs.first(where: { $0.id == id })
        }
    }

    private var availableSongs: [Song] {
        songs.filter { song in
            !playlist.songIDs.contains(song.id)
        }
    }

    
    var body: some View {
        List {
            // Playlist header
            Section {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Spacer()

                        if let firstSong = playlistSongs.first {
                            artwork(for: firstSong, size: 190)
//                                .frame(width: size, height: size)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 12)
                                )
                        } else {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 76))
                                .foregroundStyle(.mint)
                                .frame(width: 190, height: 190)
                                .background(
                                    .mint.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                        }

                        Spacer()
                    }
                    .padding(.vertical, 12)

                    Text(playlist.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)

                    Text("\(playlistSongs.count) songs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
//                        Button {
//                            showSongPicker = true
//                        } label: {
//                            Label("Add Songs", systemImage: "plus")
//                                .font(.subheadline.weight(.semibold))
//                                .frame(maxWidth: .infinity)
//                                .padding(.vertical, 12)
//                                .background(
//                                    .mint.opacity(0.15),
//                                    in: RoundedRectangle(cornerRadius: 12)
//                                )
//                        }
//                        .buttonStyle(.plain)
//                        .foregroundStyle(.mint)

                        
                        Button {
                            onShuffle()

                            if let song = playlistSongs.randomElement() {
                                onPlaySong(song, playlist.id)
                            }
                        } label: {
                            Label(
                                "Shuffle",
                                systemImage: "shuffle"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                .mint.opacity(isShuffleEnabled ? 0.28 : 0.15),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.mint)
                        .disabled(playlistSongs.isEmpty)


                        Button {
                            if let firstSong = playlistSongs.first {
                                onPlaySong(firstSong, playlist.id)
                            }
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.black)
                                .frame(width: 46, height: 46)
                                .background(.mint, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(playlistSongs.isEmpty)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Playlist songs
            Section {
                if playlistSongs.isEmpty {
                    ContentUnavailableView(
                        "No Songs Yet",
                        systemImage: "music.note",
                        description: Text("Tap Add Songs to get started.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(playlistSongs) { song in
                        SongRowView(
                            song: song,
                            artworkURL: artworkURL(song),
                            isCurrentSong: currentSongID == song.id,
                            isPlaying: isPlaying,
                            playlists: playlists,
                            currentPlaylistID: playlist.id,
                            onTap: {
                                onPlaySong(song, playlist.id)
                            },
                            onAddToQueue: { selectedSong in
                                onAddToQueue(selectedSong)
                            },
                            onAddToPlaylist: { selectedSong, playlistID in
                                onAddToPlaylist(selectedSong, playlistID)
                            },
                            onRemoveFromPlaylist: { selectedSong, playlistID in
                                onRemoveFromPlaylist(selectedSong, playlistID)
                            },
                            onDeleteSong: { _ in
                                // Deleting songs from a playlist is not allowed.
                            },
                            isLibrary: false,
                        )
                        .listRowSeparator(.visible)
                    }
                }
            } header: {
                Text("Songs")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSongPicker = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.mint)
                }
                .accessibilityLabel("Add Songs")
            }
        }
        .sheet(isPresented: $showSongPicker) {
            NavigationStack {
                Group {
                    if availableSongs.isEmpty {
                        ContentUnavailableView(
                            "All Songs Added",
                            systemImage: "checkmark.circle",
                            description: Text(
                                "Every song in your library is already in this playlist."
                            )
                        )
                    } else {
                        List(availableSongs) { song in
                            Button {
                                onAddSong(song)
                            } label: {
                                HStack(spacing: 12) {
                                    artwork(for: song)

                                    Text(song.title)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)

                                    Spacer()

                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.mint)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationTitle("Add Songs")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showSongPicker = false
                        }
                    }
                }
            }
        }
    }


    @ViewBuilder
    private func artwork(for song: Song, size: CGFloat = 46) -> some View {
        if let url = artworkURL(song),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "music.note")
                .font(.title3)
                .foregroundStyle(.mint)
                .frame(width: size, height: size)
                .background(
                    .mint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
    }
}



// MARK: - Favourites Detail

private struct FavouritesDetailView: View {
    let songs: [Song]
    let allSongs: [Song]
    let artworkURL: (Song) -> URL?
    let currentSongID: UUID?
    let isPlaying: Bool
    let playlists: [Playlist]
    let onPlaySong: (Song) -> Void
    let onAddToQueue: (Song) -> Void
    let onAddToPlaylist: (Song, UUID) -> Void
    let onRemoveFromPlaylist: (Song, UUID) -> Void
    let isShuffleEnabled: Bool
    let onShuffle: () -> Void
    

    var body: some View {
        List {
            if songs.isEmpty {
                ContentUnavailableView(
                    "No Favourite Songs",
                    systemImage: "heart",
                    description: Text(
                        "Tap the heart button in Now Playing to add songs here."
                    )
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    HStack {
                        Text("\(songs.count) songs")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            onShuffle()

                            if let song = songs.randomElement() {
                                onPlaySong(song)
                            }
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .foregroundStyle(.mint)
                        }
                        .buttonStyle(.plain)
                        .disabled(songs.isEmpty)
                    }
                }

                Section("Songs") {
                    ForEach(songs) { song in
                        SongRowView(
                            song: song,
                            artworkURL: artworkURL(song),
                            isCurrentSong: currentSongID == song.id,
                            isPlaying: isPlaying,
                            playlists: playlists,
                            currentPlaylistID: nil,
                            onTap: {
                                onPlaySong(song)
                            },
                            onAddToQueue: { selectedSong in
                                onAddToQueue(selectedSong)
                            },
                            onAddToPlaylist: { selectedSong, playlistID in
                                onAddToPlaylist(selectedSong, playlistID)
                            },
                            onRemoveFromPlaylist: { selectedSong, playlistID in
                                onRemoveFromPlaylist(selectedSong, playlistID)
                            },
                            onDeleteSong: { _ in
                                // Songs cannot be deleted from Favourites.
                            },
                            isLibrary: false
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Favourites")
        .navigationBarTitleDisplayMode(.inline)
    }
}
