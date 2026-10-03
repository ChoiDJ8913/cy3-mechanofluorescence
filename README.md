# cy3-mechanofluorescence

MATLAB analysis code for **"Piconewton Forces Reversibly Modulate Emission from a Single
Cy3 Fluorophore"** (Choi, Cho, Lee & Lee, 2026).

Data: https://doi.org/10.5281/zenodo.21886520
Code (all versions): https://doi.org/10.5281/zenodo.21886261
Licence: MIT

Requires MATLAB R2022a or later with the Image Processing, Curve Fitting and
Statistics and Machine Learning Toolboxes. No compilation needed. Add the repository root
to the MATLAB path; the scripts in `exploratory/` are not needed to reproduce the article.

Figure, table and section names below follow the eLife version of the article.

---

## Pipelines

### Force-dependent intensity (Figure 1, Figure 1—figure supplements 2 and 3, Table 1, Figure 3C input)

```
EMCCD movie (<rec>.record.mat)
  └─ MTFindPeaks / cy3_MTFindPeaks_MTView_batch / MTView   ROI detection in the bead halo,
                                                           per-frame signal and annulus background
       └─ FluorSegmenterLite_v2                            constant-force intervals, frames during
                                                           magnet translation removed;
                                                           writes <rec>_segmeans_all.csv
            └─ SegMeansBatchAggregator / SegMeansMinimal   pooled tables (figure_source_data/)
```

`<rec>_segmeans_all.csv` (one row per ROI per interval: `f_mean`, `mean_sgnl`, `mean_bgnd`,
`mean_raw` and their SDs) is deposited for every record, so the analysis can also be started
from the data deposit. `SegMeansBatchAggregator` (`NormMode = "fl"`) normalizes each ROI to the
mean of its first and last interval; every deposited record is a single F0 → F → F0 cycle, so
these are the two flanking F0 reference intervals.

### Configuration comparison (Figure 2, Figure 2—figure supplement 1)

```
MTFluorQC_GUI                              ROI picking; LOW/HIGH intervals from the force and
                                           magnet records (F_thr = 0.01, Z_thr = 1e-4, pad = 5,
                                           minPlateauLen = 10); writes the QC audit CSVs
  └─ MT_export_long_table_plateau_LOW_HIGH per-frame long table with per-ROI low-force baseline
       └─ export_fig2_dimming_split_from_longtable   per-ROI means and ratio (roi_summary_split.csv)
```

`export_origin_low_high_from_trace` and `export_origin_scatter_roi_means_from_trace` export the
same quantities in Origin-ready form.

### Emission spectra (Figure 2—figure supplement 2)

```
batchHybridBgSubAnalysis                   drift estimate and hybrid background (<rec>_hybridBG_drift.mat)
  └─ select_ROIs_batch_with_drift_gui      ROI selection; stable low/high-force frames
       (detect_stable_force_frames,        (frames during magnet translation excluded)
        estimate_background_scattered_nansafe, visualize_background_correction_whole,
        visualize_bg_subtraction)
       └─ roi_viewer_gui                   low/high spectral profiles → *_signalData.mat
            (apply_background_subtraction)
            └─ merge_and_analyze_spectra_v3   per-molecule baseline correction and peak
                 (pixel_lambda_calib_gui)     normalization, outlier filter, averaging,
                                              pixel-to-wavelength calibration
```

### Force calibration

Force is computed from the magnet position with the magnetic-tweezers calibration for M-280
beads and the 9.8 mm cube magnets, `CAL_M280_9.8mm_cube_Magnet_20250908.mat` (data deposit;
function handles `T2F` and `F2T`, valid 0–24 mm, −0.2 to 29 pN). `make_CAL_T2F_F2T_PSD.m` builds
this file from the PSD-method fit; its coefficients are written into the script.

### Structure (Figure 3B, 3D)

`cy3_panel_B_fig3` draws the Cy3 structure from `5ns4_xyz.xlsx`. `cy3_panel_D_fig3_v8` rotates
the bridge-bond torsions φ1–φ4 and plots the change in the CAZ–CBA distance; it also prints the
values at ±90° quoted in the text (φ1: 1.52/1.54 Å; φ4: 1.51/1.57 Å). `run_torsion_dx_pipeline`
runs the same scan with heat maps and validation plots.

## Which file made which figure

| Figure / table | Files |
|---|---|
| Figure 1B–D, Table 1, Figure 1—figure supplements 2 and 3 | `MTFindPeaks`, `MTView`, `cy3_MTFindPeaks_MTView_batch`, `FluorSegmenterLite_v2`, `SegMeansBatchAggregator`, `SegMeansMinimal`, `ana_MT_avr` |
| Figure 1—figure supplement 1 | `MTFindPeaks_v2`, `MTView_v2`, `MTPanelA`, `MTLabelEditor`, `mt_label`, `mt_labelpos` |
| Figure 2, Figure 2—figure supplement 1 | `MTFluorQC_GUI`, `MT_export_long_table_plateau_LOW_HIGH`, `export_fig2_dimming_split_from_longtable`, `export_origin_low_high_from_trace`, `export_origin_scatter_roi_means_from_trace` |
| Figure 2—figure supplement 2 | `batchHybridBgSubAnalysis`, `select_ROIs_batch_with_drift_gui`, `detect_stable_force_frames`, `estimate_background_scattered_nansafe`, `visualize_background_correction_whole`, `visualize_bg_subtraction`, `roi_viewer_gui`, `apply_background_subtraction`, `merge_and_analyze_spectra_v3`, `pixel_lambda_calib_gui` |
| Figure 3B | `cy3_panel_B_fig3` |
| Figure 3C | **not produced by code in this repository** — see below |
| Figure 3D | `cy3_panel_D_fig3_v8`, `run_torsion_dx_pipeline` |
| Force calibration | `make_CAL_T2F_F2T_PSD` |
| helper | `read_table_flex` |
| bundled input | `5ns4_xyz.xlsx` (Cy3 coordinates from PDB 5NS4) |

## How Δx_eff was obtained

The published value **Δx_eff = 1.09 ± 0.05 Å (slope ± SE; R² = 0.978)** comes from a
weighted linear regression of ln[I(F)/I(F0)] against force over 5.1–27.3 pN, using the
N-weighted pooled mean of the Up and Down series with weights 1/σ² (σ = pooled SD / mean),
performed in OriginPro 2019 (Linear Fit): slope = −0.02655 ± 0.00125 pN⁻¹, converted with
k_BT = 41.16 pN·Å (25 °C). The fit input is `Table1_Figure1D_Figure3C_source.csv` in the data
deposit, and a weighted least-squares fit on those rows reproduces the slope, SE and R² above.
`cy3_panel_D_fig3_v8.m` enters the Origin slope and its SE as constants and draws Δx_eff and its
SE as the reference line and shaded band in Figure 3D.

## Figure 2 groups

`export_fig2_dimming_split_from_longtable` labels each ROI `dimming` (ratio < 0.8) or `stable`.
In the deposited data every record contains exactly one `dimming` ROI, the spot under the bead,
and its neighbours are `stable`; the two classes are separated by a gap (≤ 0.73 vs ≥ 0.81), so
the labels coincide with the position-based groups (bead-tethered vs no-bead) used in the
article. Three ROIs were excluded from Figure 2 by hand; they are listed in
`Figure2_excluded_rois.csv` in the data deposit.

## Spectra outlier filter

`merge_and_analyze_spectra_v3` excludes molecules whose low-force peak (3-point moving mean)
exceeds the median + 6 × MAD of all molecules in the folder (`QC_MADmult = 6`). The N reported
in the article (18 bead-on, 31 bead-off) is after this filter.

## Known issues (kept so that the code reproduces the deposited numbers)

- `MTView`: the signal disk (r ≤ 5 px) and the background annulus (5 ≤ r ≤ exR) share the
  12 pixels at r = 5 px.
- `FluorSegmenterLite_v2`: each edit of the Lag field shifts the intervals again from the
  already-shifted position; set the lag once.
- `MTFluorQC_GUI`: ROI picks are not cleared when a new parent folder is selected; restart the
  GUI between datasets.
- `ana_MT_avr`: frame windows are hard-coded per protocol block; uncomment the block that
  matches the dataset.

## The `_v2` figure scripts

`MTFindPeaks.m` and `MTView.m` are the originals that produced the deposited
intensity data. `MTFindPeaks_v2.m` and `MTView_v2.m` are their rendering-only
successors: the peak detection and the signal/background extraction are
identical, but figures are exported at 600 dpi through `exportgraphics`.

## exploratory/

Scripts written while developing the analysis, kept for transparency but **not used for any
published figure or value**: earlier segmentation and collection tools (`FluorSegmenterLite`,
`MeansCollectorLite`), alternative force–intensity fits (`fit_FDeltaX_bell`, `fit_single_exp_IF`,
`fit_cy3_intensity_vs_force`), alternative structural scans (`Cy3`, `icy3_anchor_check`,
`cy3_Dx_absolute`, `cy3_torsion_align_scan_v2`, `standardize_atom`), earlier Figure 2 comparisons
with fixed frame windows (`onefile_lowhigh_compare`, `peak_matched_low_high_scatter`), an
extension-based calibration (`make_psd_T2F_F2T`), and the superseded Figure 3D script
(`cy3_panel_C_fig3_v7`, which hard-coded an incorrect ±0.51 Å band).

## Note on paths

These scripts were run interactively with folder pickers; a few default to folders on the
original acquisition machine. Point them at the corresponding folder of the data deposit.

## Changes in v1.0.1

- Added `FluorSegmenterLite_v2.m`, which writes the deposited `*_segmeans_all.csv` files.
- Added the emission-spectrum pipeline (`batchHybridBgSubAnalysis` … `pixel_lambda_calib_gui`).
- `cy3_panel_D_fig3_v8.m` replaces `cy3_panel_C_fig3_v7.m` for Figure 3D (band = ± SE,
  0.05 Å) and prints the ±90° values.
- `detect_stable_force_frames`: calibration file is now an option (`'CalFile'`) instead of an
  absolute path. `SegMeansBatchAggregator` can be called without arguments.
- Scripts not used for the article moved to `exploratory/`.
- README and citation updated to the eLife numbering and the corrected Δx_eff uncertainty.

## Citation

> Choi, D., Cho, H., Lee, K. S., & Lee, G. (2026). cy3-mechanofluorescence (v1.0.1).
> Zenodo. https://doi.org/10.5281/zenodo.21886261
