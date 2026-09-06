import SwiftUI
import WorkoutKit

@available(iOS 17.0, *)
struct TestView: View {
    @State var show = false
    @State var workout: CustomWorkout?

    var body: some View {
        Button("Test") {

        }
        .workoutPreview(workout, isPresented: $show)
    }
}
