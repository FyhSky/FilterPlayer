//
//  YHPlayer.swift
//  FilterPlayer
//
//  Created by Feng Yinghao on 2021/10/30.
//

import UIKit
import AVFoundation
import GPUImage

class YHPlayer: UIView,PlayerCoreControl, PixelBufferConsumer {
    var player:YHPlayerCore?
    var renderView:RenderView?
    var playerInput:YHPlayerInput?
    var filter:BasicOperation! = Pixellate()
    override init(frame: CGRect) {
        super.init(frame: frame)
        renderView = RenderView.init(frame: CGRect.init(origin: CGPoint.zero,
                                                        size: frame.size))
        self.addSubview(renderView!)
        playerInput = YHPlayerInput.init()
        //playerInput!  --> renderView!
        self.addFilter()
    }
    
    convenience init(frame: CGRect,url URL: URL?) {
        var item:AVPlayerItem?
        if let URL = URL {
            item = AVPlayerItem.init(url: URL)
        }
        self.init(frame: frame, playerItem: item)
    }
    
    convenience init(frame: CGRect,playerItem item: AVPlayerItem?) {
        self.init(frame: frame)
        if let item = item {
            player = YHPlayerCore.init(playerItem: item)
            player?.delegate = self
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func play(url:URL) {
        player?.close()
        player = YHPlayerCore.init(url: url)
        player?.delegate = self
        //playerInput! --> renderView!
        self.addFilter()
    }
    
    func play(playerItem:AVPlayerItem) {
        player?.close()
        player = YHPlayerCore.init(playerItem: playerItem)
        player?.delegate = self
        //playerInput!  --> renderView!
        self.addFilter()
    }
    
    func addFilter() {
        playerInput! --> filter --> renderView!
    }
    
    func removeFilter() {
        
    }
    
    
    // MARK: - PlayerCoreControl
    func play() {
        player?.play()
    }
    
    func pause() {
        player?.pause()
    }
    
    func position() -> Int64 {
        return player?.position() ?? 0
    }
    
    func duration() -> Int64 {
        return player?.duration() ?? 0
    }
    
    func seekTo(_ location: Int64) {
        player?.seekTo(location)
    }
    
    func setIsLooping(_ isLooping: Bool) {
        player?.setIsLooping(isLooping)
    }
    
    func setVolume(_ volume: Double) {
        player?.setVolume(volume)
    }
    
    func setPlaybackSpeed(_ speed: Double) {
        player?.setPlaybackSpeed(speed)
    }
    
    func setMixWithOthers(_ mixWithOthers: Bool) {
        player?.setMixWithOthers(mixWithOthers)
    }
    
    func close() {
        player?.close()
        player = nil
    }
    
    // MARK: - PixelBufferConsumer
    func newPixelbufferAvailable(_ pixelbuffer: CVPixelBuffer,outputTime:CMTime) {
        playerInput?.process(pixelBuffer: pixelbuffer, withSampleTime: outputTime)
    }
    
}
