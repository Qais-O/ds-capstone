import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path

country_cluster_assignments = pd.DataFrame(
    {
        "country": [f"country/{i:03d}" for i in range(8)],
        "cluster_kmeans": [0, 0, 1, 1, 1, 2, 2, 2],
        "cluster_label": [
            "Cluster_1",
            "Cluster_1",
            "Cluster_2",
            "Cluster_2",
            "Cluster_2",
            "Cluster_3",
            "Cluster_3",
            "Cluster_3",
        ],
        "pca_1": np.random.randn(8),
        "pca_2": np.random.randn(8),
    }
)

cluster_size_summary = (
    country_cluster_assignments.groupby(["cluster_kmeans", "cluster_label"], as_index=False)
    .agg(countries=("country", "count"))
)

profile_numeric = pd.DataFrame(
    {
        "cluster_kmeans": [0, 1, 2],
        "feat_a__median": [1.0, 2.0, 0.5],
        "feat_b__median": [3.0, 1.0, 2.5],
    }
)

sns.set_style("whitegrid")
out_dir = Path("/tmp/stage2_cluster_viz_test")
out_dir.mkdir(parents=True, exist_ok=True)

fig1 = plt.figure(figsize=(6, 4))
ax1 = sns.scatterplot(
    data=country_cluster_assignments,
    x="pca_1",
    y="pca_2",
    hue="cluster_label",
    style="cluster_label",
)
for row in country_cluster_assignments.itertuples(index=False):
    ax1.text(row.pca_1 + 0.01, row.pca_2 + 0.01, row.country, fontsize=7)
fig1.tight_layout()
fig1.savefig(out_dir / "cluster_pca_scatter.png", dpi=120)
plt.close(fig1)

fig2 = plt.figure(figsize=(5, 3))
sns.barplot(data=cluster_size_summary, x="cluster_label", y="countries")
fig2.tight_layout()
fig2.savefig(out_dir / "cluster_size_bar.png", dpi=120)
plt.close(fig2)

profile_for_plot = profile_numeric.set_index("cluster_kmeans")
z = (profile_for_plot - profile_for_plot.mean()) / profile_for_plot.std(ddof=0)
z = z.replace([np.inf, -np.inf], np.nan).fillna(0.0)
fig3 = plt.figure(figsize=(6, 3))
sns.heatmap(z, cmap="coolwarm", center=0)
fig3.tight_layout()
fig3.savefig(out_dir / "cluster_profile_heatmap.png", dpi=120)
plt.close(fig3)

print("viz smoke test ok:", sorted([p.name for p in out_dir.glob("*.png")]))

