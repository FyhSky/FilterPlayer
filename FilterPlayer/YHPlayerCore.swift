//
//  YHPlayerCore.swift
//  FilterPlayer
//
//  Created by Feng Yinghao on 2021/10/29.
//

import UIKit
import AVFoundation
import GLKit

public protocol PlayerCoreControl {
    func play()
    func pause()
    func position() -> Int64
    func duration() -> Int64
    func seekTo(_ location:Int64)
    func setIsLooping(_ isLooping: Bool)
    func setVolume(_ volume:Double)
    func setPlaybackSpeed(_ speed:Double)
    func setMixWithOthers(_ mixWithOthers:Bool)
    func close()
}

public protocol PixelBufferConsumer:AnyObject {
    func newPixelbufferAvailable(_ pixelbuffer:CVPixelBuffer,outputTime:CMTime)
}


func CMTimeToMillis(_ time: CMTime) -> Int64 {
    if time.timescale == 0 {
        return 0
    }
    return Int64(CMTimeScale(time.value * 1000) / time.timescale)
}

func radiansToDegrees(_ radians:Float) -> Float {
    let degrees = GLKMathRadiansToDegrees(radians)
    if(degrees < 0) {
        return degrees + 360
    }
    return degrees
}

class YHPlayerCore: NSObject,PlayerCoreControl {
    private var player:AVPlayer?
    private var videoOutput:AVPlayerItemVideoOutput?
    private var displayLink:CADisplayLink?
    private var preferredTransform:CGAffineTransform?
    private var isPlaying:Bool
    private var isLooping:Bool
    private var isInitialized:Bool
    
    private static var timeRangeContext = "timeRangeContext"
    private static var statusContext = "statusContext"
    private static var playbackLikelyToKeepUpContext = "playbackLikelyToKeepUpContext"
    private static var playbackBufferEmptyContext = "playbackBufferEmptyContext"
    private static var playbackBufferFullContext = "playbackBufferFullContext"
    
    //play status callback
    var playEvent:((NSMutableDictionary)->())?
    
    weak var delegate:PixelBufferConsumer?
    
    convenience init(url URL: URL) {
        let item = AVPlayerItem.init(url: URL)
        self.init(playerItem: item)
    }
    
    init(playerItem item: AVPlayerItem?) {
        self.isInitialized = false
        self.isLooping = false
        self.isPlaying = false
        super.init()
        
        guard let item = item else {
            return
        }
        
        let asset = item.asset
        let assetCompletionHandler = {[unowned self] in
            if(asset.statusOfValue(forKey: "tracks", error: nil) == .loaded) {
                let tracks = asset.tracks(withMediaType: .video)
                if(tracks.count > 0) {
                    guard let videoTrack = tracks.first else {
                        return
                    }
                    let trackCompletionHandler = {
                        //
                        //maybe exit
                        //
                        if (videoTrack.statusOfValue(forKey: "preferredTransform", error: nil) == .loaded) {
                            // Rotate the video by using a videoComposition and the preferredTransform
                            self.preferredTransform = self.fixTransform(videoTrack: videoTrack)
                            // Note:
                            // https://developer.apple.com/documentation/avfoundation/avplayeritem/1388818-videocomposition
                            // Video composition can only be used with file-based media and is not supported for
                            // use with media served using HTTP Live Streaming.
                            guard let transform = self.preferredTransform else {
                                return
                            }
                            let videoComposition = self.getVideoComposition(transform:transform,
                                                                            asset: asset,
                                                                            videoTrack: videoTrack)
                            item.videoComposition = videoComposition
                        }
                    }
                    videoTrack.loadValuesAsynchronously(forKeys: ["preferredTransform"],
                                                        completionHandler: trackCompletionHandler)
                }
            }
        }
        
        self.player = AVPlayer.init(playerItem: item)
        self.player?.actionAtItemEnd = .none
        
        self.createVideoOutputAndDisplayLink()
        self.addObserver(item:item)
        
        asset.loadValuesAsynchronously(forKeys: ["tracks"], completionHandler: assetCompletionHandler)
        
    }
    
    func createVideoOutputAndDisplayLink() {
        let pixBuffAttributes = [kCVPixelBufferPixelFormatTypeKey as String : NSNumber.init(value: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
                                 kCVPixelBufferIOSurfacePropertiesKey as String : NSNumber.init()]
        
        self.videoOutput = AVPlayerItemVideoOutput.init(pixelBufferAttributes: pixBuffAttributes)
        
        self.displayLink = CADisplayLink.init(target: self,
                                              selector: #selector(loopAction(_:)))
        
        self.displayLink?.add(to: RunLoop.current, forMode: RunLoop.Mode.common)
        self.displayLink?.isPaused = true
    }
    
    func fixTransform(videoTrack:AVAssetTrack) -> CGAffineTransform {
        var transform = videoTrack.preferredTransform
        if (transform.tx == 0 && transform.ty == 0) {
            let rotation = roundf(Float(atan2(transform.b, transform.a)))
            let rotationDegrees:Int64 = Int64(radiansToDegrees(rotation))
            debugPrint("TX and TY are 0. Rotation:\(rotationDegrees). Natural width,height:\(videoTrack.naturalSize.width),\(videoTrack.naturalSize.width)")
            if(rotationDegrees == 90) {
                debugPrint("Setting transform tx")
                transform.tx = videoTrack.naturalSize.height
                transform.ty = 0
            } else if (rotationDegrees == 270) {
                debugPrint("Setting transform ty")
                transform.tx = 0;
                transform.ty = videoTrack.naturalSize.width
            }
        }
        return transform
    }
    
    func getVideoComposition(transform:CGAffineTransform,
                             asset:AVAsset,
                             videoTrack:AVAssetTrack) -> AVMutableVideoComposition {
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRangeMake(start: CMTime.zero, duration: asset.duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction.init(assetTrack: videoTrack)
        layerInstruction.setTransform(transform, at: CMTime.zero)
        
        let videoComposition = AVMutableVideoComposition()
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // If in portrait mode, switch the width and height of the video
        var width = videoTrack.naturalSize.width
        var height = videoTrack.naturalSize.height
        let rotation = roundf(Float(atan2(transform.b, transform.a)))
        let rotationDegrees:Int64 = Int64(radiansToDegrees(rotation))
        if (rotationDegrees == 90 || rotationDegrees == 270) {
            width = videoTrack.naturalSize.height
            height = videoTrack.naturalSize.width
        }
        videoComposition.renderSize = CGSize.init(width: width, height: height)
        
        // TODO: should we use videoTrack.nominalFrameRate ?
        // Currently set at a constant 30 FPS
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        return videoComposition
    }
    
    func addObserver(item:AVPlayerItem) {
        item.addObserver(self,
                         forKeyPath: "loadedTimeRanges",
                         options: [NSKeyValueObservingOptions.initial,NSKeyValueObservingOptions.new],
                         context: &Self.timeRangeContext)
        item.addObserver(self,
                         forKeyPath: "status",
                         options: [NSKeyValueObservingOptions.initial,NSKeyValueObservingOptions.new],
                         context: &Self.statusContext)
        item.addObserver(self,
                         forKeyPath: "playbackLikelyToKeepUp",
                         options: [NSKeyValueObservingOptions.initial,NSKeyValueObservingOptions.new],
                         context: &Self.playbackLikelyToKeepUpContext)
        item.addObserver(self,
                         forKeyPath: "playbackBufferEmpty",
                         options: [NSKeyValueObservingOptions.initial,NSKeyValueObservingOptions.new],
                         context: &Self.playbackBufferEmptyContext)
        item.addObserver(self,
                         forKeyPath: "playbackBufferFull",
                         options: [NSKeyValueObservingOptions.initial,NSKeyValueObservingOptions.new],
                         context: &Self.playbackBufferFullContext)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(itemDidPlayToEndTime(notification:)),
                                               name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
                                               object: item)
    }
    
    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        guard let item = object as? AVPlayerItem else {
            return
        }
        if context == &Self.timeRangeContext {
            let values = NSMutableArray()
            item.loadedTimeRanges.forEach { (rangeValue:NSValue) in
                let range = rangeValue.timeRangeValue
                let start = CMTimeToMillis(range.start)
                let paire = NSMutableArray()
                paire.add(NSNumber.init(value: start))
                paire.add(NSNumber.init(value: start + CMTimeToMillis(range.duration)))
                values.add(paire)
            }
            let dic = NSMutableDictionary()
            dic["event"] = "bufferingUpdate"
            dic["values"] = values
            playEvent?(dic)
        } else if (context == &Self.statusContext) {
            switch(item.status) {
            case .failed:
                let error = NSError.init(domain: "VideoError",
                                         code: -100,
                                         userInfo: ["message":"Failed to load video: \(item.error?.localizedDescription ?? "")"])
                
                let dic = NSMutableDictionary()
                dic["event"] = "VideoError"
                dic["values"] = error
                playEvent?(dic)
                break
            case.unknown:
                break
            case .readyToPlay:
                item.add(self.videoOutput!)
                self.sendInitialized()
                self.updatePlayingState()
                break
            }
        } else if(context == &Self.playbackLikelyToKeepUpContext) {
            if(self.player?.currentItem?.isPlaybackLikelyToKeepUp == true) {
                self.updatePlayingState()
                let dic = NSMutableDictionary()
                dic["event"] = "bufferingEnd"
                playEvent?(dic)
            }
        } else if (context == &Self.playbackBufferEmptyContext) {
            let dic = NSMutableDictionary()
            dic["event"] = "bufferingStart"
            playEvent?(dic)
        } else if(context == &Self.playbackBufferFullContext) {
            let dic = NSMutableDictionary()
            dic["event"] = "bufferingEnd"
            playEvent?(dic)
        }
    }
    
    @objc func itemDidPlayToEndTime(notification:Notification) {
        if (self.isLooping) {
            if let item = notification.object as? AVPlayerItem {
                item.seek(to: CMTime.zero, completionHandler: nil)
            }
        } else {
            
        }
    }
    
    func sendInitialized() {
        if(self.isInitialized) {
            return
        }
        let size = self.player!.currentItem!.presentationSize
        let width = size.width
        let height = size.height
        
        // The player has not yet initialized.
        if(height == CGSize.zero.height && width == CGSize.zero.width) {
            return
        }
        // The player may be initialized but still needs to determine the duration.
        if self.duration() == 0 {
            return
        }
        
        self.isInitialized = true
        let dic = NSMutableDictionary()
        dic["event"] = "initialized"
        dic["duration"] = NSNumber.init(value: self.duration())
        dic["width"] = NSNumber.init(value: width)
        dic["height"] = NSNumber.init(value: height)
        playEvent?(dic)
    }
    
    func updatePlayingState() {
        if !self.isInitialized {
            return
        }
        if self.isPlaying {
            self.player?.play()
        } else {
            self.player?.pause()
        }
        self.displayLink?.isPaused = !self.isPlaying
    }
    
    // MARK: - interface
    func play() {
        self.isPlaying = true
        self.updatePlayingState()
    }
    
    func pause() {
        self.isPlaying = false
        self.updatePlayingState()
    }
    
    func position() -> Int64 {
        return CMTimeToMillis(self.player!.currentTime())
    }
    
    func duration() -> Int64 {
        return CMTimeToMillis(self.player!.currentItem!.duration)
    }
    
    func seekTo(_ location:Int64) {
        self.player?.seek(to: CMTimeMake(value: location, timescale: 1000),
                          toleranceBefore: CMTime.zero,
                          toleranceAfter: CMTime.zero)
    }
    
    func setIsLooping(_ isLooping: Bool) {
        self.isLooping = isLooping
    }
    
    func setVolume(_ volume:Double) {
        self.player?.volume = Float((volume < Double(0.0) ? Double(0.0) : ((volume > Double(1.0)) ? Double(1.0) : volume)))
    }
    
    func setPlaybackSpeed(_ speed:Double) {
        // See https://developer.apple.com/library/archive/qa/qa1772/_index.html for an explanation of
        // these checks.
        if (speed > Double(2.0) && !self.player!.currentItem!.canPlayFastForward) {
            
            let error = NSError.init(domain: "VideoError",
                                     code: -100,
                                     userInfo: ["message":"Video cannot be fast-forwarded beyond 2.0x"])
            
            let dic = NSMutableDictionary()
            dic["event"] = "VideoError"
            dic["values"] = error
            playEvent?(dic)
            return;
        }
        
        if (speed < Double(1.0) && !self.player!.currentItem!.canPlaySlowForward) {
            
            let error = NSError.init(domain: "VideoError",
                                     code: -100,
                                     userInfo: ["message":"Video cannot be slow-forwarded"])
            
            let dic = NSMutableDictionary()
            dic["event"] = "VideoError"
            dic["values"] = error
            playEvent?(dic)
            
            return;
        }
        
        self.player?.rate = Float(speed)
    }
    
    func setMixWithOthers(_ mixWithOthers:Bool) {
        if mixWithOthers {
            do {
                
                try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback,
                                                                 options: AVAudioSession.CategoryOptions.mixWithOthers)
            } catch let error as Error {
                
            }
        } else {
            do {
                
                try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
            } catch let error as Error {
                
            }
        }
        
    }
    
    func close() {
        self.displayLink?.invalidate()
        self.player?.currentItem?.removeObserver(self,
                                                 forKeyPath: "status",
                                                 context: &Self.statusContext)
        self.player?.currentItem?.removeObserver(self,
                                                 forKeyPath: "loadedTimeRanges",
                                                 context: &Self.timeRangeContext)
        self.player?.currentItem?.removeObserver(self,
                                                 forKeyPath: "playbackLikelyToKeepUp",
                                                 context: &Self.playbackLikelyToKeepUpContext)
        self.player?.currentItem?.removeObserver(self,
                                                 forKeyPath: "playbackBufferEmpty",
                                                 context: &Self.playbackBufferEmptyContext)
        self.player?.currentItem?.removeObserver(self,
                                                 forKeyPath: "playbackBufferFull",
                                                 context: &Self.playbackBufferFullContext)
        self.player?.replaceCurrentItem(with: nil)
        NotificationCenter.default.removeObserver(self)
    }
    
    
    // MARK: -
    func copyPixelBuffer() -> (CVPixelBuffer?,CMTime)? {
        let outputItemTime = self.videoOutput!.itemTime(forHostTime: CACurrentMediaTime())
        if(self.videoOutput!.hasNewPixelBuffer(forItemTime: outputItemTime)) {
            return (self.videoOutput!.copyPixelBuffer(forItemTime: outputItemTime,
                                                      itemTimeForDisplay: nil),outputItemTime)
        } else {
            return nil
        }
    }
    
    // MARK: -  loopAction
    @objc func loopAction(_ displayLink: CADisplayLink) {
        guard let pixelBuffer = self.copyPixelBuffer(),pixelBuffer.0 != nil else {
            return
        }
        
        //处理
        delegate?.newPixelbufferAvailable(pixelBuffer.0!,outputTime: pixelBuffer.1)
        //
    }
}



