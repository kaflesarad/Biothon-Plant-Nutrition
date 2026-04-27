# Mato

Mato is a location-aware crop and nutrient advisory system built for Nepal. It combines MATLAB simulation, Python machine learning, a Flask API, and a browser dashboard.

## What This Project Does

- Simulates Nepal farming conditions with altitude and climate effects.
- Trains AI models for:
  - best crop recommendation
  - nutrient dose prediction (`N`, `P`, `K` in kg/ha)
- Serves predictions through REST APIs.
- Shows recommendations in a live map + weather dashboard.

## End-to-End Architecture

```text
MATLAB Layer
  export_nepal_matlab_data.m
  -> data/nepal_training_from_matlab.csv
  -> data/nepal_latest_sensor_from_matlab.csv

Python Training Layer
  AI/train_nepal_ai.py
  -> AI/artifacts/nepal_crop_nutrient_model.joblib
  -> AI/artifacts/training_metrics.json

Python Inference/API Layer
  AI/predict_nepal_ai.py
  AI/api_server.py
  -> outputs/nepal_python_recommendations.csv
  -> outputs/final_product_summary.txt

Frontend Layer
  Frontend/Frontpage.html
  Frontend/app.js
  Frontend/styles.css
  -> consumes /api/* endpoints
```

## Key Design Choices

### 1. Location-aware recommendations
The model pipeline uses both:
- `altitude_m`
- `climate_zone`

`climate_zone` is inferred from altitude + weather + month when not explicitly provided.

### 2. Nepal-specific regional logic
Supported regions:
- `Terai`
- `Hill`
- `Mountain`

Default altitude fallback:
- Terai: `250m`
- Hill: `1400m`
- Mountain: `3000m`

### 3. Robust training split
`AI/train_nepal_ai.py` uses stratified split when every crop class has at least 2 samples, and automatically falls back to non-stratified split otherwise.

### 4. Safe preprocessing for inference
`AI/predict_nepal_ai.py` auto-fills missing context (`region`, `month`, `altitude_m`, `climate_zone`) and clips physical ranges.

## Tech Stack

- MATLAB + Simulink (data simulation + orchestration)
- Python 3.x
- scikit-learn (RandomForest classifier/regressors)
- pandas, numpy, joblib
- Flask + Flask-CORS
- HTML/CSS/JavaScript (vanilla)
- Leaflet + Open-Meteo + Nominatim (frontend integrations)

## Repository Structure

```text
test/
  AI/
    api_server.py
    train_nepal_ai.py
    predict_nepal_ai.py
    requirements.txt
    artifacts/
      nepal_crop_nutrient_model.joblib
      training_metrics.json
  Frontend/
    Frontpage.html
    app.js
    styles.css
  data/
    nepal_training_from_matlab.csv
    nepal_latest_sensor_from_matlab.csv
  outputs/
    nepal_python_recommendations.csv
    final_product_summary.txt
  SmartAgroSense_Final_Product.m
  run_nepal_matlab_python_pipeline.m
  export_nepal_matlab_data.m
  launch_pitch_demo.ps1
  README_PITCH.md
```

## Setup

### Prerequisites

- MATLAB with Simulink available from terminal (`matlab -batch ...`)
- Python virtual environment in `.venv` (recommended)

### Install Python deps

```powershell
.\.venv\Scripts\python.exe -m pip install -r AI/requirements.txt
```

## Quick Start (Pitch Demo)

```powershell
.\launch_pitch_demo.ps1
```

Fast start (skip data/model preparation if model already exists):

```powershell
.\launch_pitch_demo.ps1 -SkipPrepare
```

## Manual Run

### 1) Full MATLAB -> Python pipeline

```powershell
matlab -batch "SmartAgroSense_Final_Product"
```

This performs:
- model build/simulation
- MATLAB data export
- Python training
- Python inference
- summary generation

### 2) Start API server

```powershell
.\.venv\Scripts\python.exe AI\api_server.py
```

### 3) Open dashboard

- http://127.0.0.1:8000

## API Reference

Base URL: `http://127.0.0.1:8000`

### GET /api/health

Returns server status and model path.

Example response:

```json
{
  "status": "ok",
  "model_ready": true,
  "model_path": "C:\\...\\AI\\artifacts\\nepal_crop_nutrient_model.joblib",
  "timestamp": "2026-04-27T...Z"
}
```

### GET /api/model-info

Returns model presence and nested training metrics from `training_metrics.json`.

Example response:

```json
{
  "model_exists": true,
  "model_path": "C:\\...\\AI\\artifacts\\nepal_crop_nutrient_model.joblib",
  "metrics": {
    "samples_total": 12000,
    "samples_train": 9600,
    "samples_test": 2400,
    "crop_accuracy": 0.9283333333333333,
    "nutrient_metrics": {
      "N_apply_kg_ha": { "mae_pipeline": 4.5455 },
      "P_apply_kg_ha": { "mae_pipeline": 2.8275 },
      "K_apply_kg_ha": { "mae_pipeline": 2.7970 }
    }
  }
}
```

### POST /api/recommend

Accepts a JSON object. Missing fields are inferred/defaulted when possible.

Minimal example request:

```json
{
  "region": "Hill",
  "month": 5,
  "pH": 6.2,
  "moisture": 52,
  "temperature": 24,
  "humidity": 68
}
```

Example response fields:

- `best_crop`
- `confidence_pct`
- `geo_context` (`region`, `climate_zone`, `altitude_m`)
- `top_3` (array of `{ crop, score_pct }`)
- `nutrient_recommendation` (`N_kg_per_ha`, `P_kg_per_ha`, `K_kg_per_ha`)
- `soil_estimate` (`N_avail`, `P_avail`, `K_avail`, `NPK_composite`, status labels)
- `advisory`

### POST /api/recommend-batch

Accepts a JSON array of request objects (not wrapped in another object).

Example request:

```json
[
  { "region": "Terai", "month": 6, "pH": 6.5, "moisture": 55, "temperature": 28, "humidity": 70 },
  { "region": "Hill", "month": 5, "pH": 6.2, "moisture": 52, "temperature": 24, "humidity": 68 }
]
```

Example response:

```json
{
  "count": 2,
  "results": [
    { "best_crop": "..." },
    { "best_crop": "..." }
  ]
}
```

## Current Performance (From Latest Artifact)

From `AI/artifacts/training_metrics.json`:

- `samples_total`: `12000`
- `crop_accuracy`: `0.9283333333333333` (92.83%)
- pipeline MAE:
  - `N_apply_kg_ha`: `4.5456`
  - `P_apply_kg_ha`: `2.8275`
  - `K_apply_kg_ha`: `2.7970`

## Demo Flow (For Judges)

1. Start with `.\launch_pitch_demo.ps1`.
2. Show auto location + weather on dashboard.
3. Click **Use Live Weather**.
4. Click **Get AI Recommendation**.
5. Explain:
   - best crop + confidence
   - top 3 crop alternatives
   - N/P/K dose recommendation
   - advisory text

## Known Notes

- MATLAB may show a warning that model name `SmartAgroSense` shadows another name. Pipeline still runs, but renaming the Simulink model would remove the warning.

## Troubleshooting

### API not reachable on port 8000

- Start server manually:

```powershell
.\.venv\Scripts\python.exe AI\api_server.py
```

### Missing Python packages

```powershell
.\.venv\Scripts\python.exe -m pip install -r AI/requirements.txt
```

### Rebuild model artifacts

```powershell
matlab -batch "run_nepal_matlab_python_pipeline"
```

---

Last validated: 2026-04-27
