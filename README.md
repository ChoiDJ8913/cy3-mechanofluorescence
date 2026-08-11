# cy3-mechanofluorescence

MATLAB analysis code for **"Cy3 is a Single-Molecule Mechanosensitive Fluorophore
with Reversible Emission Modulation by Piconewton Forces"** (Choi, Cho, Lee & Lee, 2026).

Data: https://doi.org/10.5281/zenodo.21885650
Licence: MIT

Requires MATLAB R2021b or later with the Image Processing, Curve Fitting and
Statistics and Machine Learning Toolboxes. No compilation needed.

---

## Pipeline

```
EMCCD movie (.record.mat)
  └─ MTFindPeaks / cy3_MTFindPeaks_MTView_batch / MTView   ROI detection within the
                                                           bead region (S1.6)
       └─ FluorSegmenterLite / MeansCollectorLite          per-frame intensity,
                                                           annulus background (S1.7)
            └─ SegMeansBatchAggregator                     *_segmeans_all.csv
                 └─ SegMeansMinimal                        origin_minimal.xlsx  ← figure input
                      └─ MTFluorQC_GUI                     ROI QC, writes the audit CSVs
```

Force calibration (`make_psd_T2F_F2T`, `make_CAL_T2F_F2T_PSD`, S1.4) converts magnet
height to force and feeds the segmentation step.

## Which file made which figure

| Figure / table | Files |
|---|---|
| Fig. 1B–D, table S4 | `SegMeansBatchAggregator`, `SegMeansMinimal`, `ana_MT_avr` |
| Fig. 2, fig. S4 | `onefile_lowhigh_compare`, `peak_matched_low_high_scatter`, `MT_export_long_table_plateau_LOW_HIGH`, `export_fig2_dimming_split_from_longtable`, `export_origin_low_high_from_trace`, `export_origin_scatter_roi_means_from_trace` |
| Fig. 3B | `cy3_panel_B_fig3`, `Cy3`, `icy3_anchor_check`, `standardize_atom` |
| Fig. 3C | **not produced by code in this repository** — see below |
| Fig. 3D | `cy3_panel_C_fig3_v7`, `run_torsion_dx_pipeline`, `cy3_torsion_align_scan_v2`, `cy3_Dx_absolute` |
| Fig. S5 | `merge_and_analyze_spectra_v3` |
| Force calibration (S1.4) | `make_psd_T2F_F2T`, `make_CAL_T2F_F2T_PSD` |
| ROI QC and audit trail (S1.6) | `MTFluorQC_GUI` |
| helper | `read_table_flex` |
| fig. S1 panels | `MTFindPeaks_v2`, `MTView_v2`, `MTPanelA`, `MTLabelEditor`, `mt_label`, `mt_labelpos` |
| bundled input | `5ns4_xyz.xlsx` (Cy3 coordinates from PDB 5NS4) |

## How Delta-x_eff was obtained

The published value **Delta-x_eff = 1.09 +/- 0.51 Angstrom (R^2 = 0.9762)** comes from a
semi-log linear regression of I(F)/I(F0) against force for F > F0, performed in
OriginPro 2019, not from code in this repository. The value is entered as a constant in
`cy3_panel_C_fig3_v7.m`, which draws it as a reference line over the torsion scan (Fig. 3D).
The Origin worksheet is included in the data deposit.

`fit_FDeltaX_bell.m`, `fit_single_exp_IF.m` and `fit_cy3_intensity_vs_force.m` implement
alternative closed-form fits that were explored during analysis. **They were not used to
produce the published value** and are included only for completeness.
`fit_FDeltaX_bell.m` fits the full steady-state form
`I_norm(F) = 1 / (1 + alpha * (exp(F * dx / kBT) - 1))`.

## ROI QC audit trail

`MTFluorQC_GUI` writes, per parent folder:

- `per_file_selected_rois.csv` — ROI, selection timestamp, parameter hash, frames and
  forces used
- `per_roi_trace_table.csv` — LOW/HIGH frames of the selected ROIs
- `per_file_frame_table.csv` — force, magnet position, exclusion mask, segment index

Segmentation parameters: `F_thr = 0.01`, `Z_thr = 1e-4`, `pad = 5`,
`minPlateauLen = 10` (hashed into `qc_param_hash`).

## The `_v2` figure scripts

`MTFindPeaks.m` and `MTView.m` are the originals that produced the deposited
intensity data. `MTFindPeaks_v2.m` and `MTView_v2.m` are their rendering-only
successors: the peak detection and the signal/background extraction are
byte-identical, but figures are exported at 600 dpi through `exportgraphics`
instead of `saveas`, which cannot set a resolution. Use the originals to
understand how the numbers were produced and the `_v2` pair to regenerate the
panels of fig. S1.

`MTPanelA.m` builds the full-field-of-view panel (fig. S1A), averaging chosen
frame ranges and marking the zoom region. `MTLabelEditor.m` lets the peak
numbers be positioned by hand before export. `mt_label.m` and `mt_labelpos.m`
are shared helpers required by all of the above.

## Bundled input

`5ns4_xyz.xlsx` (33 atoms: label, atom name, x, y, z) holds the Cy3 coordinates extracted
from PDB entry 5NS4. `cy3_panel_B_fig3.m` and `cy3_panel_C_fig3_v7.m` read it from the
working directory. The nine backbone-chain atoms used for the torsion scan are
CAZ, NAU, CAG, CAH, CAI, CAJ, CAK, NAV, CBA.

## Note on paths

These scripts were run interactively with folder pickers; a few contain absolute
paths from the original acquisition machine. Point them at the corresponding folder
of the data deposit.

## Citation

> Choi, D., Cho, H., Lee, K. S., & Lee, G. (2026). cy3-mechanofluorescence (v1.0.0).
> Zenodo. https://doi.org/10.5281/zenodo.YYYYYYY
