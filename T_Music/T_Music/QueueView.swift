//
//  QueueView.swift
//  T_Music
//
//  Created by Tanjim Haider on 26/10/26.
//


import SwiftUI
import UIKit

struct QueueView: View {
    let songs: [Song]
    let artworkURL: (Song) -> URL?
    let onRemove: (Song) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                            .font(.system(size: 48))
                            .foregroundStyle(.mint)

                        Text("Your queue is empty")
                            .font(.title3.bold())

                        Text("Use Play Next to add songs here.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("UP NEXT · \(songs.count) SONGS") {
                            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)

                                    // Show embedded album artwork when available.
                                    if let url = artworkURL(song),
                                       let image = UIImage(contentsOfFile: url.path) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 48, height: 48)
                                            .clipShape(
                                                RoundedRectangle(cornerRadius: 8)
                                            )
                                    } else {
                                        Image(systemName: "music.note")
                                            .font(.title2)
                                            .foregroundStyle(.mint)
                                            .frame(width: 48, height: 48)
                                            .background(.mint.opacity(0.12))
                                            .clipShape(
                                                RoundedRectangle(cornerRadius: 8)
                                            )
                                    }

                                    Text(song.title)
                                        .font(.headline)
                                        .lineLimit(2)

                                    Spacer(minLength: 4)

                                    Button(role: .destructive) {
                                        onRemove(song)
                                    } label: {
                                        Image(systemName: "xmark.circle")
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        "Remove \(song.title) from queue"
                                    )
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
