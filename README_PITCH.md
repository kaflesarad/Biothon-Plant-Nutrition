# Smart AgroSense Nepal - Pitch Ready Product

Smart AgroSense is now a fully working product with a live frontend and production-style AI backend:

- MATLAB simulates Nepal-specific agricultural data
- Python trains crop + NPK recommendation models
- Flask API serves predictions in real time
- Frontend dashboard provides weather + map + AI advisory in one view

## Product Architecture

1. MATLAB data generation:
- `export_nepal_matlab_data.m`
- Outputs training + latest sensor CSV under `data/`

2. Python AI:
- Training: `AI/train_nepal_ai.py`
- Inference API: `AI/api_server.py`
- Artifacts: `AI/artifacts/nepal_crop_nutrient_model.joblib`, `AI/artifacts/training_metrics.json`

3. Frontend:
- `Frontend/Frontpage.html`
- `Frontend/styles.css`
- `Frontend/app.js`

## One-Command Pitch Launch (Windows)

From workspace root:

```powershell
.\launch_pitch_demo.ps1
```

This will:
- install Python dependencies
- generate/train model if missing
- start API server on `http://127.0.0.1:8000`
- open the dashboard in your browser

Fast start when model already exists:

```powershell
.\launch_pitch_demo.ps1 -SkipPrepare
```

## Manual Run (if needed)

1. Build full MATLAB+Python pipeline:

```powershell
matlab -batch "SmartAgroSense_Final_Product"
```

2. Start API server:

```powershell
.venv\Scripts\python.exe AI\api_server.py
```

3. Open dashboard:
- `http://127.0.0.1:8000`

## Live Demo Flow (for judges)

1. Show map + live weather auto-detection
2. Click **Use Live Weather** in AI panel
3. Click **Get AI Recommendation**
4. Present:
- Best crop + confidence
- Top-3 crops
- N, P, K recommendation doses (kg/ha)
- Advisory text for farmers

## API Endpoints

- `GET /api/health`
- `GET /api/model-info`
- `POST /api/recommend`
- `POST /api/recommend-batch`

Example payload for `POST /api/recommend`:

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

## Current Model Performance

From latest trained metrics:
- Crop accuracy: **93.00%**
- Nutrient pipeline MAE (kg/ha):
  - N: **4.44**
  - P: **2.93**
  - K: **2.96**

These values are also available at runtime from `GET /api/model-info`.
