//
//  LyricsEditorView.swift
//  T_Music
//
//  Created by Tanjim Haider on 28/10/26.
//


import SwiftUI

struct LyricsEditorView: View {
    let songID: UUID
    let songTitle: String
    let currentTime: Double
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let duration: Double

    @Environment(\.dismiss) private var dismiss

    @State private var lineText = ""
    @State private var timestamp = ""

    @State private var lyricsLines: [(time: Double, text: String)] = []
    
    @State private var saveMessage: String?

    private func timeString(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(
            format: "%02d:%02d.%02d",
            total / 60,
            total % 60,
            Int((seconds - Double(total)) * 100)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Timestamp and lyrics input
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add a Lyrics Line")
                        .font(.headline)

                    HStack(spacing: 10) {
                        TextField("00:12.50", text: $timestamp)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 115)

                        Button("Use Current Time") {
                            timestamp = timeString(currentTime)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.mint)
                    }

                    TextField("Enter lyrics in Banglish...", text: $lineText)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        guard
                            let time = parseTimestamp(timestamp),
                            !lineText.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        else { return }

                        lyricsLines.append((time, lineText))
                        lyricsLines.sort { $0.time < $1.time }
                        
                        saveLyrics()

                        lineText = ""
                        timestamp = ""
                    } label: {
                        Label("Add Line", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.mint, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                // Added lyrics lines
                List {
                    ForEach(lyricsLines.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 12) {
                            Text(timeString(lyricsLines[index].time))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.mint)

                            Text(lyricsLines[index].text)
                                .foregroundStyle(.primary)

                            Spacer()

                            Button(role: .destructive) {
                                lyricsLines.remove(at: index)
                                saveLyrics()
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.04))
                    }
                }
                .scrollContentBackground(.hidden)

                // Persistent playback controls at the bottom
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(.mint)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(songTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.white.opacity(0.15))

                                    Capsule()
                                        .fill(.mint)
                                        .frame(
                                            width: geometry.size.width *
                                            min(max(currentTime / max(duration, 1), 0), 1)
                                        )
                                }
                            }
                            .frame(height: 3)

                            Text(timeString(currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Button(action: onPlayPause) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.title2)
                                .foregroundStyle(.mint)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .padding(.horizontal)
            .background {
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
            }
            .navigationTitle("Add Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.mint)
                }
            }
            .alert(
                "Lyrics",
                isPresented: Binding(
                    get: { saveMessage != nil },
                    set: { if !$0 { saveMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    saveMessage = nil
                }
            } message: {
                Text(saveMessage ?? "")
            }
        }
        .onAppear {
            loadLyrics()
        }
        .preferredColorScheme(.dark)
    }
    
    
    private var lyricsFileURL: URL {
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let lyricsDirectory = documentsURL.appendingPathComponent(
            "Lyrics",
            isDirectory: true
        )

        return lyricsDirectory.appendingPathComponent(
            "\(songID.uuidString).lrc"
        )
    }

    private func loadLyrics() {
        do {
            let url = lyricsFileURL

            guard FileManager.default.fileExists(atPath: url.path) else {
                lyricsLines = []
                return
            }

            let content = try String(contentsOf: url, encoding: .utf8)

            lyricsLines = content.components(separatedBy: .newlines)
                .compactMap { line in
                    guard line.hasPrefix("["),
                          let closingBracket = line.firstIndex(of: "]")
                    else {
                        return nil
                    }

                    let timestampText = String(
                        line[line.index(after: line.startIndex)..<closingBracket]
                    )

                    let lyricsText = String(line[line.index(after: closingBracket)...])

                    guard let time = parseTimestamp(timestampText),
                          !lyricsText.isEmpty
                    else {
                        return nil
                    }

                    return (time: time, text: lyricsText)
                }
                .sorted { $0.time < $1.time }
        } catch {
            saveMessage = "Could not load lyrics: \(error.localizedDescription)"
        }
    }

    private func saveLyrics() {
        do {
            let directory = lyricsFileURL.deletingLastPathComponent()

            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let content = lyricsLines
                .sorted { $0.time < $1.time }
                .map { line in
                    let totalCentiseconds = Int((line.time * 100).rounded())
                    let minutes = totalCentiseconds / 6000
                    let seconds = (totalCentiseconds / 100) % 60
                    let centiseconds = totalCentiseconds % 100

                    return String(
                        format: "[%02d:%02d.%02d]%@",
                        minutes,
                        seconds,
                        centiseconds,
                        line.text
                    )
                }
                .joined(separator: "\n")

            try content.write(
                to: lyricsFileURL,
                atomically: true,
                encoding: .utf8
            )

            saveMessage = "Lyrics saved successfully."
        } catch {
            saveMessage = "Could not save lyrics: \(error.localizedDescription)"
        }
    }


    private func parseTimestamp(_ value: String) -> Double? {
        let parts = value.split(separator: ":")

        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]),
              minutes >= 0,
              seconds >= 0,
              seconds < 60 else {
            return nil
        }

        return minutes * 60 + seconds
    }
}
