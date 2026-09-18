import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score
import coremltools as ct

def train_and_export():
    # Load data
    print("Loading data...")
    train_df = pd.read_csv("CoreML_Training_Data_v5.csv")
    test_df = pd.read_csv("CoreML_Testing_Data_v5.csv")

    features = [
        "paceDelta", "hrDelta", "percentZone4", "cadenceDelta", 
        "verticalOscillation", "cv", "paceSlope", "runnerStage",
        "durationMinutes", "cadenceCV"
    ]
    target = "targetClass"

    X_train = train_df[features]
    y_train = train_df[target]
    X_test = test_df[features]
    y_test = test_df[target]

    print("Training RandomForestClassifier...")
    model = RandomForestClassifier(n_estimators=150, max_depth=12, random_state=42)
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    acc = accuracy_score(y_test, y_pred)
    print(f"Model Accuracy on Test Set: {acc * 100:.2f}%")

    # Test suite covering crucial real-world cases:
    test_cases = [
        ("Rhythm Intervals Drill", {
            "paceDelta": -60.0, "hrDelta": 25.0, "percentZone4": 0.8,
            "cadenceDelta": 10.0, "verticalOscillation": 9.5, "cv": 0.12,
            "paceSlope": 0.0, "runnerStage": 1, "durationMinutes": 15.0, "cadenceCV": 0.045
        }, "Intervals"),
        ("Steady Effort with High HR / Cardiac Drift", {
            "paceDelta": 0.0, "hrDelta": 20.0, "percentZone4": 0.80,
            "cadenceDelta": 1.0, "verticalOscillation": 9.9, "cv": 0.08,
            "paceSlope": -0.05, "runnerStage": 1, "durationMinutes": 27.0, "cadenceCV": 0.012
        }, "Steady Effort"),
        ("True Fartlek (Cadence & Pace Surges)", {
            "paceDelta": -20.0, "hrDelta": 18.0, "percentZone4": 0.45,
            "cadenceDelta": 6.0, "verticalOscillation": 9.5, "cv": 0.10,
            "paceSlope": 0.0, "runnerStage": 1, "durationMinutes": 35.0, "cadenceCV": 0.042
        }, "Fartlek"),
        ("Pure Tempo Run (Fast Paced Threshold)", {
            "paceDelta": -55.0, "hrDelta": 25.0, "percentZone4": 0.85,
            "cadenceDelta": 10.0, "verticalOscillation": 9.0, "cv": 0.05,
            "paceSlope": 0.0, "runnerStage": 1, "durationMinutes": 45.0, "cadenceCV": 0.014
        }, "Tempo Run"),
        ("Easy Recovery Run", {
            "paceDelta": 45.0, "hrDelta": -20.0, "percentZone4": 0.01,
            "cadenceDelta": -4.0, "verticalOscillation": 10.2, "cv": 0.02,
            "paceSlope": 0.0, "runnerStage": 1, "durationMinutes": 25.0, "cadenceCV": 0.011
        }, "Recovery Run"),
    ]

    print("\n--- Validation Test Suite ---")
    all_passed = True
    for name, data, expected in test_cases:
        pred = model.predict(pd.DataFrame([data]))[0]
        match = "✓" if pred == expected else "✗"
        if pred != expected:
            all_passed = False
        print(f"[{match}] {name}: Predicted '{pred}' (Expected '{expected}')")

    if not all_passed:
        print("\nWarning: Some validation cases did not match expected class.")

    print("\nConverting to CoreML...")
    coreml_model = ct.converters.sklearn.convert(model, features, target)
    coreml_model.author = "Antigravity"
    coreml_model.short_description = "Runalyst AI Coach Classifier"
    
    # Save the model
    model_path = "RunalystClassifier.mlmodel"
    coreml_model.save(model_path)
    print(f"Successfully saved new model to {model_path}")

if __name__ == '__main__':
    train_and_export()
