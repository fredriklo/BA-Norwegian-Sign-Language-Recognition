//
//  CameraView.swift
//  Sign Language Classifier
//
//  Created by Fredrik Løkke on 18/04/2025.
//

import SwiftUI
import AVFoundation
import UIKit
import Vision

struct CameraView: UIViewRepresentable {
    @Binding var predictionLabel: String
    @Binding var progress: Double
    @Binding var predictionTopThree: Array<(key: String, value: Double)>
    var coordinatorContainer: CoordinatorContainer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        coordinatorContainer.coordinator = context.coordinator
        context.coordinator.setupCaptureSession(in: view)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
            context.coordinator.overlayLayer?.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(predictionLabel: $predictionLabel, progress: $progress, predictionTopThree: $predictionTopThree)
    }
}
