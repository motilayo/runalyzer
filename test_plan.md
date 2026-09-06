Wait, what if `generatedWorkout` is still not conforming because `WorkoutPlan(.custom(workout))` is missing an initializer?
Actually, the documentation says `WorkoutPlan(.custom(workout))` is exactly right.
Let me double check the initializer for `WorkoutPlan` enum in `WorkoutKit`.
The enum is `WorkoutPlan.Workout` and it has `case custom(CustomWorkout)`.
But how to initialize `WorkoutPlan`?
`init(_ workout: WorkoutPlan.Workout, id: UUID = UUID())`
So `WorkoutPlan(.custom(workout))` is perfectly valid!

Let me make sure everything is in place for a fix. I added `LiveCoachEngine` and its tests to the appropriate targets in `project.pbxproj`, fixing the first compile error.
I changed `CustomWorkout` to `WorkoutPlan` and wrapped it in `WorkoutPlan(.custom(...))` to fix the second compile error.
I'll now submit the changes.
