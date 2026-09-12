import csv
import random

try:
    import pandas as pd
    import numpy as np
    HAS_PANDAS = True
except ImportError:
    HAS_PANDAS = False

def generate_smooth_seed_data(num_samples=15000):
    runs = []
    
    for _ in range(num_samples):
        # Pick a base archetype smoothly
        archetype = random.choices(
            ["Recovery", "Easy", "Steady", "Progression", "Tempo", "Intervals"],
            weights=[0.15, 0.25, 0.25, 0.15, 0.10, 0.10]
        )[0]
        
        if archetype == "Recovery":
            avg_pace_sec = random.gauss(480, 15)       # ~8:00/km
            avg_hr = random.gauss(120, 5)              # Low HR
            percent_zone4 = random.betavariate(1, 20)  # Skewed heavily toward 0%
            workout_class = "Recovery Run"
            
        elif archetype == "Easy":
            avg_pace_sec = random.gauss(400, 15)       # ~6:40/km
            avg_hr = random.gauss(135, 5)
            percent_zone4 = random.betavariate(1, 10)   # Very low Zone 4
            workout_class = "Easy Run"
            
        elif archetype == "Steady":
            # This covers the 5:40 - 6:00 pace range with moderate HR
            avg_pace_sec = random.gauss(350, 15)       # ~5:50/km
            avg_hr = random.gauss(150, 5)              
            percent_zone4 = random.betavariate(2, 8)   # Moderate spread
            workout_class = "Steady Effort"
            
        elif archetype == "Progression":
            avg_pace_sec = random.gauss(310, 15)       # ~5:10/km
            avg_hr = random.gauss(165, 5)
            percent_zone4 = random.betavariate(4, 4)
            workout_class = "Progression Run"
            
        elif archetype == "Tempo":
            # True structured fast effort with high anaerobic load
            avg_pace_sec = random.gauss(270, 15)       # ~4:30/km
            avg_hr = random.gauss(178, 4)
            percent_zone4 = random.betavariate(8, 2)   # High Zone 4
            workout_class = "Tempo Run"
            
        else: # Intervals
            avg_pace_sec = random.gauss(220, 15)       # ~3:40/km
            avg_hr = random.gauss(188, 4)
            percent_zone4 = random.betavariate(10, 1)
            workout_class = "Intervals"

        # Clamp values to realistic human bounds
        avg_pace_sec = float(max(200.0, min(550.0, avg_pace_sec)))
        avg_hr = float(max(100.0, min(195.0, avg_hr)))
        percent_zone4 = float(max(0.0, min(1.0, percent_zone4)))
        cadence = float(max(130.0, min(185.0, random.gauss(152, 6))))
        osc = float(max(6.0, min(14.0, random.gauss(10.2, 0.8))))

        runs.append({
            "averagePace": avg_pace_sec,
            "averageHeartRate": avg_hr,
            "percentZone4": percent_zone4,
            "averageCadence": cadence,
            "verticalOscillation": osc,
            "runnerStage": random.choice([0, 1, 2]),
            "targetClass": workout_class
        })

    return runs

def export_v3_dataset():
    runs = generate_smooth_seed_data(15000)
    output_filename = "CoreML_Training_Data_v3.csv"
    
    if HAS_PANDAS:
        df = pd.DataFrame(runs)
        df.to_csv(output_filename, index=False)
    else:
        fieldnames = ["averagePace", "averageHeartRate", "percentZone4", "averageCadence", "verticalOscillation", "runnerStage", "targetClass"]
        with open(output_filename, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(runs)
            
    print("Continuous probability dataset v3 exported successfully.")

if __name__ == "__main__":
    export_v3_dataset()
