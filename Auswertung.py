# -*- coding: utf-8 -*-


import pandas as pd
import matplotlib.pyplot as plt
plt.rcParams['xtick.labelsize'] = 16
plt.rcParams['ytick.labelsize'] = 16

# --- Konfiguration ---
csv_file = "timeseries_refs_heads_user_mkuehtreiber_530_20250929_QM_authors_2025-07-01_to_2025-09-30.csv"   # Pfad zu deiner CSV-Datei

# CSV einlesen
df = pd.read_csv(csv_file, parse_dates=["Date"])

# Plot erstellen
plt.figure(figsize=(12, 6))

plt.plot(df["Date"], df["CumAdded"], label="Cum. Added", linewidth=2)
plt.plot(df["Date"], df["CumDeleted"], label="Cum. Deleted", linewidth=2)
plt.plot(df["Date"], df["CumNet"], label="Cum. Net", linewidth=2, linestyle="--")

plt.title("Kumulative Codeänderungen im Zeitraum Q3 2025", fontsize=20)
plt.xlabel("Datum", fontsize=18)
plt.ylabel("Zeilen", fontsize=18)
plt.legend()
plt.grid(True, linestyle=":", alpha=0.7)

plt.tight_layout()
plt.show()
