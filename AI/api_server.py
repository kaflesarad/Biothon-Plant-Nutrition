#!/usr/bin/env python3
"""Smart AgroSense API server for pitch demo.

Serves:
- Frontend dashboard
- AI recommendation API
- Model metadata endpoints
"""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any

import joblib
import numpy as np
import pandas as pd
from flask import Flask, jsonify, request, send_from_directory
from flask_cors import CORS

PROJECT_ROOT = Path(__file__).resolve().parent.parent
FRONTEND_DIR = PROJECT_ROOT / "Frontend"
ARTIFACTS_DIR = Path(__file__).resolve().parent / "artifacts"
MODEL_PATH = ARTIFACTS_DIR / "nepal_crop_nutrient_model.joblib"
METRICS_PATH = ARTIFACTS_DIR / "training_metrics.json"

# Load MATLAB-generated training CSV for seasonal queries
TRAIN_CSV = PROJECT_ROOT / "data" / "nepal_training_from_matlab.csv"
try:
    _TRAIN_DF = pd.read_csv(TRAIN_CSV)
except Exception:
    _TRAIN_DF = None

VALID_REGIONS = {"Terai", "Hill", "Mountain"}
VALID_CLIMATE_ZONES = {
    "Tropical_Monsoon",
    "Subtropical_Humid",
    "Temperate_Hill",
    "Cool_Mountain",
    "Alpine_Cold",
}

# Disable Flask's automatic static route to avoid greedy root matching; serve
# frontend assets under /static/ instead.
app = Flask(__name__, static_folder=None, static_url_path=None)
CORS(app)

_MODEL_CACHE: dict[str, Any] | None = None


def load_model() -> dict[str, Any]:
    global _MODEL_CACHE

    if _MODEL_CACHE is not None:
        return _MODEL_CACHE

    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            f"Model not found at {MODEL_PATH}. Run MATLAB pipeline or train_nepal_ai.py first."
        )

    artifact = joblib.load(MODEL_PATH)
    _MODEL_CACHE = artifact
    return artifact


def clip(value: float, lo: float, hi: float) -> float:
    return float(min(hi, max(lo, value)))


def default_altitude_from_region(region: str) -> float:
    if region == "Terai":
        return 250.0
    if region == "Mountain":
        return 3000.0
    return 1400.0


def infer_region_from_altitude(altitude: float) -> str:
    if altitude >= 2200:
        return "Mountain"
    if altitude >= 700:
        return "Hill"
    return "Terai"


def infer_climate_zone(altitude: float, temperature: float, humidity: float, month: int) -> str:
    is_monsoon = 6 <= month <= 9

    if altitude >= 3400 or temperature <= 6:
        return "Alpine_Cold"
    if altitude >= 2200:
        return "Cool_Mountain"
    if altitude >= 1100:
        return "Temperate_Hill"
    if is_monsoon and humidity >= 65:
        return "Tropical_Monsoon"
    return "Subtropical_Humid"


def estimate_npk(ph: float, moisture: float, temperature: float, humidity: float) -> dict[str, float]:
    ph_penalty = max(0.0, 1.0 - abs(ph - 6.5) / 2.0)
    moist_factor = min(1.0, max(0.0, (moisture - 20.0) / 50.0))
    temp_factor = max(0.0, 1.0 - abs(temperature - 24.0) / 16.0)
    hum_factor = min(1.0, max(0.0, (humidity - 35.0) / 45.0))

    npk_base = 100.0 * (0.6 * ph_penalty + 0.4 * moist_factor)

    n_avail = npk_base * (0.85 + 0.25 * moist_factor - 0.10 * (1.0 - hum_factor))
    p_avail = npk_base * (0.85 + 0.30 * ph_penalty - 0.15 * (1.0 - temp_factor))
    k_avail = npk_base * (0.90 + 0.20 * ph_penalty + 0.05 * hum_factor)

    n_avail = clip(n_avail, 0.0, 100.0)
    p_avail = clip(p_avail, 0.0, 100.0)
    k_avail = clip(k_avail, 0.0, 100.0)

    return {
        "N_avail": n_avail,
        "P_avail": p_avail,
        "K_avail": k_avail,
        "NPK_composite": (n_avail + p_avail + k_avail) / 3.0,
    }


def fertility_label(value: float) -> str:
    if value < 35.0:
        return "Low"
    if value < 65.0:
        return "Medium"
    return "High"


def advisory(input_row: dict[str, float | str], prediction: dict[str, Any]) -> str:
    ph = float(input_row["pH"])
    moisture = float(input_row["moisture"])
    npk = float(prediction["soil_estimate"]["NPK_composite"])
    altitude = float(input_row.get("altitude_m", 1400.0))
    climate = str(input_row.get("climate_zone", "Subtropical_Humid"))

    if ph < 5.5:
        return "Soil is acidic. Add agricultural lime and organic compost before sowing."
    if ph > 7.8:
        return "Soil is alkaline. Use sulfur-rich amendments and organic matter."
    if moisture < 25:
        return "Field is dry. Increase irrigation frequency in short intervals."
    if moisture > 78:
        return "Field is over-wet. Improve drainage to avoid root disease."
    if npk < 35:
        return "Fertility is low. Apply balanced NPK basal dose and compost."
    if altitude >= 2600:
        return "High-altitude field detected. Prefer cold-tolerant crops and split phosphorus application."
    if climate == "Tropical_Monsoon":
        return "Monsoon-like climate detected. Use split nitrogen doses to reduce leaching losses."

    crop = prediction["best_crop"]
    return f"Conditions are favorable. Proceed with {crop} and monitor moisture weekly."


def normalize_payload(payload: dict[str, Any]) -> dict[str, Any]:
    now = datetime.now()

    month = payload.get("month", now.month)
    month = int(month)
    month = int(clip(month, 1, 12))

    altitude_raw = payload.get("altitude_m", None)
    try:
        altitude_m = float(altitude_raw) if altitude_raw not in (None, "") else None
    except (TypeError, ValueError):
        altitude_m = None

    raw_region = str(payload.get("region", "")).strip().title()
    if raw_region in VALID_REGIONS:
        region = raw_region
    elif altitude_m is not None:
        region = infer_region_from_altitude(altitude_m)
    else:
        region = "Hill"

    if altitude_m is None:
        altitude_m = default_altitude_from_region(region)
    altitude_m = clip(altitude_m, 60.0, 5200.0)

    ph = clip(float(payload.get("pH", 6.2)), 4.5, 8.5)
    moisture = clip(float(payload.get("moisture", 48.0)), 10.0, 90.0)
    temperature = clip(float(payload.get("temperature", 24.0)), 8.0, 40.0)
    humidity = clip(float(payload.get("humidity", 65.0)), 25.0, 95.0)

    raw_climate = str(payload.get("climate_zone", "")).strip()
    if raw_climate in VALID_CLIMATE_ZONES:
        climate_zone = raw_climate
    else:
        climate_zone = infer_climate_zone(altitude_m, temperature, humidity, month)

    has_npk = all(k in payload for k in ["N_avail", "P_avail", "K_avail", "NPK_composite"])

    if has_npk:
        npk_values = {
            "N_avail": clip(float(payload["N_avail"]), 0.0, 100.0),
            "P_avail": clip(float(payload["P_avail"]), 0.0, 100.0),
            "K_avail": clip(float(payload["K_avail"]), 0.0, 100.0),
            "NPK_composite": clip(float(payload["NPK_composite"]), 0.0, 100.0),
        }
    else:
        npk_values = estimate_npk(ph, moisture, temperature, humidity)

    row = {
        "region": region,
        "climate_zone": climate_zone,
        "month": month,
        "altitude_m": altitude_m,
        "pH": ph,
        "moisture": moisture,
        "temperature": temperature,
        "humidity": humidity,
        **npk_values,
    }

    return row


def top3(classes: np.ndarray, probs: np.ndarray) -> list[dict[str, Any]]:
    idx = np.argsort(probs)[::-1][:3]
    return [
        {
            "crop": str(classes[i]),
            "score_pct": round(float(probs[i] * 100.0), 2),
        }
        for i in idx
    ]


def predict_single(payload: dict[str, Any]) -> dict[str, Any]:
    artifact = load_model()

    feature_columns: list[str] = artifact["feature_columns"]
    crop_model = artifact["crop_model"]
    nutrient_models = artifact["nutrient_models"]

    row = normalize_payload(payload)

    x = pd.DataFrame([row])[feature_columns]

    crop_pred = str(crop_model.predict(x)[0])
    probs = crop_model.predict_proba(x)[0]
    class_names = crop_model.named_steps["model"].classes_

    nutrient_x = x.copy()
    nutrient_x["Crop"] = crop_pred

    n_dose = float(max(0.0, nutrient_models["N_apply_kg_ha"].predict(nutrient_x)[0]))
    p_dose = float(max(0.0, nutrient_models["P_apply_kg_ha"].predict(nutrient_x)[0]))
    k_dose = float(max(0.0, nutrient_models["K_apply_kg_ha"].predict(nutrient_x)[0]))

    top = top3(class_names, probs)

    result = {
        "input": row,
        "best_crop": crop_pred,
        "confidence_pct": round(float(np.max(probs) * 100.0), 2),
        "geo_context": {
            "region": row["region"],
            "climate_zone": row["climate_zone"],
            "altitude_m": round(float(row["altitude_m"]), 1),
        },
        "top_3": top,
        "nutrient_recommendation": {
            "N_kg_per_ha": round(n_dose, 2),
            "P_kg_per_ha": round(p_dose, 2),
            "K_kg_per_ha": round(k_dose, 2),
        },
        "soil_estimate": {
            "N_avail": round(float(row["N_avail"]), 2),
            "P_avail": round(float(row["P_avail"]), 2),
            "K_avail": round(float(row["K_avail"]), 2),
            "NPK_composite": round(float(row["NPK_composite"]), 2),
            "N_status": fertility_label(float(row["N_avail"])),
            "P_status": fertility_label(float(row["P_avail"])),
            "K_status": fertility_label(float(row["K_avail"])),
        },
    }

    result["advisory"] = advisory(row, result)
    return result


@app.get("/")
def index() -> Any:
    return send_from_directory(FRONTEND_DIR, "Frontpage.html")


@app.get('/static/<path:filename>')
def frontend_static(filename: str) -> Any:
    # Serve JS/CSS and other frontend assets from the Frontend directory
    return send_from_directory(FRONTEND_DIR, filename)


@app.get("/api/health")
def health() -> Any:
    model_ready = MODEL_PATH.exists()
    return jsonify(
        {
            "status": "ok",
            "model_ready": model_ready,
            "model_path": str(MODEL_PATH),
            "timestamp": datetime.utcnow().isoformat() + "Z",
        }
    )


@app.get("/api/model-info")
def model_info() -> Any:
    metrics = None
    if METRICS_PATH.exists():
        try:
            metrics = json.loads(METRICS_PATH.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            metrics = None

    return jsonify(
        {
            "model_exists": MODEL_PATH.exists(),
            "model_path": str(MODEL_PATH),
            "metrics": metrics,
        }
    )


@app.get('/api/debug-seasonal')
def debug_seasonal() -> Any:
    return jsonify({"ok": True, "note": "debug seasonal endpoint reachable"})


@app.get('/api/seasonal-crops')
@app.get('/api/seasonal_crops')
def seasonal_crops() -> Any:
    """
    Return crops that are in-season for a given region and month inferred
    from the MATLAB-generated training CSV by frequency.
    Query params:
      - region (optional): Terai, Hill, Mountain
      - month  (optional): 1-12 (defaults to current month)
    """
    print(f"[DEBUG] seasonal_crops called; args={{}}".format(request.args))
    if _TRAIN_DF is None:
        return jsonify({"error": "training data not available", "path": str(TRAIN_CSV)}), 500

    region_q = request.args.get("region", None)
    month_q = request.args.get("month", None)
    try:
        month = int(month_q) if month_q is not None else datetime.utcnow().month
    except Exception:
        return jsonify({"error": "invalid month"}), 400

    df = _TRAIN_DF.copy()
    print(f"[DEBUG] TRAIN_CSV={TRAIN_CSV} df_columns={list(df.columns)} df_shape={df.shape}", flush=True)
    try:
        print(f"[DEBUG] df sample:\n{df.head().to_dict(orient='records')}", flush=True)
    except Exception:
        pass

    # Support case-insensitive column names from MATLAB export
    cols_lower = {c.lower(): c for c in df.columns}
    crop_col = cols_lower.get("crop")
    region_col = cols_lower.get("region")
    month_col = cols_lower.get("month")

    if region_col and region_q:
        df = df[df[region_col].astype(str).str.lower() == region_q.lower()]
    if month_col:
        try:
            df = df[df[month_col].astype(int) == int(month)]
        except Exception:
            # If month column isn't integer-typed, coerce where possible
            df = df[df[month_col].astype(str) == str(int(month))]

    if df.empty:
        # broaden fallback: try month-only, then region-only
        if "month" in _TRAIN_DF.columns:
            df = _TRAIN_DF[_TRAIN_DF["month"] == int(month)]
        else:
            df = _TRAIN_DF

        if region_q and df.empty:
            df = _TRAIN_DF[_TRAIN_DF["region"].astype(str).str.lower() == region_q.lower()]

    if df.empty:
        return jsonify({"region": region_q, "month": month, "in_season_crops": []})

    if crop_col and crop_col in df.columns:
        counts = df[crop_col].astype(str).value_counts()
        crops = counts.index.tolist()
        # ensure JSON-serializable counts (plain ints)
        counts_dict = {str(k): int(v) for k, v in counts.to_dict().items()}
    else:
        # best-effort fallback: any column named like crop
        crops = []
        counts_dict = {}

    return jsonify({
        "region": region_q,
        "month": int(month),
        "in_season_crops": crops,
        "count_by_crop": counts_dict,
    })


@app.post("/api/recommend")
def recommend() -> Any:
    if not request.is_json:
        return jsonify({"error": "Request must be JSON."}), 400

    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Invalid JSON payload."}), 400

    try:
        result = predict_single(payload)
        return jsonify(result)
    except FileNotFoundError as exc:
        return jsonify({"error": str(exc)}), 503
    except (TypeError, ValueError) as exc:
        return jsonify({"error": f"Invalid input: {exc}"}), 400
    except Exception as exc:  # noqa: BLE001
        return jsonify({"error": f"Prediction failed: {exc}"}), 500


@app.post("/api/recommend-batch")
def recommend_batch() -> Any:
    if not request.is_json:
        return jsonify({"error": "Request must be JSON."}), 400

    payload = request.get_json(silent=True)
    if not isinstance(payload, list):
        return jsonify({"error": "Batch payload must be a JSON array."}), 400

    try:
        results = [predict_single(item if isinstance(item, dict) else {}) for item in payload]
        return jsonify({"count": len(results), "results": results})
    except FileNotFoundError as exc:
        return jsonify({"error": str(exc)}), 503
    except (TypeError, ValueError) as exc:
        return jsonify({"error": f"Invalid input: {exc}"}), 400
    except Exception as exc:  # noqa: BLE001
        return jsonify({"error": f"Batch prediction failed: {exc}"}), 500


def main() -> None:
    print("[INFO] Registered routes:\n" + '\n'.join(sorted(str(r) for r in app.url_map.iter_rules())))


@app.before_request
def log_request_info() -> None:
    try:
        print(f"[REQUEST] {request.method} {request.path} args={dict(request.args)} remote={request.remote_addr}", flush=True)
    except Exception:
        print("[REQUEST] failed to log request info", flush=True)


@app.route('/api/<path:subpath>', methods=['GET', 'POST', 'OPTIONS'])
def api_catcher(subpath: str) -> Any:
    # Generic catcher for API paths to help debug routing issues.
    try:
        print(f"[API_CATCHER] path={subpath} method={request.method} args={dict(request.args)}", flush=True)
    except Exception:
        print("[API_CATCHER] failed to log", flush=True)

    # If a specific route exists, Flask will route to it; this function only runs
    # if a request reaches a path that doesn't match an explicit rule.
    return jsonify({"caught": subpath, "args": dict(request.args)}), 200


@app.get('/seasonal-crops.json')
def seasonal_crops_json() -> Any:
    # Allow a root-level JSON path for clients that may avoid /api/ prefix
    return seasonal_crops()
    app.run(host="127.0.0.1", port=8000, debug=False)


if __name__ == "__main__":
    main()
