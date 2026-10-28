
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Combine
import MediaPlayer
import Foundation
import UIKit


struct Song: Identifiable, Codable {
    var id: UUID
    var title: String
    var filename: String

    // The filename of the extracted album artwork, if available.
    var artworkFilename: String? = nil
    var artist: String? = nil
}


struct Playlist: Identifiable, Codable {
    var id: UUID
    var name: String
    var songIDs: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        songIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.songIDs = songIDs
    }
}





enum RepeatMode: String, CaseIterable {
    case off
    case repeatOne
    case repeatAll
}



@MainActor
final class MusicLibrary: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var songs: [Song] = []
    @Published var currentSongID: UUID?
    @Published var isPlaying = false
    @Published var errorMessage: String?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isShuffleEnabled = false
    @Published var repeatMode: RepeatMode = .off
    // Songs waiting to play next, stored by song ID.
    @Published var priorityQueue: [UUID] = []
    
    @Published var playlists: [Playlist] = []
    
    @Published private(set) var favouriteSongIDs: Set<UUID> = []

    private let favouritesKey = "MyMusic.favouriteSongIDs"
    // The playlist currently controlling playback.
    private var activePlaylistID: UUID?
    private var isPlayingFavourites = false



    

    private var player: AVAudioPlayer?
    // Updates playback progress four times per second
    private var progressTimer: Timer?

    private let libraryKey = "MyMusic.savedSongs"
    private let playlistsKey = "MyMusic.savedPlaylists"

    
    
    // Stores the IDs of the last five played songs.
    private var recentlyPlayedSongIDs: [UUID] = []

   // Number of recent songs excluded from shuffle.
    private let shuffleCooldown = 5


    private var musicFolder: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
    }
    
    
    private var artworkFolder: URL {
        musicFolder.appendingPathComponent("Artwork", isDirectory: true)
    }

    // Returns the local URL of a song's artwork, if it exists.
    func artworkURL(for song: Song) -> URL? {
        guard let filename = song.artworkFilename else {
            return nil
        }

        let url = artworkFolder.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return url
    }

    
//    private var progressTimer: Timer?

    override init() {
        super.init()

        configureAudioSession()
        setupRemoteCommands()
        loadLibrary()
        loadPlaylists()
        loadFavourites()
    }
    
    
    
    private func detectedAudioExtension(for url: URL) -> String? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            guard let data = try handle.read(upToCount: 12),
                  data.count >= 4 else {
                return nil
            }

            let bytes = [UInt8](data)

            // MP4 / M4A container: "ftyp" at byte offset 4.
            if bytes.count >= 8,
               String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
                return "m4a"
            }

            // WAV container: "RIFF" at the beginning.
            if String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF" {
                return "wav"
            }

            // AIFF container: "FORM" at the beginning.
            if String(bytes: bytes[0..<4], encoding: .ascii) == "FORM" {
                return "aiff"
            }

            // FLAC container.
            if bytes.count >= 4,
               String(bytes: bytes[0..<4], encoding: .ascii) == "fLaC" {
                return "flac"
            }

            // MP3 with an ID3 header.
            if bytes.count >= 3,
               String(bytes: bytes[0..<3], encoding: .ascii) == "ID3" {
                return "mp3"
            }

            // MP3 without an ID3 header: MPEG audio frame sync.
            if bytes.count >= 2,
               bytes[0] == 0xFF,
               (bytes[1] & 0xE0) == 0xE0 {
                return "mp3"
            }

            // AAC in ADTS format.
            if bytes.count >= 2,
               bytes[0] == 0xFF,
               (bytes[1] & 0xF6) == 0xF0 {
                return "aac"
            }

            return nil
        } catch {
            print("Format detection failed: \(error.localizedDescription)")
            return nil
        }
    }


    
    func importFiles(_ urls: [URL]) {
        // Create the artwork folder if it doesn't exist.
        do {
            try FileManager.default.createDirectory(
                at: artworkFolder,
                withIntermediateDirectories: true
            )
        } catch {
            errorMessage = "Could not create artwork folder: \(error.localizedDescription)"
            return
        }

        Task { @MainActor in
            for url in urls {
                let hasAccess = url.startAccessingSecurityScopedResource()

                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    // 1. Copy the audio file into the app's Documents folder.
                    let originalExtension = url.pathExtension.lowercased()
                    let detectedExtension = detectedAudioExtension(for: url)

                    let finalExtension: String

                    if let detectedExtension {
                        finalExtension = detectedExtension
                    } else {
                        finalExtension = originalExtension
                    }

                    let originalName = url.deletingPathExtension().lastPathComponent
                    let filename = "\(originalName).\(finalExtension)"
                    let destination = musicFolder.appendingPathComponent(filename)

                    try FileManager.default.copyItem(
                        at: url,
                        to: destination
                    )

                    // 2. Extract and save artwork using the reusable function.
                    let artworkFilename = await extractAndSaveArtwork(from: destination)

                    // 3. Create the song entry.
                    let song = Song(
                        id: UUID(),
                        title: url.deletingPathExtension().lastPathComponent,
                        filename: filename,
                        artworkFilename: artworkFilename
                    )

                    songs.insert(song, at: 0)

                } catch {
                    errorMessage = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
                }
            }

            // 4. Save the updated music library.
            saveLibrary()
        }
    }


    
    func togglePlayback(_ song: Song) {
        if currentSongID == song.id, let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
            } else {
                isPlaying = player.play()
            }
            return
        }

        let url = musicFolder.appendingPathComponent(song.filename)

        do {
            // Verify that the audio file exists.
            guard FileManager.default.fileExists(atPath: url.path) else {
                errorMessage = "Audio file not found: \(url.lastPathComponent)"
                print("❌ Audio file not found: \(url.path)")
                return
            }

            print("🎵 Playing file: \(url.path)")
            print("📄 File extension: \(url.pathExtension)")

            // Initialize the audio player.
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self

            guard newPlayer.prepareToPlay() else {
                errorMessage = "The audio file could not be prepared for playback."
                print("❌ prepareToPlay() failed")
                return
            }

            player = newPlayer
            duration = newPlayer.duration
            currentTime = newPlayer.currentTime

            let didStart = newPlayer.play()

            guard didStart else {
                isPlaying = false
                errorMessage = "The audio player could not start playback."
                print("❌ AVAudioPlayer.play() returned false")
                return
            }

            currentSongID = song.id
            recordPlayedSong(song)
            isPlaying = newPlayer.isPlaying

            startProgressTimer()
            updateNowPlayingInfo(for: song)

            print("✅ Playback started: \(newPlayer.isPlaying)")

        } catch {
            isPlaying = false
            errorMessage = "Could not play this song: \(error.localizedDescription)"
            print("❌ Playback error: \(error)")
            print("❌ NSError details: \(error as NSError)")
        }
    }

    
    func seek(to time: Double) {
        guard let player else { return }

        player.currentTime = min(max(0, time), player.duration)
        currentTime = player.currentTime

        if let song = songs.first(where: { $0.id == currentSongID }) {
            updateNowPlayingInfo(for: song)
        }
    }

    
    private func recordPlayedSong(_ song: Song) {
        // Record the newly started song.
        recentlyPlayedSongIDs.append(song.id)

        // Keep only the five most recently played songs.
        if recentlyPlayedSongIDs.count > shuffleCooldown {
            recentlyPlayedSongIDs.removeFirst(
                recentlyPlayedSongIDs.count - shuffleCooldown
            )
        }
    }
    
    private var playbackSongs: [Song] {
        // Favourites playback context
        if isPlayingFavourites {
            return songs.filter { favouriteSongIDs.contains($0.id) }
        }

        // Normal playlist playback context
        if let activePlaylistID,
           let playlist = playlists.first(where: {
               $0.id == activePlaylistID
           }) {
            return playlist.songIDs.compactMap { songID in
                songs.first(where: { $0.id == songID })
            }
        }

        // Default: entire music library
        return songs
    }
    
    func playNext() {
        let currentSongs = playbackSongs

        guard !currentSongs.isEmpty else {
            isPlaying = false
            return
        }

        // 1. Priority queue: play only songs in the current context.
        while let queuedID = priorityQueue.first {
            guard let queueIndex = priorityQueue.firstIndex(of: queuedID) else {
                break
            }

            guard let queuedSong = currentSongs.first(where: {
                $0.id == queuedID
            }) else {
                // Keep songs outside the current playlist in the queue.
                // Remove only IDs that no longer exist in the library.
                if !songs.contains(where: { $0.id == queuedID }) {
                    priorityQueue.remove(at: queueIndex)
                    continue
                }

                // This queued song belongs outside the current context.
                break
            }

            priorityQueue.remove(at: queueIndex)
            togglePlayback(queuedSong)
            return
        }

        // 2. Find the current song within the active context.
        guard let index = currentSongs.firstIndex(where: {
            $0.id == currentSongID
        }) else {
            isPlaying = false
            return
        }

        let nextIndex: Int

        // 3. Shuffle only within the current playlist or Library.
        if isShuffleEnabled {
            let availableIndices = currentSongs.indices.filter {
                $0 != index &&
                !recentlyPlayedSongIDs.contains(currentSongs[$0].id)
            }

            if let randomIndex = availableIndices.randomElement() {
                nextIndex = randomIndex
            } else {
                let fallbackIndices = currentSongs.indices.filter {
                    $0 != index
                }

                if let randomIndex = fallbackIndices.randomElement() {
                    nextIndex = randomIndex
                } else {
                    nextIndex = index
                }
            }
        } else if index + 1 < currentSongs.count {
            // 4. Play the next song in order.
            nextIndex = index + 1
        } else if repeatMode == .repeatAll {
            // 5. Repeat the active playlist or Library.
            nextIndex = 0
        } else {
            // 6. End playback at the end of the active context.
            player?.stop()
            player = nil
            isPlaying = false
            currentTime = 0
            return
        }

        togglePlayback(currentSongs[nextIndex])
    }

    
    
    func enqueueNext(_ song: Song) {
        // Do not queue the song that is already playing.
        guard song.id != currentSongID else {
            return
        }

        // Avoid duplicate entries in the priority queue.
        priorityQueue.removeAll { $0 == song.id }

        // Put the newly selected song at the front.
        priorityQueue.insert(song.id, at: 0)
    }
    
    
    func removeFromQueue(_ song: Song) {
        priorityQueue.removeAll { $0 == song.id }
    }
    
    
    func deleteSong(_ song: Song) {
        // Stop playback if this is the currently playing song.
        if currentSongID == song.id {
            player?.stop()
            player = nil
            currentSongID = nil
            isPlaying = false
            currentTime = 0
            duration = 0
        }

        // Remove the actual audio file from the app's Documents directory.
        let audioURL = musicFolder.appendingPathComponent(song.filename)

        do {
            if FileManager.default.fileExists(atPath: audioURL.path) {
                try FileManager.default.removeItem(at: audioURL)
            }
        } catch {
            errorMessage = "Could not delete audio file: \(error.localizedDescription)"
            return
        }

        // Remove the associated artwork file, if present.
        if let artworkFilename = song.artworkFilename {
            let artworkURL = artworkFolder.appendingPathComponent(artworkFilename)

            do {
                if FileManager.default.fileExists(atPath: artworkURL.path) {
                    try FileManager.default.removeItem(at: artworkURL)
                }
            } catch {
                errorMessage = "Song deleted, but artwork could not be deleted: \(error.localizedDescription)"
            }
        }

        // Remove the song from the library and all playlists.
        songs.removeAll { $0.id == song.id }
        favouriteSongIDs.remove(song.id)
        saveFavourites()
        priorityQueue.removeAll { $0 == song.id }

        for index in playlists.indices {
            playlists[index].songIDs.removeAll { $0 == song.id }
        }

        saveLibrary()
        savePlaylists()
    }





    func playPrevious() {
        let currentSongs = playbackSongs

        guard !currentSongs.isEmpty,
              let index = currentSongs.firstIndex(where: {
                  $0.id == currentSongID
              }) else {
            return
        }

        let previousIndex = index > 0
            ? index - 1
            : (repeatMode == .repeatAll ? currentSongs.count - 1 : 0)

        togglePlayback(currentSongs[previousIndex])
    }
    
    
    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        guard flag else { return }

        isPlaying = false
        currentTime = 0

        if repeatMode == .repeatOne,
           let currentSong = songs.first(where: {
               $0.id == currentSongID
           }) {
            togglePlayback(currentSong)
            return
        }

        playNext()
    }

    
    
    func toggleShuffle() {
        isShuffleEnabled.toggle()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off:
            repeatMode = .repeatAll
        case .repeatAll:
            repeatMode = .repeatOne
        case .repeatOne:
            repeatMode = .off
        }
    }
    
    func createPlaylist(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            errorMessage = "Playlist name cannot be empty."
            return
        }

        let playlist = Playlist(name: trimmedName)
        playlists.append(playlist)
        savePlaylists()
    }
    
    
    func isFavourite(_ song: Song) -> Bool {
        favouriteSongIDs.contains(song.id)
    }

    func toggleFavourite(_ song: Song) {
        if favouriteSongIDs.contains(song.id) {
            favouriteSongIDs.remove(song.id)
        } else {
            favouriteSongIDs.insert(song.id)
        }

        saveFavourites()

        // If the current song is removed from Favourites,
        // leave the Favourites playback context.
        if isPlayingFavourites,
           let currentSongID,
           !favouriteSongIDs.contains(currentSongID) {

            isPlayingFavourites = false
            activePlaylistID = nil
        }

        // If no favourite songs remain, leave Favourites context.
        if favouriteSongIDs.isEmpty {
            isPlayingFavourites = false
            activePlaylistID = nil
        }
    }

    private func saveFavourites() {
        do {
            let data = try JSONEncoder().encode(favouriteSongIDs)
            UserDefaults.standard.set(data, forKey: favouritesKey)
        } catch {
            errorMessage = "Could not save favourites."
        }
    }

    private func loadFavourites() {
        guard let data = UserDefaults.standard.data(forKey: favouritesKey),
              let savedIDs = try? JSONDecoder().decode(
                  Set<UUID>.self,
                  from: data
              ) else {
            return
        }

        favouriteSongIDs = savedIDs
    }


    func addSong(_ song: Song, to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: {
            $0.id == playlistID
        }) else {
            return
        }

        // Do not add the same song twice to one playlist.
        guard !playlists[index].songIDs.contains(song.id) else {
            return
        }

        playlists[index].songIDs.insert(song.id, at: 0)
        savePlaylists()
    }

    func removeSong(_ song: Song, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: {
            $0.id == playlistID
        }) else {
            return
        }

        playlists[index].songIDs.removeAll { $0 == song.id }
        savePlaylists()
    }
    
    
    func updateSong(
        id: UUID,
        title: String,
        artist: String,
        artworkData: Data?,
        removeArtwork: Bool
    ) {
        guard let index = songs.firstIndex(where: {
            $0.id == id
        }) else {
            return
        }

        let trimmedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let trimmedArtist = artist.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedTitle.isEmpty else {
            errorMessage = "Song title cannot be empty."
            return
        }

        var updatedSong = songs[index]
        updatedSong.title = trimmedTitle
        updatedSong.artist = trimmedArtist.isEmpty
            ? nil
            : trimmedArtist

        do {
            if let artworkData {
                try FileManager.default.createDirectory(
                    at: artworkFolder,
                    withIntermediateDirectories: true
                )

                let filename = UUID().uuidString + ".jpg"
                let artworkURL = artworkFolder
                    .appendingPathComponent(filename)

                try artworkData.write(to: artworkURL)
                updatedSong.artworkFilename = filename

            } else if removeArtwork {
                updatedSong.artworkFilename = nil
            }

            songs[index] = updatedSong
            saveLibrary()

        } catch {
            errorMessage = "Could not save song changes: \(error.localizedDescription)"
        }
    }


    func deletePlaylist(_ playlistID: UUID) {
        playlists.removeAll { $0.id == playlistID }
        savePlaylists()
    }

    func playlistsNotContaining(_ song: Song) -> [Playlist] {
        playlists.filter { playlist in
            !playlist.songIDs.contains(song.id)
        }
    }
    
    func playFromPlaylist(_ song: Song, playlistID: UUID) {
        guard let playlist = playlists.first(where: {
            $0.id == playlistID
        }) else {
            return
        }

        guard playlist.songIDs.contains(song.id) else {
            return
        }

        isPlayingFavourites = false
        activePlaylistID = playlistID
        togglePlayback(song)
    }
    
    func playFavouriteSong(_ song: Song) {
        guard favouriteSongIDs.contains(song.id) else {
            return
        }

        isPlayingFavourites = true
        activePlaylistID = nil
        togglePlayback(song)
    }
    
    func playFromLibrary(_ song: Song) {
        activePlaylistID = nil
        togglePlayback(song)
    }



    private func saveLibrary() {
        do {
            let data = try JSONEncoder().encode(songs)
            UserDefaults.standard.set(data, forKey: libraryKey)
        } catch {
            errorMessage = "Could not save your music library."
        }
    }

    private func loadLibrary() {
        guard let data = UserDefaults.standard.data(forKey: libraryKey),
              let savedSongs = try? JSONDecoder().decode(
                [Song].self,
                from: data
              ) else {
            return
        }

        songs = savedSongs.filter {
            FileManager.default.fileExists(
                atPath: musicFolder.appendingPathComponent($0.filename).path
            )
        }
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default
            )
            try session.setActive(true)
        } catch {
            errorMessage = "Audio setup failed: \(error.localizedDescription)"
        }
    }
    
    private func updateNowPlayingInfo(for song: Song) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist ?? "Unknown Artist",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let player {
            info[MPMediaItemPropertyPlaybackDuration] = player.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        }

        // Add album artwork to the Lock Screen.
        if let artworkURL = artworkURL(for: song),
           let imageData = try? Data(contentsOf: artworkURL),
           let image = UIImage(data: imageData) {

            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                image
            }

            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    private func setupRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()

        // MARK: Play
        commands.playCommand.isEnabled = true
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                if let player = self.player {
                    player.play()
                    self.isPlaying = player.isPlaying

                    if let song = self.songs.first(where: {
                        $0.id == self.currentSongID
                    }) {
                        self.updateNowPlayingInfo(for: song)
                    }
                }
            }
            return .success
        }

        // MARK: Pause
        commands.pauseCommand.isEnabled = true
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }

                self.player?.pause()
                self.isPlaying = false

                if let song = self.songs.first(where: {
                    $0.id == self.currentSongID
                }) {
                    self.updateNowPlayingInfo(for: song)
                }
            }
            return .success
        }

        // MARK: Next Track
        commands.nextTrackCommand.isEnabled = true
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playNext()
            }
            return .success
        }

        // MARK: Previous Track
        commands.previousTrackCommand.isEnabled = true
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.playPrevious()
            }
            return .success
        }

        // MARK: Seek / Change Playback Position
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.changePlaybackPositionCommand.addTarget {
            [weak self] event in

            guard let event = event as? MPChangePlaybackPositionCommandEvent
            else {
                return .commandFailed
            }

            Task { @MainActor in
                guard let self, let player = self.player else { return }

                let newTime = min(
                    max(event.positionTime, 0),
                    player.duration
                )

                player.currentTime = newTime
                self.currentTime = newTime
            }

            return .success
        }
    }
    
    // Start a timer that keeps playback time in sync with AVAudioPlayer
    
    // Task responsible for updating playback progress
   private var progressTask: Task<Void, Never>?

    // Start periodic progress updates on the Main Actor.
    private func startProgressTimer() {
        // Cancel any previous progress loop.
        progressTask?.cancel()

        progressTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()

            while !Task.isCancelled {
                guard let self else { return }

                if let player = self.player {
                    self.currentTime = player.currentTime
                    self.duration = player.duration

                    // Update Lock Screen playback information.
                    if let song = self.songs.first(where: {
                        $0.id == self.currentSongID
                    }) {
                        self.updateNowPlayingInfo(for: song)
                    }
                } else {
                    self.currentTime = 0
                    self.duration = 0
                }

                // Wait 250 milliseconds before the next update.
                do {
                    try await clock.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
        }
    }
   // Stop progress updates when no longer needed
   private func stopProgressTimer() {
       progressTask?.cancel()
       progressTask = nil
   }

    
    
    private func extractArtwork(from audioURL: URL) async -> Data? {
        let asset = AVURLAsset(url: audioURL)

        do {
            // Read metadata embedded in the audio file.
            let metadata = try await asset.load(.commonMetadata)

            // Find the album artwork item.
            guard let artworkItem = metadata.first(where: {
                $0.commonKey == .commonKeyArtwork
            }) else {
                return nil
            }

            // Return the image data.
            return try await artworkItem.load(.dataValue)
        } catch {
            print("Could not read album artwork: \(error)")
            return nil
        }
    }
    
    
    // MARK: - Extract and Save Album Artwork

   private func extractAndSaveArtwork(from audioURL: URL) async -> String? {
       // Extract embedded artwork from the audio file.
       guard let artworkData = await extractArtwork(from: audioURL),
             let image = UIImage(data: artworkData),
             let jpegData = image.jpegData(compressionQuality: 0.9) else {
           return nil
       }

       do {
           // Ensure the Artwork folder exists.
           try FileManager.default.createDirectory(
               at: artworkFolder,
               withIntermediateDirectories: true
           )

           // Generate a unique filename for the artwork.
           let imageFilename = UUID().uuidString + ".jpg"
           let imageURL = artworkFolder.appendingPathComponent(imageFilename)

           // Save the artwork as a JPEG image.
           try jpegData.write(to: imageURL)

           return imageFilename
       } catch {
           errorMessage = "Could not save artwork: \(error.localizedDescription)"
           return nil
       }
   }

    
    
    private func savePlaylists() {
        do {
            let data = try JSONEncoder().encode(playlists)
            UserDefaults.standard.set(data, forKey: playlistsKey)
        } catch {
            errorMessage = "Could not save playlists: \(error.localizedDescription)"
        }
    }

    private func loadPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: playlistsKey) else {
            return
        }

        do {
            playlists = try JSONDecoder().decode([Playlist].self, from: data)
        } catch {
            errorMessage = "Could not load playlists: \(error.localizedDescription)"
        }
    }
    
    
    // MARK: - Scan Documents for audio files

   
    func scanDocumentsFolder() {
        let fileManager = FileManager.default

        guard let documentsURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return
        }

        let supportedExtensions = [
            "mp3", "m4a", "aac", "wav", "aiff", "aif"
        ]

        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )
            .sorted {
                let firstDate = (
                    try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate
                ) ?? .distantPast

                let secondDate = (
                    try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate
                ) ?? .distantPast

                return firstDate > secondDate
            }

            // Process audio files asynchronously.
            Task { @MainActor in
                for fileURL in fileURLs {
                    // Only process supported audio files.
                    guard supportedExtensions.contains(
                        fileURL.pathExtension.lowercased()
                    ) else {
                        continue
                    }

                    // Skip songs already in the library.
                    let alreadyExists = songs.contains {
                        $0.filename == fileURL.lastPathComponent
                    }

                    guard !alreadyExists else {
                        continue
                    }

                    // Extract and save artwork using the reusable function.
                    let artworkFilename =
                        await extractAndSaveArtwork(from: fileURL)

                    // Create the song entry.
                    let song = Song(
                        id: UUID(),
                        title: fileURL.deletingPathExtension().lastPathComponent,
                        filename: fileURL.lastPathComponent,
                        artworkFilename: artworkFilename
                    )

                    songs.append(song)
                }

                // Save the updated library.
                saveLibrary()
            }

        } catch {
            errorMessage =
                "Could not scan music folder: \(error.localizedDescription)"
        }
    }




}

struct ContentView: View {
    @State private var selectedTab = 0

    @StateObject private var library = MusicLibrary()
    @State private var showImporter = false
    @State private var showNowPlaying = false

    @State private var showQueueConfirmation = false
    @State private var queueConfirmationMessage = ""

    var body: some View {
        VStack(spacing: 0) {

            // MARK: - Tabs

            TabView(selection: $selectedTab) {

                // MARK: - Library Tab

                NavigationStack {
                    VStack(spacing: 0) {

                        // Library header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOUR SOUND. YOUR WORLD.")
                                .font(.caption.bold())
                                .tracking(2)
                                .foregroundStyle(.mint)

                            HStack(alignment: .center) {
                                Text("My Music")
                                    .font(.largeTitle.bold())

                                Spacer()

                                
                                Button {
                                    showImporter = true
                                } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: "square.and.arrow.down")
                                            .font(.title2.weight(.semibold))

                                        Text("Import")
                                            .font(.caption.weight(.medium))
                                    }
                                    .foregroundStyle(.mint)
                                    .frame(width: 52, height: 48)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Import songs")

                            }

                            Text("Your personal offline library")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()

//                        // Import audio files
//                        Button {
//                            showImporter = true
//                        } label: {
//                            Label(
//                                "Import Songs",
//                                systemImage: "plus.circle.fill"
//                            )
//                            .font(.headline)
//                            .frame(maxWidth: .infinity)
//                            .padding()
//                            .background(
//                                .mint,
//                                in: RoundedRectangle(cornerRadius: 16)
//                            )
//                            .foregroundStyle(.black)
//                        }
//                        .padding(.horizontal)

                        // Song list or empty state
                        if library.songs.isEmpty {
                            Spacer()

                            Image(systemName: "music.note.list")
                                .font(.system(size: 55))
                                .foregroundStyle(.mint)

                            Text("Your library is empty")
                                .font(.title3.bold())
                                .padding(.top, 8)

                            Text("Import audio files to start listening.")
                                .foregroundStyle(.secondary)

                            Spacer()
                        } else {
                            List(library.songs) { song in
                                SongRowView(
                                    song: song,
                                    artworkURL: library.artworkURL(for: song),
                                    isCurrentSong: library.currentSongID == song.id,
                                    isPlaying: library.isPlaying,
                                    playlists: library.playlists,
//                                    currentSongID: song.id,
                                    currentPlaylistID: nil,
                                    onTap: {
                                        library.playFromLibrary(song)
                                    },
                                    onAddToQueue: { selectedSong in
                                        library.enqueueNext(selectedSong)
                                    },
                                    onAddToPlaylist: { selectedSong, playlistID in
                                        library.addSong(selectedSong, to: playlistID)
                                    },
                                    onRemoveFromPlaylist: { _, _ in
                                        // Not used in the Library.
                                    },
                                    onDeleteSong: { song in
                                        library.deleteSong(song)
                                    },
                                    isLibrary: true,
                                )
                                .listRowSeparator(.visible)
                            }
                            .listStyle(.plain)
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)

                    // Import songs
                    .fileImporter(
                        isPresented: $showImporter,
                        allowedContentTypes: [.audio],
                        allowsMultipleSelection: true
                    ) { result in
                        switch result {
                        case .success(let urls):
                            library.importFiles(urls)

                        case .failure(let error):
                            library.errorMessage = error.localizedDescription
                        }
                    }

                    // Library errors
                    .alert(
                        "Music Player",
                        isPresented: Binding(
                            get: { library.errorMessage != nil },
                            set: {
                                if !$0 {
                                    library.errorMessage = nil
                                }
                            }
                        )
                    ) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text(library.errorMessage ?? "")
                    }
                }
                .tabItem {
                    Label("Library", systemImage: "music.quarternote.3")
                }
                .tag(0)

                // MARK: - Playlists Tab

                PlaylistTabView(
                    playlists: library.playlists,
                    songs: library.songs,
                    favouriteSongIDs: library.favouriteSongIDs,
                    currentSongID: library.currentSongID,
                    isPlaying: library.isPlaying,
                    artworkURL: { song in
                        library.artworkURL(for: song)
                    },
                    onCreate: { name in
                        library.createPlaylist(name: name)
                    },
                    onAddSong: { song, playlistID in
                        library.addSong(song, to: playlistID)
                    },
                    onRemoveSong: { song, playlistID in
                        library.removeSong(song, from: playlistID)
                    },
                    onDeletePlaylist: { playlistID in
                        library.deletePlaylist(playlistID)
                    },
                    onPlaySong: { song, playlistID in
                        library.playFromPlaylist(song, playlistID: playlistID)
                        showNowPlaying = true
                    },
                    onPlayFavouriteSong: { song in
                        library.playFavouriteSong(song)
                        showNowPlaying = true
                    },
                    onAddToQueue: { song in
                        library.enqueueNext(song)
                    },
                    isShuffleEnabled: library.isShuffleEnabled,
                    onShuffle: {
                        library.toggleShuffle()
                    },
                )
                .tabItem {
                    Label("Playlists", systemImage: "music.note.house.fill")
                }
                .tag(1)
            }

            // MARK: - Shared Mini Player
            // This is outside TabView, so it remains visible on every tab.

            if let song = library.songs.first(where: {
                $0.id == library.currentSongID
            }) {
                HStack(spacing: 12) {

                    // Song information button
                    Button {
                        showNowPlaying = true
                    } label: {
                        HStack(spacing: 12) {

                            // Waveform icon
                            Image(systemName: "waveform")
                                .font(.title2)
                                .foregroundStyle(.mint)
                                .symbolEffect(
                                    .bounce,
                                    options: .repeating,
                                    isActive: library.isPlaying
                                )
                                .fixedSize()

                            // Title and playback status
                            VStack(alignment: .leading, spacing: 4) {
                                ScrollingSongTitle(
                                    title: song.title,
                                    font: .system(size: 13, weight: .bold)
                                )
                                .frame(height: 18)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .clipped()

                                Text(library.isPlaying ? "Playing" : "Paused")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clipped()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    // Play/Pause control
                    Button {
                        library.togglePlayback(song)
                    } label: {
                        Image(
                            systemName: library.isPlaying
                                ? "pause.fill"
                                : "play.fill"
                        )
                        .font(.title2)
                        .foregroundStyle(.mint)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
                .padding()
                .background(.thinMaterial)
            }
        }

        // MARK: - Now Playing Sheet

        .sheet(isPresented: $showNowPlaying) {
            if let song = library.songs.first(where: {
                $0.id == library.currentSongID
            }) {
                NowPlayingView(
                    title: song.title,
                    artist: song.artist ?? "",
                    isPlaying: library.isPlaying,
                    currentTime: library.currentTime,
                    duration: library.duration,
                    onPlayPause: {
                        library.togglePlayback(song)
                    },
                    onPrevious: {
                        library.playPrevious()
                    },
                    onNext: {
                        library.playNext()
                    },
                    onSeek: { time in
                        library.seek(to: time)
                    },
                    artworkURL: library.artworkURL(for: song),
                    isShuffleEnabled: library.isShuffleEnabled,
                    repeatMode: library.repeatMode,
                    onShuffle: {
                        library.toggleShuffle()
                    },
                    onRepeat: {
                        library.cycleRepeatMode()
                    },
                    queuedSongs: library.priorityQueue.compactMap {
                        queuedID in
                        library.songs.first(where: {
                            $0.id == queuedID
                        })
                    },
                    artworkURLForSong: { queuedSong in
                        library.artworkURL(for: queuedSong)
                    },
                    onRemoveFromQueue: { queuedSong in
                        library.removeFromQueue(queuedSong)
                    },
                    playlists: library.playlists,
                    currentSongID: song.id,
                    onAddToPlaylist: { playlistID in
                        library.addSong(song, to: playlistID)
                    },
                    onSaveSong: { newTitle, newArtist, artworkData, removeArtwork in
                        library.updateSong(
                            id: song.id,
                            title: newTitle,
                            artist: newArtist,
                            artworkData: artworkData,
                            removeArtwork: removeArtwork
                        )
                    },
                    isFavourite: library.isFavourite(song),
                    onToggleFavourite: {
                        library.toggleFavourite(song)
                    },
                )
            }
        }

        // MARK: - Queue Confirmation

        .alert(
            "Queue Updated",
            isPresented: $showQueueConfirmation
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(queueConfirmationMessage)
        }

        .onAppear {
            library.scanDocumentsFolder()
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
