import SwiftUI
import AVFoundation
import Vision
import CoreML

struct ContentView: View {
    @State private var predictionLabel: String = "No Action"
    @State private var bufferProgress: Double = 0.0  // Progress from 0.0 to 1.0
    @State private var predictionTopThree: Array<(key: String, value: Double)> = []
    @StateObject private var coordinatorContainer = CoordinatorContainer()
    
    
    var body: some View {
        ZStack {
            CameraView(predictionLabel: $predictionLabel, progress: $bufferProgress, predictionTopThree: $predictionTopThree, coordinatorContainer: coordinatorContainer
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    VStack {
                        ForEach(predictionTopThree, id: \.key) { key, value in
                            Text("\(key): \(String(format: "%.2f%%", value * 100))")
                        }
                    }
                    .padding()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .border(Color.black)
                    Spacer()
                    
                    Button(action: {
                        if let coordinator = coordinatorContainer.coordinator,
                           let rootView = UIApplication.shared.windows.first?.rootViewController?.view {
                            coordinator.switchCamera(in: rootView)
                        }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .padding()
                            .background(Color.white.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                
                
                Spacer()
                //The circular progress bar that fills during a hand action
                CircularProgressBar(progress: bufferProgress)
                    .frame(width: 50, height: 50)
                    .padding()
                
                
                Text("\(predictionLabel)")
                    .font(.title)
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
            }
            .padding(.bottom, 20)
            
            
        }
    }
}

class CoordinatorContainer: ObservableObject {
    var coordinator: Coordinator?
}




struct CircularProgressBar: View {
    var progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 10)
            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(Angle(degrees: -90)) // Start from top.
                .animation(progress == 0 ? nil : .linear, value: progress)
        }
    }
}
