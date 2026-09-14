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
        # Assign Runner Stage (0 = Beginner, 1 = Intermediate, 2 = Advanced, 3 = Elite)
        runner_stage = random.choices([0, 1, 2, 3], weights=[0.40, 0.35, 0.20, 0.05])[0]
        
        # Base Biomechanics by Stage
        if runner_stage == 0:
            base_cad = 148
            base_osc = 11.5
            cv_multiplier = 1.2
        elif runner_stage == 1:
            base_cad = 158
            base_osc = 10.0
            cv_multiplier = 1.0
        elif runner_stage == 2:
            base_cad = 168
            base_osc = 8.5
            cv_multiplier = 0.85
        else: # Elite
            base_cad = 180
            base_osc = 6.5
            cv_multiplier = 0.70
            
        cadence = float(max(130.0, min(195.0, random.gauss(base_cad, 5))))
        osc = float(max(5.0, min(15.0, random.gauss(base_osc, 1.0))))

        # Pick a base archetype smoothly
        archetype = random.choices(
            ["Recovery", "Easy", "Steady", "Progression", "Tempo", "Fartlek", "Intervals"],
            weights=[0.15, 0.20, 0.20, 0.15, 0.10, 0.10, 0.10]
        )[0]
        
        if archetype == "Recovery":
            pace_delta = random.gauss(60, 15)          # Slower than baseline
            hr_delta = random.gauss(-25, 5)            # Much lower HR
            percent_zone4 = random.betavariate(1, 20)  
            cv = random.gauss(0.015, 0.004)
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(-5, 2)
            workout_class = "Recovery Run"
            
        elif archetype == "Easy":
            pace_delta = random.gauss(30, 15)          # Slightly slower than baseline
            hr_delta = random.gauss(-15, 5)
            percent_zone4 = random.betavariate(1, 10)   
            cv = random.gauss(0.022, 0.008)
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(-2, 2)
            workout_class = "Easy Run"
            
        elif archetype == "Steady":
            # 85% normal steady, 15% 'fly and die' pacing fade
            is_pacing_fade = random.random() < 0.15
            pace_delta = random.gauss(0, 15)           # Anchor: baseline pace
            hr_delta = random.gauss(0, 5)              # Anchor: baseline HR
            percent_zone4 = random.betavariate(2, 8)   
            cadence_delta = random.gauss(0, 2)
            if is_pacing_fade:
                cv = random.gauss(0.09, 0.015)          
                pace_slope = random.gauss(0.375, 0.075)    
            else:
                cv = random.gauss(0.038, 0.008)
                pace_slope = random.gauss(0.0, 0.038)
            workout_class = "Steady Effort"
            
        elif archetype == "Progression":
            pace_delta = random.gauss(-30, 15)         # Faster overall
            hr_delta = random.gauss(15, 5)
            percent_zone4 = random.betavariate(4, 4)
            cv = random.gauss(0.052, 0.008)
            pace_slope = random.gauss(-0.338, 0.075)      # Negative slope
            cadence_delta = random.gauss(5, 2)
            workout_class = "Progression Run"
            
        elif archetype == "Tempo":
            pace_delta = random.gauss(-60, 15)         # Much faster
            hr_delta = random.gauss(25, 4)
            percent_zone4 = random.betavariate(8, 2)   
            cv = random.gauss(0.06, 0.011)
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(10, 2)
            workout_class = "Tempo Run"
            
        elif archetype == "Fartlek":
            pace_delta = random.gauss(-15, 20)         # Slightly faster average
            hr_delta = random.gauss(15, 6)
            percent_zone4 = random.betavariate(3, 7)   
            cv = random.gauss(0.09, 0.011)             # High variance
            pace_slope = random.gauss(0.0, 0.038)       
            cadence_delta = random.gauss(5, 3)
            workout_class = "Fartlek"
            
        else: # Intervals
            pace_delta = random.gauss(-90, 15)         # Much faster
            hr_delta = random.gauss(35, 4)
            percent_zone4 = random.betavariate(10, 1)
            cv = random.gauss(0.135, 0.015)              # Very high variance
            pace_slope = random.gauss(0.0, 0.038)
            cadence_delta = random.gauss(15, 3)
            workout_class = "Intervals"

        # Clamp values to realistic human bounds for deltas
        pace_delta = float(max(-300.0, min(300.0, pace_delta)))
        hr_delta = float(max(-60.0, min(80.0, hr_delta)))
        cadence_delta = float(max(-30.0, min(40.0, cadence_delta)))
        percent_zone4 = float(max(0.0, min(1.0, percent_zone4)))
        # Apply CV multiplier based on runner experience
        cv = float(max(0.0, min(0.35, cv * cv_multiplier)))

        runs.append({
            "paceDelta": pace_delta,
            "hrDelta": hr_delta,
            "percentZone4": percent_zone4,
            "cadenceDelta": cadence_delta,
            "verticalOscillation": osc,
            "cv": cv,
            "paceSlope": pace_slope,
            "runnerStage": runner_stage,
            "targetClass": workout_class
        })

    return runs

def export_v5_dataset():
    train_runs = generate_smooth_seed_data(35000)
    test_runs = generate_smooth_seed_data(5000)
    
    if HAS_PANDAS:
        df_train = pd.DataFrame(train_runs)
        df_test = pd.DataFrame(test_runs)
        df_train.to_csv("CoreML_Training_Data_v5.csv", index=False)
        df_test.to_csv("CoreML_Testing_Data_v5.csv", index=False)
    else:
        fieldnames = ["paceDelta", "hrDelta", "percentZone4", "cadenceDelta", "verticalOscillation", "cv", "paceSlope", "runnerStage", "targetClass"]
        for runs, filename in [(train_runs, "CoreML_Training_Data_v5.csv"), (test_runs, "CoreML_Testing_Data_v5.csv")]:
            with open(filename, "w", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(runs)
            
    print("Generated v5 datasets for dynamic runner stages.")

if __name__ == "__main__":
    export_v5_dataset()
