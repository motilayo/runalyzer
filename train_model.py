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

    # Quick test case similar to user's Rhythm Intervals screenshot
    # paceDelta: maybe fast (-60), hrDelta: high (25), percentZone4: high (0.8), cv: high (0.12)
    test_case = pd.DataFrame([{
        "paceDelta": -60.0,
        "hrDelta": 25.0,
        "percentZone4": 0.8,
        "cadenceDelta": 10.0,
        "verticalOscillation": 9.5,
        "cv": 0.12,
        "paceSlope": 0.0,
        "runnerStage": 1,
        "durationMinutes": 15.0,
        "cadenceCV": 0.045
    }])
    pred = model.predict(test_case)
    print(f"Quick Test Prediction: {pred[0]}")

    print("Converting to CoreML...")
    coreml_model = ct.converters.sklearn.convert(model, features, target)
    coreml_model.author = "Antigravity"
    coreml_model.short_description = "Runalyst AI Coach Classifier"
    
    # Save the model
    model_path = "RunalystClassifier.mlmodel"
    coreml_model.save(model_path)
    print(f"Successfully saved new model to {model_path}")

if __name__ == '__main__':
    train_and_export()
