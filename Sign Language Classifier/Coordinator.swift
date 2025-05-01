//
//  Coordinator.swift
//  Sign Language Classifier
//
//  Created by Fredrik Løkke on 18/04/2025.
//
import CoreML
import SwiftUI
import UIKit
import AVFoundation
import Vision

class Coordinator: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var overlayLayer: CAShapeLayer?
    var currentCameraPosition: AVCaptureDevice.Position = .front
    
    var handPoseBuffer: [VNHumanHandPoseObservation] = []
    
    //Variables to store the prediction with highest confidence, the progress for buffering purposes and top three predictions
    @Binding var predictionLabel: String
    @Binding var progress: Double
    @Binding var predictionTopThree: Array<(key: String, value: Double)>
    
    
    //These are the four tested models in the thesis. Refer to the the implementation section to review their performance
    
    //MARK: BASE
    //let handActionModel = HandActionClassifierBase()
    
    //MARK: WITHOUT NO SIGN
    //let handActionModel = HandActionClassifierWithoutNoSign()
    
    //MARK: AUGMENTED
    //let handActionModel = HandActionClassifierAugmented()
    
    //MARK: 80 vids fewer augs
    let handActionModel = HandActionClassifier80vidsFewerAugs()
    
    
    //Keypoint identifiers. In order, to ensure correct model input
    let keypointOrder: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip
    ]
    
    init(predictionLabel: Binding<String>, progress: Binding<Double>, predictionTopThree: Binding<Array<(key: String, value: Double)>>) {
        _predictionLabel = predictionLabel
        _progress = progress
        _predictionTopThree = predictionTopThree
        super.init()
    }
    
    // Configure and start the camera capture session.
    func setupCaptureSession(in view: UIView, position: AVCaptureDevice.Position = .front) {
        currentCameraPosition = position
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .hd1280x720
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                        for: .video,
                                                        position: position) else { return }
        // Set the frame rate to 30 fps to match what the model has trained on
        try! videoDevice.lockForConfiguration()
        
        videoDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 30)
        videoDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 30)
        videoDevice.unlockForConfiguration()
        
        guard let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        captureSession?.addInput(videoInput)
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession?.canAddOutput(videoOutput) == true {
            captureSession?.addOutput(videoOutput)
        }
        
        // Set up the preview layer - what is shown on the user device screen
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = view.bounds
        previewLayer?.zPosition = -1
        view.layer.insertSublayer(previewLayer!, at: 0)
        
        // Configure the overlay layer for drawing red dots
        overlayLayer = CAShapeLayer()
        overlayLayer?.frame = view.bounds
        overlayLayer?.strokeColor = UIColor.red.cgColor
        overlayLayer?.fillColor = UIColor.red.cgColor
        overlayLayer?.lineWidth = 2.0
        view.layer.addSublayer(overlayLayer!)
        
        if let connection = videoOutput.connection(with: .video) {
            connection.isVideoMirrored = true
            connection.videoOrientation = .portrait
        }
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
        }
    }
    
    //Switch between front/back camera
    func switchCamera(in view: UIView) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.stopRunning()
        }
        
        DispatchQueue.main.async {
            self.previewLayer?.removeFromSuperlayer()
            self.overlayLayer?.removeFromSuperlayer()
            
            let newPosition: AVCaptureDevice.Position = (self.currentCameraPosition == .front) ? .back : .front
            self.setupCaptureSession(in: view, position: newPosition)
        }
    }
    
    // Process each captured frame. The handPoseRequest retrieves the hand landmarks for each frame, storing these in the handPoseBuffer array. Once this reaches a count of 60, this array is used to classify the hand action (signed word).
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        let handPoseRequest = VNDetectHumanHandPoseRequest()
        handPoseRequest.maximumHandCount = 2
        
        do {
            try requestHandler.perform([handPoseRequest])
            if let observations = handPoseRequest.results, !observations.isEmpty,
               let handObservation = observations.first {
                // Draw red dots for each keypoint.
                drawHandPoints(observation: handObservation)
                
                handPoseBuffer.append(handObservation)
                DispatchQueue.main.async {
                    self.progress = Double(self.handPoseBuffer.count) / 60.0
                }
                if handPoseBuffer.count >= 60 {
                    classifyHandAction()
                    handPoseBuffer.removeAll()
                    DispatchQueue.main.async { self.progress = 0.0 }
                }
            } else {
                // Clear overlay if no hand is detected and reset the buffer/progress.
                clearHandPoints()
                handPoseBuffer.removeAll()
                DispatchQueue.main.async { self.progress = 0.0 }
            }
        } catch {
            print("Error performing hand pose request: \(error)")
        }
    }
    
    // Draw red dots on the preview for each detected hand keypoint - useful for testing purposes, but maybe not in the finished application
    func drawHandPoints(observation: VNHumanHandPoseObservation) {
        DispatchQueue.main.async {
            guard let previewLayer = self.previewLayer,
                  let overlayLayer = self.overlayLayer else { return }
            
            let path = UIBezierPath()
            for key in self.keypointOrder {
                if let point = try? observation.recognizedPoint(key), point.confidence > 0.2 {
                    let normalizedPoint = CGPoint(x: 1 - point.location.y, y: point.location.x)
                    let convertedPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
                    let circle = UIBezierPath(arcCenter: convertedPoint,
                                              radius: 3,
                                              startAngle: 0,
                                              endAngle: CGFloat.pi * 2,
                                              clockwise: true)
                    path.append(circle)
                }
            }
            overlayLayer.path = path.cgPath
        }
    }
    
    // Remove dots when no hand is detected.
    func clearHandPoints() {
        DispatchQueue.main.async {
            self.overlayLayer?.path = nil
        }
    }
    
    // Package observations into an MLMultiArray and run prediction. Takes in the handPoseBuffer array from the captureOutput method, and uses this to create the MLMultiArray. Uses the model to run a prediction on the multiarray, and returns the top label and top three confidences
    func classifyHandAction() {
        guard let multiArray = try? MLMultiArray(shape: [60, 3, 21] as [NSNumber], dataType: .float32) else {
            print("Failed to create MLMultiArray")
            return
        }
        
        for frameIndex in 0..<60 {
            let observation = handPoseBuffer[frameIndex]
            for (keyIndex, key) in keypointOrder.enumerated() {
                let baseIndex = frameIndex * 3 * 21 + keyIndex
                let xIndex = baseIndex
                let yIndex = frameIndex * 3 * 21 + (1 * 21) + keyIndex
                let confIndex = frameIndex * 3 * 21 + (2 * 21) + keyIndex
                
                if let point = try? observation.recognizedPoint(key) {
                    multiArray[xIndex] = NSNumber(value: Float(point.location.x))
                    multiArray[yIndex] = NSNumber(value: Float(point.location.y))
                    multiArray[confIndex] = NSNumber(value: Float(point.confidence))
                } else {
                    multiArray[xIndex] = 0
                    multiArray[yIndex] = 0
                    multiArray[confIndex] = 0
                }
            }
        }
        
        do {
            let prediction = try handActionModel.prediction(poses: multiArray)
            DispatchQueue.main.async {
                self.predictionLabel = prediction.label
                self.predictionTopThree = Array(prediction.labelProbabilities.sorted(by: {$0.value > $1.value}).prefix(3))
            }
        } catch {
            print("Prediction error: \(error)")
        }
    }
}
