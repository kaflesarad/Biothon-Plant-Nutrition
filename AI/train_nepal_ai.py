#!/usr/bin/env python3
"""Train Nepal crop + nutrient AI models from MATLAB-exported CSV data."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.metrics import accuracy_score, mean_absolute_error, mean_squared_error
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

FEATURE_COLUMNS = [
    "region",
    "climate_zone",
    "month",
    "altitude_m",
    "pH",
    "moisture",
    "temperature",
    "humidity",
    "N_avail",
    "P_avail",
    "K_avail",
    "NPK_composite",
]

CROP_TARGET = "Crop"
NUTRIENT_TARGETS = ["N_apply_kg_ha", "P_apply_kg_ha", "K_apply_kg_ha"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train Nepal crop + nutrient AI models")
    parser.add_argument("--input-csv", required=True, help="Training CSV exported by MATLAB")
    parser.add_argument("--model-out", required=True, help="Path to write model artifact (.joblib)")
    parser.add_argument("--metrics-out", required=True, help="Path to write metrics (.json)")
    parser.add_argument("--test-size", type=float, default=0.20, help="Holdout ratio")
    parser.add_argument("--seed", type=int, default=2026, help="Random seed")
    return parser.parse_args()


def validate_columns(df: pd.DataFrame, required: list[str], source_name: str) -> None:
    missing = [col for col in required if col not in df.columns]
    if missing:
        raise ValueError(f"{source_name} missing required columns: {missing}")


def build_crop_pipeline(seed: int) -> Pipeline:
    cat_cols = ["region", "climate_zone"]
    num_cols = [c for c in FEATURE_COLUMNS if c not in cat_cols]

    pre = ColumnTransformer(
        transformers=[
            ("cat", OneHotEncoder(handle_unknown="ignore"), cat_cols),
            ("num", "passthrough", num_cols),
        ]
    )

    clf = RandomForestClassifier(
        n_estimators=320,
        max_depth=22,
        min_samples_leaf=2,
        random_state=seed,
        n_jobs=-1,
    )

    return Pipeline(steps=[("preprocess", pre), ("model", clf)])


def build_nutrient_pipeline(seed: int) -> Pipeline:
    nutrient_features = FEATURE_COLUMNS + ["Crop"]
    cat_cols = ["region", "climate_zone", "Crop"]
    num_cols = [c for c in nutrient_features if c not in cat_cols]

    pre = ColumnTransformer(
        transformers=[
            ("cat", OneHotEncoder(handle_unknown="ignore"), cat_cols),
            ("num", "passthrough", num_cols),
        ]
    )

    reg = RandomForestRegressor(
        n_estimators=260,
        max_depth=20,
        min_samples_leaf=2,
        random_state=seed,
        n_jobs=-1,
    )

    return Pipeline(steps=[("preprocess", pre), ("model", reg)])


def main() -> None:
    args = parse_args()

    input_csv = Path(args.input_csv)
    model_out = Path(args.model_out)
    metrics_out = Path(args.metrics_out)

    if not input_csv.exists():
        raise FileNotFoundError(f"Input CSV not found: {input_csv}")

    model_out.parent.mkdir(parents=True, exist_ok=True)
    metrics_out.parent.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(input_csv)
    validate_columns(df, FEATURE_COLUMNS + [CROP_TARGET] + NUTRIENT_TARGETS, "Training CSV")

    # Keep crop names as normalized strings to avoid category mismatch across tools.
    df[CROP_TARGET] = df[CROP_TARGET].astype(str).str.strip()
    df["region"] = df["region"].astype(str).str.strip().str.title()
    df["climate_zone"] = df["climate_zone"].astype(str).str.strip()

    crop_counts = df[CROP_TARGET].value_counts()
    min_count = crop_counts.min()
    
    should_stratify = min_count >= 2
    if should_stratify:
        train_df, test_df = train_test_split(
            df,
            test_size=args.test_size,
            random_state=args.seed,
            stratify=df[CROP_TARGET],
        )
    else:
        train_df, test_df = train_test_split(
            df,
            test_size=args.test_size,
            random_state=args.seed,
        )

    crop_model = build_crop_pipeline(args.seed)
    crop_model.fit(train_df[FEATURE_COLUMNS], train_df[CROP_TARGET])

    pred_crop = crop_model.predict(test_df[FEATURE_COLUMNS])
    pred_crop = pd.Series(pred_crop, index=test_df.index, name="Crop")

    crop_accuracy = accuracy_score(test_df[CROP_TARGET], pred_crop)

    nutrient_models: dict[str, Pipeline] = {}
    nutrient_metrics: dict[str, dict[str, float]] = {}

    nutrient_train_x = train_df[FEATURE_COLUMNS].copy()
    nutrient_train_x["Crop"] = train_df[CROP_TARGET]

    nutrient_test_x_pipeline = test_df[FEATURE_COLUMNS].copy()
    nutrient_test_x_pipeline["Crop"] = pred_crop.values

    nutrient_test_x_true = test_df[FEATURE_COLUMNS].copy()
    nutrient_test_x_true["Crop"] = test_df[CROP_TARGET].values

    for target in NUTRIENT_TARGETS:
        model = build_nutrient_pipeline(args.seed)
        model.fit(nutrient_train_x, train_df[target])

        pred_pipeline = model.predict(nutrient_test_x_pipeline)
        pred_true = model.predict(nutrient_test_x_true)

        pred_pipeline = np.clip(pred_pipeline, 0.0, None)
        pred_true = np.clip(pred_true, 0.0, None)

        nutrient_metrics[target] = {
            "mae_pipeline": float(mean_absolute_error(test_df[target], pred_pipeline)),
            "rmse_pipeline": float(np.sqrt(mean_squared_error(test_df[target], pred_pipeline))),
            "mae_true_crop": float(mean_absolute_error(test_df[target], pred_true)),
            "rmse_true_crop": float(np.sqrt(mean_squared_error(test_df[target], pred_true))),
        }

        nutrient_models[target] = model

    artifact = {
        "feature_columns": FEATURE_COLUMNS,
        "crop_target": CROP_TARGET,
        "nutrient_targets": NUTRIENT_TARGETS,
        "crop_model": crop_model,
        "nutrient_models": nutrient_models,
        "class_names": sorted(df[CROP_TARGET].unique().tolist()),
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "training_rows": int(len(df)),
        "seed": int(args.seed),
    }

    joblib.dump(artifact, model_out)

    metrics = {
        "input_csv": str(input_csv),
        "created_utc": artifact["created_utc"],
        "samples_total": int(len(df)),
        "samples_train": int(len(train_df)),
        "samples_test": int(len(test_df)),
        "crop_accuracy": float(crop_accuracy),
        "nutrient_metrics": nutrient_metrics,
    }

    metrics_out.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    print("===============================================================")
    print(" Python AI training completed")
    print("===============================================================")
    print(f"Input CSV:       {input_csv}")
    print(f"Model artifact:  {model_out}")
    print(f"Metrics JSON:    {metrics_out}")
    print(f"Crop accuracy:   {crop_accuracy * 100:.2f}%")
    print(
        "Pipeline MAE (kg/ha): "
        f"N={nutrient_metrics['N_apply_kg_ha']['mae_pipeline']:.2f}, "
        f"P={nutrient_metrics['P_apply_kg_ha']['mae_pipeline']:.2f}, "
        f"K={nutrient_metrics['K_apply_kg_ha']['mae_pipeline']:.2f}"
    )
    print("===============================================================")


if __name__ == "__main__":
    main()
