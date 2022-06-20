//
//  ViewController.swift
//  FilterPlayer
//
//  Created by Feng Yinghao on 2021/10/29.
//

import UIKit
import GPUImage
import AVFoundation

class ViewController: UIViewController,PixelBufferConsumer {
    func newPixelbufferAvailable(_ pixelbuffer: CVPixelBuffer, outputTime: CMTime) {
        filterPlayer?.newPixelbufferAvailable(pixelbuffer,
                                              outputTime: outputTime)
//        originRenderView.newFramebufferAvailable(<#T##framebuffer: Framebuffer##Framebuffer#>, fromSourceIndex: <#T##UInt#>)
    }
    
    
    var filterPlayer:YHPlayer?
    var originRenderView:RenderView!
   // var originPlayerInput:YHPlayerInput = YHPlayerInput.init()
//    var originPlayer:YHPlayer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        let resourcePath = Bundle.main.path(forResource: "50", ofType: "mp4")
        let fileURL = URL.init(fileURLWithPath: resourcePath!)
        
        let rect = CGRect.init(x: 0.0,
                               y: 0.0,
                               width: self.view.frame.width,
                               height: self.view.frame.height / 2.0)
        
        originRenderView = RenderView.init(frame: rect)
        self.view.addSubview(originRenderView)

        let rect2 = CGRect.init(x: 0.0,
                                y: self.view.frame.height / 2.0,
                                width: self.view.frame.width,
                                height: self.view.frame.height / 2.0)
        filterPlayer = YHPlayer.init(frame: rect2,
                                     url: fileURL)
        filterPlayer?.player?.delegate = self;
        self.view.addSubview(filterPlayer!)
        filterPlayer!.playerInput! --> originRenderView
        filterPlayer?.play()
    }
    
}

