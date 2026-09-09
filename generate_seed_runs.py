import random
import csv

def generate_safe_seed_data(num_samples=10000):
    runs = []
    
    for _ in range(num_samples):
        # 20% Edge Cases: High HR + Slow Pace = Hard Effort
        if random.random() < 0.20:
            avg_pace_sec = random.uniform(390.0, 540.0)
            avg_hr = random.uniform(165.0, 185.0)
            percent_zone4 = random.uniform(0.25, 0.85)
            workout_class = random.choice(["Threshold Run", "Tempo Run"])
            
        else:
            workout_class = random.choice([
                "Recovery Run", "Easy Run", "Steady Run", 
                "Progression Run", "Intervals"
            ])
            
            # Strict Zone 4 cap for Easy/Recovery
            if workout_class in ["Recovery Run", "Easy Run"]:
                percent_zone4 = random.uniform(0.0, 0.05)
                avg_hr = random.uniform(110.0, 145.0)
                avg_pace_sec = random.uniform(330.0, 480.0)
                
            elif workout_class in ["Steady Run", "Progression Run"]:
                percent_zone4 = random.uniform(0.05, 0.20)
                avg_hr = random.uniform(145.0, 165.0)
                avg_pace_sec = random.uniform(270.0, 360.0)
                
            else:
                percent_zone4 = random.uniform(0.30, 0.90)
                avg_hr = random.uniform(160.0, 190.0)
                avg_pace_sec = random.uniform(210.0, 300.0)

        runs.append({
            "averagePace": avg_pace_sec,
            "averageHeartRate": avg_hr,
            "percentZone4": percent_zone4,
            "averageCadence": random.uniform(140.0, 180.0),
            "verticalOscillation": random.uniform(7.0, 12.0),
            "runnerStage": random.choice([0, 1, 2]),
            "targetClass": workout_class
        })

    return runs

if __name__ == "__main__":
    try:
        import pandas as pd
        df = pd.DataFrame(generate_safe_seed_data(10000))
        df.to_csv("CoreML_Training_Data_v2.csv", index=False)
        print("Generated CoreML_Training_Data_v2.csv using pandas.")
    except ImportError:
        runs = generate_safe_seed_data(10000)
        keys = ["averagePace", "averageHeartRate", "percentZone4", "averageCadence", "verticalOscillation", "runnerStage", "targetClass"]
        with open("CoreML_Training_Data_v2.csv", "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=keys)
            writer.writeheader()
            writer.writerows(runs)
        print("Generated CoreML_Training_Data_v2.csv using standard csv module.")
