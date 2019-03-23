//
//  Starling
//
//  Released under: MIT License
//  Copyright (c) 2018 by Matt Reagan
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import Foundation
import AVFoundation

/// Typealias used for identifying specific sound effects
public typealias SoundIdentifier = String

/// Errors specific to Starling's loading or playback functions
enum StarlingError: Error {
  case resourceNotFound(name: String)
  case invalidSoundIdentifier(name: String)
  case audioLoadingFailure
}

public class Starling : NSObject {

  /// Defines the number of players which Starling instantiates
  /// during initialization. If more concurrent sounds than this
  /// are requested at any point, Starling will allocate additional
  /// players as needed, up to `maximumTotalPlayers`.
  private static let defaultStartingPlayerCount = 8

  /// Defines the total number of concurrent sounds which Starling
  /// will allow to be played at the same time. If (N) sounds are
  /// already playing and another play() request is made, it will
  /// be ignored (not queued).
  private static let maximumTotalPlayers = 48

 // MARK: - Internal Properties

  private var players: [StarlingAudioPlayer]
  private var files: [String: AVAudioFile]
  private var buffers: [String: AVAudioPCMBuffer]
  private let engine = AVAudioEngine()

  // MARK: - Initializer

  public override init() {
    assert(Starling.defaultStartingPlayerCount <= Starling.maximumTotalPlayers, "Invalid starting and max audio player counts.")
    assert(Starling.defaultStartingPlayerCount > 0, "Starting audio player count must be > 0.")

    players = [StarlingAudioPlayer]()
    files = [String: AVAudioFile]()
    buffers = [String: AVAudioPCMBuffer]()
    super.init()

    for _ in 0..<Starling.defaultStartingPlayerCount {
      players.append(createNewPlayerAttachedToEngine())
    }

    do {
      try engine.start()
    } catch {
      print("Starling error: \(error)")
    }
  }

  // MARK: - Public API (Loading Sounds)

  @objc(loadSoundFromBundle:withType:forIdentifier:completionBlock:)
  public func load(resource: String, type: String, for identifier: SoundIdentifier, _ callback: @escaping (Error?) -> Void) {
    if let url = Bundle.main.url(forResource: resource, withExtension: type) {
      load(sound: url, for: identifier, callback)
    } else {
      callback(StarlingError.resourceNotFound(name: "\(resource).\(type)"))
    }
  }

  @objc(loadSoundFromURL:forIdentifier:completionBlock:)
  public func load(sound url: URL, for identifier: SoundIdentifier, _ callback: (Error?) -> Void) {
    do {
      let file = try AVAudioFile(forReading: url)

      // Note: self is used as the lock pointer here to avoid
      // the possibility of locking on _swiftEmptyDictionaryStorage
      objc_sync_enter(self)
      files[identifier] = file
      objc_sync_exit(self)

      callback(nil)
    } catch {
      callback(error)
    }
  }

  @objc(loadSoundFromData:withFormat:forIdentifier:)
  public func load(sound data: Data, format: AVAudioFormat, for identifier: SoundIdentifier) {
    let buffer = data.toPCMBuffer(format: format)

    // Note: self is used as the lock pointer here to avoid
    // the possibility of locking on _swiftEmptyDictionaryStorage
    objc_sync_enter(self)
    buffers[identifier] = buffer
    objc_sync_exit(self)
  }

  @objc(unloadSound:)
  public func unload(sound identifier: SoundIdentifier) {
    // Note: self is used as the lock pointer here to avoid
    // the possibility of locking on _swiftEmptyDictionaryStorage
    objc_sync_enter(self)
    files[identifier] = nil
    buffers[identifier] = nil
    objc_sync_exit(self)
  }

  // MARK: - Public API (Playback)

  @objc(playSound:volume:allowOverlap:completionBlock:)
  public func play(
    _ sound: SoundIdentifier,
    volume: Float,
    allowOverlap: Bool,
    _ callback: @escaping (Error?) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.performSoundPlayback(
        sound,
        volume: volume,
        allowOverlap: allowOverlap,
        callback
      )
    }
  }

  // MARK: - Internal Functions

  private func performSoundPlayback(
    _ sound: SoundIdentifier,
    volume: Float,
    allowOverlap: Bool,
    _ callback: @escaping (Error?) -> Void
  ) {
    // Note: self is used as the lock pointer here to avoid
    // the possibility of locking on _swiftEmptyDictionaryStorage
    objc_sync_enter(self)
    let file = files[sound]
    let buffer = buffers[sound]
    objc_sync_exit(self)

    if file == nil && buffer == nil {
      callback(StarlingError.invalidSoundIdentifier(name: sound))
      return
    }

    func performPlaybackOnFirstAvailablePlayer() {
      guard let player = firstAvailablePlayer() else { return }
      player.volume = volume

      if let audio = file {
        player.play(audio, identifier: sound, callback)
      } else if let audio = buffer {
        player.play(audio, identifier: sound, callback)
      }
    }

    if allowOverlap {
       performPlaybackOnFirstAvailablePlayer()
    } else {
      if !soundIsCurrentlyPlaying(sound) {
        performPlaybackOnFirstAvailablePlayer()
      }
    }
  }

  private func soundIsCurrentlyPlaying(_ sound: SoundIdentifier) -> Bool {
    objc_sync_enter(players)
    defer { objc_sync_exit(players) }
    // TODO: This O(n) loop could be eliminated by simply keeping a playback tally
    for player in players {
      let state = player.state
      if state.status != .idle && state.sound == sound {
        return true
      }
    }
    return false
  }

  private func firstAvailablePlayer() -> StarlingAudioPlayer? {
    objc_sync_enter(players)
    defer { objc_sync_exit(players) }
    let player: StarlingAudioPlayer? = {
      // TODO: A better solution would be to actively manage a pool of available player references
      // For almost every general use case of this library, however, this performance penalty is trivial
      let player = players.first(where: { $0.state.status == .idle })
      if player == nil && players.count < Starling.maximumTotalPlayers {
        let newPlayer = createNewPlayerAttachedToEngine()
        players.append(newPlayer)
        return newPlayer
      }
      return player
    }()

    return player
  }

  private func createNewPlayerAttachedToEngine() -> StarlingAudioPlayer {
    let player = StarlingAudioPlayer()
    engine.attach(player.node)
    engine.connect(player.node, to: engine.mainMixerNode, format: nil)
    return player
  }

  // MARK: - Debugging / Diagnostics

  private var diagnosticTimer: Timer? = nil
  public func beginPeriodicDiagnostics() {
    guard diagnosticTimer == nil else { return }
    diagnosticTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(diagnosticTimerFire(_:)), userInfo: nil, repeats: true)
  }

  public func stopDiagnostics() {
    diagnosticTimer?.invalidate()
    diagnosticTimer = nil
  }

  @objc private func diagnosticTimerFire(_ timer: Timer) {
    print("****** Starling Debug Info ******")
    print("Audio files loaded: \(files.count)")
    objc_sync_enter(players)
    print("Total living players: \(players.count)")
    print("Currently playing: \(players.filter({ $0.state.status != .idle }).count)")
    for (index, player) in players.enumerated() {
      print("Player \(index): \(player.state.status == .idle ? "Idle" : "Playing \(player.state.sound ?? "(Null)")")")
    }
    print("\n")
    objc_sync_exit(players)
  }
}

/// The internal playback status. This is somewhat redundant at the moment given that
/// it should effectively mimic -isPlaying on the node, however it may be extended in
/// the future to represent other non-binary playback modes.
///
/// - idle: No sound is currently playing.
/// - playing: A sound is playing.
/// - looping: (Not currently implemented)
private enum PlayerStatus {
  case idle
  case playing
  case looping
}

private struct PlayerState {
  let sound: SoundIdentifier?
  let status: PlayerStatus

  static func idle() -> PlayerState {
    return PlayerState(sound: nil, status: .idle)
  }
}

private class StarlingAudioPlayer {
  let node = AVAudioPlayerNode()
  var state: PlayerState = PlayerState.idle()
  var volume: Float = 1

  func play(_ file: AVAudioFile, identifier: SoundIdentifier, _ callback: @escaping (Error?) -> Void) {
    node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) {
      [weak self] callbackType in
      self?.didCompletePlayback(for: identifier, callback)
    }
    state = PlayerState(sound: identifier, status: .playing)
    node.volume = volume
    node.play()
  }

  func play(_ buffer: AVAudioPCMBuffer, identifier: SoundIdentifier, _ callback: @escaping (Error?) -> Void) {
    node.scheduleBuffer(buffer, at: nil, completionCallbackType: .dataPlayedBack) {
      [weak self] callbackType in
      self?.didCompletePlayback(for: identifier, callback)
    }
    state = PlayerState(sound: identifier, status: .playing)
    node.volume = volume
    node.play()
  }

  func didCompletePlayback(for sound: SoundIdentifier, _ callback: (Error?) -> Void) {
    state = PlayerState.idle()
    callback(nil)
  }
}

extension StarlingError: CustomStringConvertible {
  var description: String {
    switch self {
    case .resourceNotFound(let name):
      return "Resource not found '\(name)'"
    case .invalidSoundIdentifier(let name):
      return "Invalid identifier. No sound loaded named '\(name)'"
    case .audioLoadingFailure:
      return "Could not load audio data"
    }
  }
}

extension Data {
  func toPCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let streamDesc = format.streamDescription.pointee
    let frameCapacity = UInt32(count) / streamDesc.mBytesPerFrame
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)
    else { return nil }

    buffer.int16ChannelData!.pointee.withMemoryRebound(to: UInt8.self, capacity: count) {
        let stream = OutputStream(toBuffer: $0, capacity: self.count)
        stream.open()
        _ = self.withUnsafeBytes {
            stream.write($0, maxLength: self.count)
        }
        stream.close()
    }

    buffer.frameLength = frameCapacity
    return buffer
  }
}
