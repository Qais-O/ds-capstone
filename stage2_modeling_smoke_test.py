"""Tiny smoke test for Stage 2 modeling dependencies and workflow shape."""

import numpy as np
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.impute import SimpleImputer
from sklearn.linear_model import Ridge
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler


def make_synthetic_panel(n_countries: int = 6, n_periods: int = 12) -> pd.DataFrame:
    rng = np.random.default_rng(42)
    rows = []
    dates = pd.date_range("2021-01-01", periods=n_periods, freq="MS")
    for c in range(n_countries):
        country = f"country/{c:03d}"
        base = rng.uniform(1.0, 8.0)
        for dt in dates:
            vax = np.clip(rng.normal(40 + c * 2, 12), 0, 100)
            urban = np.clip(rng.normal(60 + c, 7), 20, 95)
            gdp = rng.uniform(3000, 60000)
            # Synthetic target with mild signal + noise.
            cfr = base - 0.015 * vax + 0.00002 * gdp - 0.01 * urban + rng.normal(0, 0.5)
            rows.append(
                {
                    "date": dt,
                    "country": country,
                    "case_fatality_rate_pct": cfr,
                    "vax_primary_pct": vax,
                    "urbanization_ratio": urban,
                    "worldBank/NY_GDP_PCAP_CD": gdp,
                }
            )
    return pd.DataFrame(rows)


def main() -> None:
    df = make_synthetic_panel()
    df["year"] = df["date"].dt.year

    train = df[df["date"] < "2021-10-01"].copy()
    test = df[df["date"] >= "2021-10-01"].copy()

    features = ["vax_primary_pct", "urbanization_ratio", "worldBank/NY_GDP_PCAP_CD"]
    preprocessor = ColumnTransformer(
        transformers=[
            (
                "num",
                Pipeline(
                    steps=[
                        ("imputer", SimpleImputer(strategy="median")),
                        ("scaler", StandardScaler()),
                    ]
                ),
                features,
            ),
            (
                "country",
                Pipeline(
                    steps=[
                        ("imputer", SimpleImputer(strategy="most_frequent")),
                        ("onehot", OneHotEncoder(handle_unknown="ignore")),
                    ]
                ),
                ["country"],
            ),
            ("year", "passthrough", ["year"]),
        ]
    )

    model = Pipeline(steps=[("prep", preprocessor), ("model", Ridge(alpha=1.0))])
    model.fit(train[features + ["country", "year"]], train["case_fatality_rate_pct"])

    preds = model.predict(test[features + ["country", "year"]])
    assert len(preds) == len(test), "Prediction length mismatch"
    print("Smoke test passed.")
    print(f"Rows train={len(train)}, test={len(test)}, pred_mean={preds.mean():.4f}")


if __name__ == "__main__":
    main()

