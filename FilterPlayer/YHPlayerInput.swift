//
//  YHPlayerInput.swift
//  FilterPlayer
//
//  Created by Feng Yinghao on 2021/10/30.
//

import UIKit
import GPUImage
import AVFoundation

class YHPlayerInput: ImageSource {
    var targets: TargetContainer = TargetContainer()
    
    func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        
    }
    
    let yuvConversionShader:ShaderProgram
    
    init() {
        self.yuvConversionShader = crashOnShaderCompileFailure("MovieInput"){try sharedImageProcessingContext.programForVertexShader(defaultVertexShaderForInputs(2),
                                                                                                                                     fragmentShader:YUVConversionFullRangeFragmentShader)}
    }
    
    deinit {
        
    }
    
    func process(movieFrame frame:CMSampleBuffer) {
        let currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(frame)
        let pixelBuffer = CMSampleBufferGetImageBuffer(frame)!
        self.process(pixelBuffer:pixelBuffer, withSampleTime:currentSampleTime)
    }
    
    func process(pixelBuffer:CVPixelBuffer, withSampleTime:CMTime) {
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        
        let conversionMatrix = colorConversionMatrix601FullRangeDefault
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        //let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
        
#if os(iOS)
        var luminanceGLTexture: CVOpenGLESTexture?
        
        glActiveTexture(GLenum(GL_TEXTURE0))
        
        //Y-plane. Y平面
        let luminanceGLTextureResult = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                                    sharedImageProcessingContext.coreVideoTextureCache,
                                                                                    pixelBuffer,
                                                                                    nil,
                                                                                    GLenum(GL_TEXTURE_2D),
                                                                                    GL_LUMINANCE,
                                                                                    GLsizei(bufferWidth),
                                                                                    GLsizei(bufferHeight),
                                                                                    GLenum(GL_LUMINANCE),
                                                                                    GLenum(GL_UNSIGNED_BYTE),
                                                                                    0,
                                                                                    &luminanceGLTexture)
        
        assert(luminanceGLTextureResult == kCVReturnSuccess && luminanceGLTexture != nil)
        
        let luminanceTexture = CVOpenGLESTextureGetName(luminanceGLTexture!)
        
        glBindTexture(GLenum(GL_TEXTURE_2D), luminanceTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE));
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE));
        
        let luminanceFramebuffer: Framebuffer
        do {
            luminanceFramebuffer = try Framebuffer(context: sharedImageProcessingContext,
                                                   orientation: .portrait,
                                                   size: GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)),
                                                   textureOnly: true,
                                                   overriddenTexture: luminanceTexture)
        } catch {
            fatalError("Could not create a framebuffer of the size (\(bufferWidth), \(bufferHeight)), error: \(error)")
        }
        
        //         luminanceFramebuffer.cache = sharedImageProcessingContext.framebufferCache
        luminanceFramebuffer.lock()
        
        
        var chrominanceGLTexture: CVOpenGLESTexture?
        
        glActiveTexture(GLenum(GL_TEXTURE1))
        
        let chrominanceGLTextureResult = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                                      sharedImageProcessingContext.coreVideoTextureCache,
                                                                                      pixelBuffer,
                                                                                      nil,
                                                                                      GLenum(GL_TEXTURE_2D),
                                                                                      GL_LUMINANCE_ALPHA,
                                                                                      GLsizei(bufferWidth / 2),
                                                                                      GLsizei(bufferHeight / 2),
                                                                                      GLenum(GL_LUMINANCE_ALPHA),
                                                                                      GLenum(GL_UNSIGNED_BYTE),
                                                                                      1,
                                                                                      &chrominanceGLTexture)
        
        if(chrominanceGLTextureResult != kCVReturnSuccess) {
            debugPrint("Error at CVOpenGLESTextureCacheCreate \(chrominanceGLTextureResult)")
        }
        
        assert(chrominanceGLTextureResult == kCVReturnSuccess && chrominanceGLTexture != nil)
        
        let chrominanceTexture = CVOpenGLESTextureGetName(chrominanceGLTexture!)
        
        glBindTexture(GLenum(GL_TEXTURE_2D), chrominanceTexture)
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GLfloat(GL_CLAMP_TO_EDGE));
        glTexParameterf(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GLfloat(GL_CLAMP_TO_EDGE));
        
        let chrominanceFramebuffer: Framebuffer
        do {
            chrominanceFramebuffer = try Framebuffer(context: sharedImageProcessingContext,
                                                     orientation: .portrait,
                                                     size: GLSize(width:GLint(bufferWidth),
                                                                  height:GLint(bufferHeight)),
                                                     textureOnly: true,
                                                     overriddenTexture: chrominanceTexture)
        } catch {
            fatalError("Could not create a framebuffer of the size (\(bufferWidth), \(bufferHeight)), error: \(error)")
        }
        
        //         chrominanceFramebuffer.cache = sharedImageProcessingContext.framebufferCache
        chrominanceFramebuffer.lock()
#else
        let luminanceFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait,
                                                                                                                  size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)),
                                                                                                                  textureOnly:true)
        luminanceFramebuffer.lock()
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), luminanceFramebuffer.texture)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_LUMINANCE, GLsizei(bufferWidth), GLsizei(bufferHeight), 0, GLenum(GL_LUMINANCE), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddressOfPlane(movieFrame, 0))
        
        let chrominanceFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:true)
        chrominanceFramebuffer.lock()
        glActiveTexture(GLenum(GL_TEXTURE1))
        glBindTexture(GLenum(GL_TEXTURE_2D), chrominanceFramebuffer.texture)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_LUMINANCE_ALPHA, GLsizei(bufferWidth / 2), GLsizei(bufferHeight / 2), 0, GLenum(GL_LUMINANCE_ALPHA), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddressOfPlane(movieFrame, 1))
#endif
        let movieFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait,
                                                                                                              size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)),
                                                                                                              textureOnly:false)
        
        convertYUVToRGB(shader:self.yuvConversionShader,
                        luminanceFramebuffer:luminanceFramebuffer,
                        chrominanceFramebuffer:chrominanceFramebuffer,
                        resultFramebuffer:movieFramebuffer,
                        colorConversionMatrix:conversionMatrix)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        
        movieFramebuffer.timingStyle = .videoFrame(timestamp:Timestamp(withSampleTime))
        self.updateTargetsWithFramebuffer(movieFramebuffer)
        
        //        if self.runBenchmark {
        //            let currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime)
        //            self.numberOfFramesCaptured += 1
        //            self.totalFrameTimeDuringCapture += currentFrameTime
        //            print("Average frame time : \(1000.0 * self.totalFrameTimeDuringCapture / Double(self.numberOfFramesCaptured)) ms")
        //            print("Current frame time : \(1000.0 * currentFrameTime) ms")
        //        }
    }
    
}

