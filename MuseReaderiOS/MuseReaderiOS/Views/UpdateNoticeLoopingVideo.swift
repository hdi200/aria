//
//  UpdateNoticeLoopingVideo.swift
//  MuseReaderiOS
//
//  A muted, looping clip in the update notice.
//

import AVFoundation
import SwiftUI
import UIKit

struct UpdateNoticeLoopingVideo: UIViewRepresentable {
    let url: URL

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var looper: AVPlayerLooper?
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        // The clips have no sound; muting also keeps other audio playing.
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        view.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {}

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.playerLayer.player?.pause()
        view.looper = nil
    }
}
