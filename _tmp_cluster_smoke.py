import numpy as np
import pandas as pd
from sklearn.cluster import AgglomerativeClustering, KMeans
from sklearn.decomposition import PCA
from sklearn.impute import SimpleImputer
from sklearn.metrics import silhouette_score
from sklearn.preprocessing import StandardScaler

rng = np.random.default_rng(7)
rows = []
for i in range(16):
    country = f"country/{i:03d}"
    for dt in pd.date_range("2021-01-01", periods=12, freq="MS"):
        rows.append(
            {
                "country": country,
                "date": dt,
                "urbanization_ratio": 45 + i * 1.5 + rng.normal(0, 2),
                "demographic_vulnerability_index": 30 + (15 - i) * 1.2 + rng.normal(0, 1.5),
                "worldBank/NY_GDP_PCAP_CD": 5000 + i * 2500 + rng.normal(0, 1000),
                "case_fatality_rate_pct": 4.5 - i * 0.15 + rng.normal(0, 0.4),
            }
        )


def slope(vals):
    s = pd.to_numeric(vals, errors="coerce").dropna()
    if len(s) < 2:
        return np.nan
    x = np.arange(len(s), dtype=float)
    y = s.to_numpy(dtype=float)
    return float(np.polyfit(x, y, 1)[0])


df = pd.DataFrame(rows)
parts = []
for col in [
    "urbanization_ratio",
    "demographic_vulnerability_index",
    "worldBank/NY_GDP_PCAP_CD",
    "case_fatality_rate_pct",
]:
    g = df.groupby("country")[col]
    parts.append(
        pd.DataFrame(
            {
                f"{col}__median": g.median(),
                f"{col}__std": g.std(),
                f"{col}__coverage": g.apply(lambda s: s.notna().mean()),
                f"{col}__trend": g.apply(slope),
            }
        )
    )

mat = pd.concat(parts, axis=1).reset_index()
X = mat.drop(columns=["country"])
X_scaled = StandardScaler().fit_transform(SimpleImputer(strategy="median").fit_transform(X))

best_k = None
best_s = -1.0
for k in range(2, 6):
    labels = KMeans(n_clusters=k, random_state=42, n_init=20).fit_predict(X_scaled)
    s = silhouette_score(X_scaled, labels)
    if s > best_s:
        best_k = k
        best_s = s

labels_k = KMeans(n_clusters=best_k, random_state=42, n_init=30).fit_predict(X_scaled)
labels_h = AgglomerativeClustering(n_clusters=best_k, linkage="ward").fit_predict(X_scaled)
xy = PCA(n_components=2, random_state=42).fit_transform(X_scaled)

print("Smoke clustering ok")
print(f"countries={len(mat)}, best_k={best_k}, silhouette={best_s:.4f}")
print(f"kmeans_clusters={len(set(labels_k))}, agg_clusters={len(set(labels_h))}, pca_shape={xy.shape}")

