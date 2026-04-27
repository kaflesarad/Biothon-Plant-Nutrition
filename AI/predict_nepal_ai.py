#!/usr/bin/env python3
"""Run inference for Nepal crop + nutrient recommendation using trained model."""

from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

BASE_SENSOR_COLUMNS = ["pH", "moisture", "temperature", "humidity"]
NPK_COLUMNS = ["N_avail", "P_avail", "K_avail", "NPK_composite"]
VALID_REGIONS = {"Terai", "Hill", "Mountain"}
VALID_CLIMATE_ZONES = {
    "Tropical_Monsoon",
    "Subtropical_Humid",
    "Temperate_Hill",
    "Cool_Mountain",
    "Alpine_Cold",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Predict Nepal crop and nutrient recommendations")
    parser.add_argument("--model", required=True, help="Model artifact (.joblib)")
    parser.add_argument("--input-csv", required=True, help="Input sensor CSV from MATLAB")
    parser.add_argument("--output-csv", required=True, help="Output CSV with recommendations")
    return parser.parse_args()


def validate_columns(df: pd.DataFrame, required: list[str], source_name: str) -> None:
    missing = [col for col in required if col not in df.columns]
    if missing:
        raise ValueError(f"{source_name} missing required columns: {missing}")


def clip_series(series: pd.Series, lo: float, hi: float) -> pd.Series:
    return series.clip(lower=lo, upper=hi)


def estimate_npk_components(df: pd.DataFrame) -> pd.DataFrame:
    ph = df["pH"].astype(float)
    moist = df["moisture"].astype(float)
    temp = df["temperature"].astype(float)
    hum = df["humidity"].astype(float)

    ph_penalty = (1 - (ph - 6.5).abs() / 2.0).clip(lower=0)
    moist_factor = ((moist - 20) / 50).clip(lower=0, upper=1)
    temp_factor = (1 - (temp - 24).abs() / 16).clip(lower=0)
    hum_factor = ((hum - 35) / 45).clip(lower=0, upper=1)

    npk_base = 100 * (0.6 * ph_penalty + 0.4 * moist_factor)

    n_avail = npk_base * (0.85 + 0.25 * moist_factor - 0.10 * (1 - hum_factor))
    p_avail = npk_base * (0.85 + 0.30 * ph_penalty - 0.15 * (1 - temp_factor))
    k_avail = npk_base * (0.90 + 0.20 * ph_penalty + 0.05 * hum_factor)

    n_avail = n_avail.clip(lower=0, upper=100)
    p_avail = p_avail.clip(lower=0, upper=100)
    k_avail = k_avail.clip(lower=0, upper=100)
    npk = (n_avail + p_avail + k_avail) / 3

    out = df.copy()
    out["N_avail"] = n_avail
    out["P_avail"] = p_avail
    out["K_avail"] = k_avail
    out["NPK_composite"] = npk
    return out


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


def ensure_location_features(df: pd.DataFrame, feature_columns: list[str]) -> pd.DataFrame:
    out = df.copy()

    if "region" not in out.columns:
        out["region"] = "Hill"
    out["region"] = out["region"].astype(str).str.strip().str.title()
    out.loc[~out["region"].isin(VALID_REGIONS), "region"] = "Hill"

    if "month" not in out.columns:
        out["month"] = datetime.now().month
    out["month"] = pd.to_numeric(out["month"], errors="coerce").fillna(datetime.now().month)
    out["month"] = out["month"].clip(lower=1, upper=12).round().astype(int)

    needs_altitude = "altitude_m" in feature_columns
    needs_climate = "climate_zone" in feature_columns

    if needs_altitude:
        if "altitude_m" not in out.columns:
            out["altitude_m"] = out["region"].map(default_altitude_from_region).astype(float)
        else:
            out["altitude_m"] = pd.to_numeric(out["altitude_m"], errors="coerce")
            missing_alt = out["altitude_m"].isna()
            out.loc[missing_alt, "altitude_m"] = out.loc[missing_alt, "region"].map(default_altitude_from_region).astype(float)
        out["altitude_m"] = out["altitude_m"].clip(lower=60, upper=5200)

        missing_region = out["region"].isna() | (out["region"] == "")
        out.loc[missing_region, "region"] = out.loc[missing_region, "altitude_m"].apply(infer_region_from_altitude)

    if needs_climate:
        def _derive_climate(row: pd.Series) -> str:
            altitude = float(row.get("altitude_m", default_altitude_from_region(str(row["region"]))))
            temperature = float(row["temperature"])
            humidity = float(row["humidity"])
            month = int(row["month"])
            return infer_climate_zone(altitude, temperature, humidity, month)

        if "climate_zone" not in out.columns:
            out["climate_zone"] = out.apply(_derive_climate, axis=1)
        else:
            out["climate_zone"] = out["climate_zone"].astype(str).str.strip()
            invalid = ~out["climate_zone"].isin(VALID_CLIMATE_ZONES)
            out.loc[invalid, "climate_zone"] = out.loc[invalid].apply(_derive_climate, axis=1)

    return out


def top3(classes: np.ndarray, prob_row: np.ndarray) -> tuple[str, float, str, float, str, float]:
    idx = np.argsort(prob_row)[::-1][:3]

    # Always return exactly 3 entries for easy CSV output.
    names = [str(classes[i]) for i in idx]
    probs = [float(prob_row[i] * 100.0) for i in idx]

    while len(names) < 3:
        names.append("")
        probs.append(0.0)

    return names[0], probs[0], names[1], probs[1], names[2], probs[2]


def main() -> None:
    args = parse_args()

    model_path = Path(args.model)
    input_csv = Path(args.input_csv)
    output_csv = Path(args.output_csv)

    if not model_path.exists():
        raise FileNotFoundError(f"Model artifact not found: {model_path}")
    if not input_csv.exists():
        raise FileNotFoundError(f"Input CSV not found: {input_csv}")

    output_csv.parent.mkdir(parents=True, exist_ok=True)

    artifact = joblib.load(model_path)

    feature_columns: list[str] = artifact["feature_columns"]
    nutrient_targets: list[str] = artifact["nutrient_targets"]
    crop_model = artifact["crop_model"]
    nutrient_models = artifact["nutrient_models"]

    df = pd.read_csv(input_csv)

    validate_columns(df, BASE_SENSOR_COLUMNS, "Input CSV")

    # If NPK feature columns are missing, compute them from base sensors.
    if not all(col in df.columns for col in NPK_COLUMNS):
        df = estimate_npk_components(df)

    df = ensure_location_features(df, feature_columns)

    validate_columns(df, feature_columns, "Input CSV after preprocessing")

    # Keep values in expected physical ranges.
    df["pH"] = clip_series(df["pH"], 4.5, 8.5)
    df["moisture"] = clip_series(df["moisture"], 10.0, 90.0)
    df["temperature"] = clip_series(df["temperature"], 8.0, 40.0)
    df["humidity"] = clip_series(df["humidity"], 25.0, 95.0)
    if "altitude_m" in df.columns:
        df["altitude_m"] = clip_series(df["altitude_m"], 60.0, 5200.0)

    x = df[feature_columns].copy()

    pred_crop = crop_model.predict(x)
    crop_probs = crop_model.predict_proba(x)

    nutrient_x = x.copy()
    nutrient_x["Crop"] = pred_crop

    nutrient_preds: dict[str, np.ndarray] = {}
    for target in nutrient_targets:
        pred = nutrient_models[target].predict(nutrient_x)
        nutrient_preds[target] = np.clip(pred, 0.0, None)

    class_names = crop_model.named_steps["model"].classes_

    out = df.copy()
    out["predicted_crop"] = pred_crop
    out["confidence_pct"] = np.max(crop_probs, axis=1) * 100.0
    out["N_recommend_kg_ha"] = nutrient_preds["N_apply_kg_ha"]
    out["P_recommend_kg_ha"] = nutrient_preds["P_apply_kg_ha"]
    out["K_recommend_kg_ha"] = nutrient_preds["K_apply_kg_ha"]

    top_cols = [
        "top1_crop",
        "top1_score_pct",
        "top2_crop",
        "top2_score_pct",
        "top3_crop",
        "top3_score_pct",
    ]
    top_records = [top3(class_names, prob_row) for prob_row in crop_probs]
    top_df = pd.DataFrame(top_records, columns=top_cols)
    out = pd.concat([out.reset_index(drop=True), top_df], axis=1)

    out["N_recommend_kg_ha"] = out["N_recommend_kg_ha"].round(2)
    out["P_recommend_kg_ha"] = out["P_recommend_kg_ha"].round(2)
    out["K_recommend_kg_ha"] = out["K_recommend_kg_ha"].round(2)
    out["confidence_pct"] = out["confidence_pct"].round(2)
    out["top1_score_pct"] = out["top1_score_pct"].round(2)
    out["top2_score_pct"] = out["top2_score_pct"].round(2)
    out["top3_score_pct"] = out["top3_score_pct"].round(2)

    out.to_csv(output_csv, index=False)

    first = out.iloc[0]
    print("===============================================================")
    print(" Python AI inference completed")
    print("===============================================================")
    print(f"Input CSV:     {input_csv}")
    print(f"Output CSV:    {output_csv}")
    print(
        "First recommendation: "
        f"crop={first['predicted_crop']} ({first['confidence_pct']:.2f}%), "
        f"N={first['N_recommend_kg_ha']:.2f}, "
        f"P={first['P_recommend_kg_ha']:.2f}, "
        f"K={first['K_recommend_kg_ha']:.2f} kg/ha"
    )
    print("===============================================================")


if __name__ == "__main__":
    main()
