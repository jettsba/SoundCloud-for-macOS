//
//  NowPlaying.swift
//  SoundCloud
//

import AppKit
import MediaPlayer

/// The app's own Now Playing entry, under its own bundle id.
///
/// WebKit publishes one for the page too, but from its GPU process, which
/// carries the same bundle id in every app built on a web view, Safari
/// included. While some other player is the current one, nothing outside can
/// pick that entry out to send it a command. This one it can.
final class NowPlaying {
    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var artwork: String
        var duration: Double
        var position: Double
    }

    private let center = MPNowPlayingInfoCenter.default()
    private let send: (String, Double?) -> Void
    private var artworkURL: String?
    private var artwork: MPMediaItemArtwork?
    private var track: Track?
    private var playing = false

    init(send: @escaping (String, Double?) -> Void) {
        self.send = send
        let commands = MPRemoteCommandCenter.shared()
        let actions: [(MPRemoteCommand, String)] = [
            (commands.playCommand, "play"),
            (commands.pauseCommand, "pause"),
            (commands.togglePlayPauseCommand, "toggle"),
            (commands.nextTrackCommand, "nexttrack"),
            (commands.previousTrackCommand, "previoustrack"),
        ]
        for (command, action) in actions {
            command.isEnabled = true
            command.addTarget { [weak self] _ in
                self?.send(action, nil)
                return .success
            }
        }
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.send("seekto", event.positionTime)
            return .success
        }
        commands.skipForwardCommand.isEnabled = false
        commands.skipBackwardCommand.isEnabled = false
    }

    func update(track: Track?, playing: Bool) {
        self.track = track
        self.playing = playing
        guard let track else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        if track.artwork != artworkURL {
            artworkURL = track.artwork
            artwork = nil
            loadArtwork(track.artwork)
        }
        publish()
    }

    private func publish() {
        guard let track else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: track.position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = playing ? .playing : .paused
    }

    private func loadArtwork(_ address: String) {
        guard let url = URL(string: address), url.scheme == "https" else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.artworkURL == address else { return }
                self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.publish()
            }
        }.resume()
    }
}
