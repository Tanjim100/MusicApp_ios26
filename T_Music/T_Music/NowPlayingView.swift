
import SwiftUI
import UIKit
import PhotosUI

struct ScrollingSongTitle: View {
    let title: String
    var font: Font = .title2.bold()

    @State private var textWidth: CGFloat = 0
    @State private var startDate = Date()
    

    private let scrollSpeed: CGFloat = 35
    private let gap: CGFloat = 48

    var body: some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            let shouldScroll = textWidth > containerWidth

            TimelineView(
                .animation(
                    minimumInterval: 1.0 / 30.0,
                    paused: !shouldScroll
                )
            ) { timeline in
                let elapsed = max(
                    0,
                    timeline.date.timeIntervalSince(startDate)
                )

                let distance = textWidth + gap
                let cycleDuration = max(
                    0.1,
                    Double(distance / scrollSpeed)
                )

                let offset = shouldScroll
                    ? -CGFloat(elapsed.truncatingRemainder(
                        dividingBy: cycleDuration
                    )) * scrollSpeed
                    : 0

                HStack(spacing: gap) {
                    titleText

                    if shouldScroll {
                        titleText
                    }
                }
                .offset(x: offset)
                .frame(
                    height: geometry.size.height,
                    alignment: .leading
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .clipped()
            }
            .frame(
                width: containerWidth,
                height: geometry.size.height
            )
        }
        .frame(height: 36)
        .onChange(of: title) { _, _ in
            // Restart scrolling whenever the song title changes
            startDate = Date()
        }
    }

    private var titleText: some View {
        Text(title)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            updateTextWidth(proxy.size.width)
                        }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            updateTextWidth(newWidth)
                        }
                }
            }
    }

    private func updateTextWidth(_ width: CGFloat) {
        if abs(textWidth - width) > 1 {
            textWidth = width
        }
    }
}



struct NowPlayingView: View {
    let title: String
    let artist: String
    let isPlaying: Bool
    let currentTime: Double
    let duration: Double

    let onPlayPause: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onSeek: (Double) -> Void

    let artworkURL: URL?

    let isShuffleEnabled: Bool
    let repeatMode: RepeatMode
    let onShuffle: () -> Void
    let onRepeat: () -> Void

    // Queue data and actions
    let queuedSongs: [Song]
    let artworkURLForSong: (Song) -> URL?
    let onRemoveFromQueue: (Song) -> Void
    
    // Playlist data and callback for adding the current song
    let playlists: [Playlist]
    let currentSongID: UUID
    let onAddToPlaylist: (UUID) -> Void
    let onSaveSong: (String, String, Data?, Bool) -> Void
    
    let isFavourite: Bool
    let onToggleFavourite: () -> Void

    // Controls presentation of the Up Next screen.
    @State private var showQueue = false
    
    // Controls the playlist picker and confirmation popup
    @State private var showPlaylistPicker = false
    @State private var playlistMessage: String?
    @State private var showEditSong = false
    
    @State private var showMoreOptions = false
    @State private var lyricsEnabled = false
    @State private var hasLyrics = false
    @State private var showLyricsEditor = false
    @State private var currentLyricsLine = ""
    
    @State private var editedTitle = ""
    @State private var editedArtist = ""
    @State private var editedArtwork: UIImage?
    @State private var showArtworkPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var shouldRemoveArtwork = false
    
    @Environment(\.dismiss) private var dismiss
    
    private func loadCurrentLyricsLine() {
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let lyricsURL = documentsURL
            .appendingPathComponent("Lyrics", isDirectory: true)
            .appendingPathComponent("\(currentSongID.uuidString).lrc")

        guard
            let content = try? String(contentsOf: lyricsURL, encoding: .utf8)
        else {
            currentLyricsLine = ""
            return
        }

        let lines: [(time: Double, text: String)] = content
            .components(separatedBy: .newlines)
            .compactMap { line in
                guard line.hasPrefix("["),
                      let closingBracket = line.firstIndex(of: "]")
                else {
                    return nil
                }

                let timestamp = String(
                    line[line.index(after: line.startIndex)..<closingBracket]
                )

                let parts = timestamp.split(separator: ":")

                guard parts.count == 2,
                      let minutes = Double(parts[0]),
                      let seconds = Double(parts[1])
                else {
                    return nil
                }

                let text = String(line[line.index(after: closingBracket)...])

                return (minutes * 60 + seconds, text)
            }
            .sorted { $0.time < $1.time }

        currentLyricsLine = lines.last(where: {
            $0.time <= currentTime
        })?.text ?? ""
    }
    
    private func checkLyricsFile() {
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let lyricsURL = documentsURL
            .appendingPathComponent("Lyrics", isDirectory: true)
            .appendingPathComponent("\(currentSongID.uuidString).lrc")

        hasLyrics = FileManager.default.fileExists(
            atPath: lyricsURL.path
        )
    }

    private var progress: Double {
        min(max(currentTime, 0), max(duration, 0))
    }

    // Convert seconds into mm:ss or h:mm:ss
    private func timeString(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours, minutes, remainingSeconds
            )
        }

        return String(
            format: "%02d:%02d",
            minutes, remainingSeconds
        )
    }
    
    // Only show playlists that do not already contain this song
    private var availablePlaylists: [Playlist] {
        playlists.filter { playlist in
            !playlist.songIDs.contains(currentSongID)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.28, blue: 0.27),
                    Color(red: 0.07, green: 0.08, blue: 0.13),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {

                // Header: Close, title, and more options.
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Now Playing")

                    Spacer()

                    Text("NOW PLAYING")
                        .font(.caption.bold())
                        .tracking(3)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        showMoreOptions = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title2.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More options")
                }
                .foregroundStyle(.white.opacity(0.85))

                Spacer(minLength: 2)

                // Album artwork.
                ZStack {
                    RoundedRectangle(cornerRadius: 30)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.mint.opacity(0.8),
                                    Color.indigo.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if let artworkURL,
                       let imageData = try? Data(contentsOf: artworkURL),
                       let artwork = UIImage(data: imageData) {

                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFit()
//                            .frame(width: 150, height: 150)
                            .clipShape(
                                RoundedRectangle(cornerRadius: 30)
                            )

                    } else {
                        Image(systemName: "waveform")
                            .font(
                                .system(size: 100, weight: .ultraLight)
                            )
                            .foregroundStyle(.white)
                            .symbolEffect(
                                .pulse,
                                options: .repeating,
                                isActive: isPlaying
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, 4)
                .shadow(color: .mint.opacity(0.15), radius: 24)
                .layoutPriority(1)
                
                
                // Compact one-line Lyrics section.
                HStack(spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.subheadline)
                        .foregroundStyle(.mint)

                    ZStack(alignment: .leading) {
                        if !lyricsEnabled {
                            Text("Lyrics are turned off")
                                .id("lyrics-off")
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)
                                    )
                                )
                        } else {
                            Text(
                                currentLyricsLine.isEmpty
                                    ? "Lyrics will appear here"
                                    : currentLyricsLine
                            )
                            .id(currentLyricsLine)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .top).combined(with: .opacity)
                                )
                            )
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(1))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                    .animation(.easeInOut(duration: 0.5), value: lyricsEnabled)
                    .animation(.easeInOut(duration: 0.5), value: currentLyricsLine)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(
                    .white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                
                
                // Song information.
                VStack(alignment: .leading, spacing: 8) {
                    // marquee action in the title
                    ScrollingSongTitle(title: title)
                        .frame(maxWidth: .infinity)

                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                    // Open the list of playlists available for this song
//                    Button {
//                        showPlaylistPicker = true
//                    } label: {
//                        Label("Add to Playlist", systemImage: "plus.circle.fill")
//                            .font(.subheadline.weight(.semibold))
//                            .foregroundStyle(.mint)
//                            .padding(.vertical, 10)
//                            .padding(.horizontal, 14)
//                            .background(.mint.opacity(0.12), in: Capsule())
//                    }
//                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Playback progress.
                VStack(spacing: 8) {
                    // Live playback progress slider
                    Slider(
                        value: Binding(
                            get: {
                                min(max(currentTime, 0), max(duration, 0))
                            },
                            set: { newTime in
                                onSeek(newTime)
                            }
                        ),
                        in: 0...max(duration, 1)
                    )
                    .tint(.mint)
                    .disabled(duration <= 0)
                    
                    // Elapsed time on the left, remaining time on the right
                    HStack {
                        Text(timeString(currentTime))

                        Spacer()

                        Text("-" + timeString(max(duration - currentTime, 0)))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                
                // Action Row: Playlist, Favourite, and Queue.
                HStack(spacing: 12) {
                    Button {
                        showPlaylistPicker = true
                    } label: {
                        Label("Add to Playlist", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.mint)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(.mint.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    Button {
                        onToggleFavourite()
                    } label: {
                        Image(systemName: isFavourite ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(isFavourite ? .mint : .white.opacity(0.7))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        isFavourite ? "Remove from Favourites" : "Add to Favourites"
                    )

                    Button {
                        showQueue = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open Queue")
                }
                .frame(maxWidth: .infinity)

                // Playback Controls: Shuffle, Previous, Play/Pause, Next, Repeat.
                HStack(spacing: 0) {

                    // Shuffle
                    Button(action: onShuffle) {
                        Image(systemName: "shuffle")
                            .font(.title3)
                            .foregroundStyle(
                                isShuffleEnabled ? .mint : .white.opacity(0.55)
                            )
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Toggle Shuffle")

                    Spacer(minLength: 0)

                    // Previous
                    Button(action: onPrevious) {
                        Image(systemName: "backward.end.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous Song")

                    Spacer(minLength: 0)

                    // Play/Pause
                    Button(action: onPlayPause) {
                        Image(
                            systemName: isPlaying ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 76, height: 76)
                        .background(.mint, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")

                    Spacer(minLength: 0)

                    // Next
                    Button(action: onNext) {
                        Image(systemName: "forward.end.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next Song")

                    Spacer(minLength: 0)

                    // Repeat
                    Button(action: onRepeat) {
                        Image(
                            systemName: repeatMode == .repeatOne
                                ? "repeat.1"
                                : "repeat"
                        )
                        .font(.title3)
                        .foregroundStyle(
                            repeatMode == .off ? .white.opacity(0.55) : .mint
                        )
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Change Repeat Mode")
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 8)
        }
        .onAppear {
            loadCurrentLyricsLine()
        }
        .onChange(of: currentTime) { _, _ in
            loadCurrentLyricsLine()
        }
        .onChange(of: currentSongID) { _, _ in
            loadCurrentLyricsLine()
        }
        .preferredColorScheme(.dark)

        // Present the Up Next Queue screen.
        .sheet(isPresented: $showQueue) {
            QueueView(
                songs: queuedSongs,
                artworkURL: artworkURLForSong,
                onRemove: onRemoveFromQueue
            )
        }
        .sheet(
            isPresented: $showLyricsEditor,
            onDismiss: {
                checkLyricsFile()
                loadCurrentLyricsLine()
            }
        ) {
            LyricsEditorView(
                songID: currentSongID,
                songTitle: title,
                currentTime: currentTime,
                isPlaying: isPlaying,
                onPlayPause: onPlayPause,
                duration: duration,
            )
        }
        // Show only playlists that do not already contain this song
//        .confirmationDialog(
//            "Add to Playlist",
//            isPresented: $showPlaylistPicker,
//            titleVisibility: .visible
//        ) {
//            ForEach(availablePlaylists) { playlist in
//                Button(playlist.name) {
//                    onAddToPlaylist(playlist.id)
//                    playlistMessage = "Added to \(playlist.name)"
//                }
//            }
//
//            if availablePlaylists.isEmpty {
//                Button("No available playlists", role: .cancel) { }
//            }
//
//            Button("Cancel", role: .cancel) { }
//        }
        
        .sheet(isPresented: $showPlaylistPicker) {
            NavigationStack {
                List {
                    ForEach(
                        playlists.filter {
                            !$0.songIDs.contains(currentSongID)
                        }
                    ) { playlist in
                        Button {
                            onAddToPlaylist(playlist.id)
                            showPlaylistPicker = false
                        } label: {
                            HStack {
                                Text(playlist.name)
                                    .foregroundStyle(.primary)

                                Spacer()

                                Image(systemName: "plus.circle")
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
                .overlay {
                    if playlists.allSatisfy({
                        $0.songIDs.contains(currentSongID)
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
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMoreOptions) {
            NavigationStack {
                List {
                    Button {
                        editedTitle = title
                        editedArtist = artist
                        editedArtwork = nil
                        selectedPhoto = nil
                        shouldRemoveArtwork = false

                        showMoreOptions = false

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showEditSong = true
                        }
                    } label: {
                        Label("Edit Song", systemImage: "pencil")
                            .foregroundStyle(.primary)
                    }

                    // Add Lyrics / Edit Lyrics
                    Button {
                        showMoreOptions = false

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showLyricsEditor = true
                        }
                    } label: {
                        Label(
                            hasLyrics ? "Edit Lyrics" : "Add Lyrics",
                            systemImage: "text.quote"
                        )
                        .foregroundStyle(.orange)
                    }

                    // Lyrics On / Off — only when lyrics exist
                    if hasLyrics {
                        Button {
                            lyricsEnabled.toggle()
                            showMoreOptions = false
                        } label: {
                            Label(
                                lyricsEnabled ? "Lyrics Off" : "Lyrics On",
                                systemImage: lyricsEnabled
                                    ? "text.quote"
                                    : "text.quote"
                            )
                            .foregroundStyle(.orange)
                        }
                    }
                }
                .navigationTitle("More Options")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showMoreOptions = false
                        }
                        .foregroundStyle(.mint)
                    }
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEditSong) {
            NavigationStack {
                Form {
                    Section("Song Information") {
                        TextField("Song Title", text: $editedTitle)

                        TextField("Artist", text: $editedArtist)
                    }

                    Section("Album Artwork") {
                        if let editedArtwork {
                            Image(uiImage: editedArtwork)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 12)
                                )
                        } else {
                            ContentUnavailableView(
                                "No Custom Artwork",
                                systemImage: "music.note",
                                description: Text(
                                    "Choose an image for this song."
                                )
                            )
                        }

                        
                        PhotosPicker(
                            selection: $selectedPhoto,
                            matching: .images
                        ) {
                            Label(
                                "Choose Artwork",
                                systemImage: "photo"
                            )
                            .foregroundStyle(.mint)
                        }
                        .onChange(of: selectedPhoto) { _, newPhoto in
                            guard let newPhoto else { return }

                            Task {
                                if let data = try? await newPhoto.loadTransferable(
                                    type: Data.self
                                ),
                                let image = UIImage(data: data) {
                                    editedArtwork = image
                                    shouldRemoveArtwork = false
                                }
                                
                            }
                            
                        }


                        if editedArtwork != nil {
                            Button("Remove Custom Artwork", role: .destructive) {
                                editedArtwork = nil
                                shouldRemoveArtwork = true
                            }
                        }
                    }
                }
                .navigationTitle("Edit Song")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showEditSong = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let artworkData = editedArtwork?.jpegData(
                                compressionQuality: 0.9
                            )

                            onSaveSong(
                                editedTitle,
                                editedArtist,
                                artworkData,
                                shouldRemoveArtwork
                            )

                            showEditSong = false
                        }
                        .foregroundStyle(.mint)
                        .disabled(
                            editedTitle.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                    }
                }
            }
        }


        // Show confirmation after adding a song
        .alert(
            "Playlist Updated",
            isPresented: Binding(
                get: { playlistMessage != nil },
                set: { if !$0 { playlistMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                playlistMessage = nil
            }
        } message: {
            Text(playlistMessage ?? "")
        }
    }
}
