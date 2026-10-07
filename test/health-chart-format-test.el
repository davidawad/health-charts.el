;;; health-chart-format-test.el --- display precision and label columns -*- lexical-binding: t; -*-

;;; Commentary:

;; Synthetic data only.  Two things are pinned here: how many digits a
;; displayed number gets (and that status is still judged on the number
;; as it came), and that in a 90x22 text view no row label touches a
;; value.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'health-chart)
(require 'health-chart-format)
(require 'health-chart-biomarker)
(require 'health-chart-fit)
(require 'health-chart-biomarker-test)
(require 'health-chart-test-support)

;;; The number rule

(ert-deftest health-chart-format-three-significant-figures--by-default ()
  (should (equal (health-chart-format-number 82.916685236) "82.9"))
  (should (equal (health-chart-format-number 4.551020408) "4.55"))
  (should (equal (health-chart-format-number 27.92060233) "27.9"))
  (should (equal (health-chart-format-number 28.12594114) "28.1"))
  (should (equal (health-chart-format-number 3.538461538) "3.54"))
  (should (equal (health-chart-format-number 0.0123456) "0.0123"))
  (should (equal (health-chart-format-number -4.551020408) "-4.55")))

(ert-deftest health-chart-format-never-drops-integer-digits ()
  (should (equal (health-chart-format-number 132) "132"))
  (should (equal (health-chart-format-number 132.0) "132"))
  (should (equal (health-chart-format-number 1234.5678) "1235"))
  (should (equal (health-chart-format-number 12345.6) "12346")))

(ert-deftest health-chart-format-trailing-zeros-go ()
  (should (equal (health-chart-format-number 5.0) "5"))
  (should (equal (health-chart-format-number 2.5) "2.5"))
  (should (equal (health-chart-format-number 0.0) "0"))
  (should (equal (health-chart-format-number -0.0001 :decimals 2) "0.00")))

(ert-deftest health-chart-format-keeps-the-decimals-the-limits-show ()
  ;; limits 0.0 and 0.2 show one decimal: 0.02 stays 0.02, not 0.0
  (should (equal (health-chart-format-number 0.02 :limits '(0.0 0.2)) "0.02"))
  ;; limits 0.36 and 0.46 show two: 0.3 is 0.30 so the column lines up
  (should (equal (health-chart-format-number 0.3 :limits '(0.36 0.46)) "0.30"))
  ;; a limit of 3.55 keeps two decimals even where 3 figures would give one
  (should (equal (health-chart-format-number 82.916685236 :limits '(60 120)) "82.9"))
  (should (equal (health-chart-format-number 82.916685236 :limits '(60.25 120)) "82.92"))
  (should (equal (health-chart-format-number 132 :limits '(100 140)) "132"))
  (should (equal (health-chart-format-number 4.551020408 :limits '(0 5)) "4.55"))
  (should (equal (health-chart-format-number 27.92060233 :limits '(18.5 24.9)) "27.9"))
  ;; trailing zeros are cut only down to the limits' decimals
  (should (equal (health-chart-format-number 5.0 :limits '(3.9 5.6)) "5.0"))
  ;; nil and non-numbers in LIMITS are ignored
  (should (equal (health-chart-format-number 4.551 :limits '(nil :null "x")) "4.55"))
  ;; float noise in a limit does not widen the number
  (should (equal (health-chart-format-number 4.551 :limits '(0.30000000000000004)) "4.55")))

(ert-deftest health-chart-format-explicit-decimals-win ()
  (should (equal (health-chart-format-number 82.916685236 :decimals 0) "83"))
  (should (equal (health-chart-format-number 82.916685236 :decimals 3) "82.917"))
  (should (equal (health-chart-format-number 5 :decimals 1) "5.0"))
  ;; even over the limits
  (should (equal (health-chart-format-number 0.02 :decimals 1 :limits '(0.001 0.2)) "0.0")))

(ert-deftest health-chart-format-significant-figures-are-adjustable ()
  (should (equal (health-chart-format-number 82.916685236 :sig 2) "83"))
  (should (equal (health-chart-format-number 82.916685236 :sig 5) "82.917"))
  (should (equal (health-chart-format-number 4.551020408 :sig 1) "5")))

(ert-deftest health-chart-format-not-a-number-is-empty ()
  (should (equal (health-chart-format-number nil) ""))
  (should (equal (health-chart-format-number "x") ""))
  (should (equal (health-chart-format-number 1.0e+INF) "")))

(ert-deftest health-chart-format-truncate-ends-in-an-ellipsis ()
  (should (equal (health-chart-format-truncate "Body Mass Index" 28) "Body Mass Index"))
  (should (equal (health-chart-format-truncate "Estimated Glomerular Filtration Rate" 20)
                 "Estimated Glomerula…"))
  (should (<= (length (health-chart-format-truncate "Estimated Glomerular Filtration Rate" 20)) 20))
  (should (equal (health-chart-format-truncate "abc" nil) "abc"))
  (should (equal (health-chart-format-truncate "abcdef" 1) "abcdef")))

;;; The transform: display text only

(defun health-chart-format-test--format (rows &rest params)
  "ROWS (a list of plists) through the health-format transform with PARAMS, as a list."
  (append (health-chart-format--transform (vconcat rows) params) nil))

(ert-deftest health-chart-format-transform-adds-text-and-keeps-the-number ()
  (let ((row (car (health-chart-format-test--format
                   (list (list :analyte "Body Weight" :value 82.916685236 :ref_low 50 :ref_high 90))
                   :fields ["value"]))))
    (should (equal (plist-get row :value_text) "82.9"))
    (should (equal (plist-get row :value) 82.916685236))
    (should (equal (plist-get row :analyte) "Body Weight"))))

(ert-deftest health-chart-format-transform-reads-the-limits-of-each-row ()
  (let ((rows (health-chart-format-test--format
               (list (list :value 0.02 :ref_low 0.0 :ref_high 0.2)
                     (list :value 0.3 :ref_low 0.36 :ref_high 0.46)
                     (list :value 132.0 :ref_low 100 :ref_high 140))
               :fields ["value"])))
    (should (equal (mapcar (lambda (r) (plist-get r :value_text)) rows)
                   '("0.02" "0.30" "132")))))

(ert-deftest health-chart-format-transform-row-decimals-override-the-binding ()
  (let ((rows (health-chart-format-test--format
               (list (list :value 82.916685236 :decimals 3)
                     (list :value 82.916685236))
               :fields ["value"] :decimals 0)))
    (should (equal (mapcar (lambda (r) (plist-get r :value_text)) rows) '("82.917" "83")))))

(ert-deftest health-chart-format-transform-limit-values-and-bands-set-the-floor ()
  (should (equal (plist-get (car (health-chart-format-test--format
                                  (list (list :value 4.0)) :fields ["value"] :limit_values [3.125 5]))
                            :value_text)
                 "4.000")))

(ert-deftest health-chart-format-transform-cuts-labels-without-merging-them ()
  (let ((rows (health-chart-format-test--format
               (list (list :analyte "Short" :value 1)
                     (list :analyte "A very long analyte name that goes on (one)" :value 1)
                     (list :analyte "A very long analyte name that goes on (two)" :value 2))
               :fields ["value"] :label_field "analyte" :label_max 12)))
    (let ((shown (mapcar (lambda (r) (plist-get r :analyte_short)) rows)))
      (should (equal (car shown) "Short"))
      ;; both long names would cut to the same text: they keep their full names
      (should (equal (cdr shown) (mapcar (lambda (r) (plist-get r :analyte)) (cdr rows))))
      (should (= (length (delete-dups (copy-sequence shown))) 3)))
    (let ((shown (mapcar (lambda (r) (plist-get r :analyte_short))
                         (health-chart-format-test--format
                          (list (list :analyte "Estimated Glomerular Filtration Rate" :value 1))
                          :fields ["value"] :label_field "analyte" :label_max 12))))
      (should (equal shown '("Estimated G…"))))))

;;; Status stays on the number as it came

(ert-deftest health-chart-format-status-is-judged-on-the-raw-number ()
  (let* ((bindings (list :data (vector (list :time "2025-01-01" :analyte "Glucose"
                                             :value 5.6004 :ref_low 3.9 :ref_high 5.6))))
         (row (aref (plist-get (plist-get (eas-resolve "health/lab-status-grid" bindings) :data)
                               :values)
                    0)))
    ;; the text rounds to the limit, the status knows it is above it
    (should (equal (plist-get row :value_text) "5.6"))
    (should (equal (plist-get row :status) "high"))
    (should (equal (plist-get row :value) 5.6004))))

(ert-deftest health-chart-format-slot-decimals-and-row-decimals-reach-the-text ()
  (let* ((rows (vector (list :analyte "Weight" :value 82.916685236 :unit "kg" :ref_low 50 :ref_high 90)
                       (list :analyte "Ratio" :value 4.551020408 :ref_low 0 :ref_high 5 :decimals 3)))
         (plain (substring-no-properties
                 (health-chart-render "lab-results" (list :data rows) :backend 'text)))
         (two (substring-no-properties
               (health-chart-render "lab-results" (list :data rows :decimals 2) :backend 'text)))
         (figs (substring-no-properties
                (health-chart-render "lab-results" (list :data rows :sig_figs 4) :backend 'text))))
    (should (string-match-p "Weight  82\\.9 kg" plain))
    (should (string-match-p "Ratio  4\\.551" plain))
    (should (string-match-p "Weight  82\\.92 kg" two))
    (should (string-match-p "Ratio  4\\.551" two))
    (should (string-match-p "Weight  82\\.92 kg" figs))
    (should-not (string-match-p "82\\.9166" (concat plain two figs)))))

(ert-deftest health-chart-format-slots-are-validated ()
  (let ((rows (vector (list :analyte "A" :value 1.5 :ref_low 1 :ref_high 2))))
    (health-chart-test-should-code
     "out_of_range" "decimals"
     (lambda () (health-chart-validate "lab-results" (list :data rows :decimals 99))))
    (health-chart-test-should-code
     "out_of_range" "data[0].decimals"
     (lambda () (health-chart-validate
                 "lab-results"
                 (list :data (vector (list :analyte "A" :value 1.5 :decimals -1))))))))

;;; Every number a template shows is formatted

(defconst health-chart-format-test--noisy
  '(("lab-results" . (:data [(:analyte "Body Weight" :value 82.916685236 :unit "kg"
                              :ref_low 50 :ref_high 90)
                             (:analyte "CHOL/HDL RATIO" :value 4.551020408
                              :ref_low 0 :ref_high 5)]))
    ("lab-change" . (:data [(:analyte "CHOL/HDL RATIO" :before 4.551020408 :after 3.538461538
                             :ref_low 0 :ref_high 5)]))
    ("lipid-panel" . (:data [(:analyte "Body Mass Index" :value 27.92060233 :unit "mg/dL"
                              :goal 100 :direction "below" :prior 28.12594114)]))
    ("weight-bmi-trend" . (:height_m 1.78
                           :bands [(:label "normal" :low 18.5 :high 25 :status "ok")
                                   (:label "high" :low 25 :high 40 :status "high")]
                           :data [(:time "2025-01-01" :weight_kg 82.916685236)
                                  (:time "2025-02-01" :weight_kg 83.123456789)])))
  "Bindings with computed floats, by template.")

(ert-deftest health-chart-format-no-template-prints-raw-floats ()
  (dolist (entry health-chart-format-test--noisy)
    (let ((text (substring-no-properties
                 (health-chart-render (car entry) (cdr entry) :backend 'text :width 100 :height 24))))
      (should-not (string-match-p "[0-9]\\.[0-9]\\{5,\\}" text)))
    ;; the tooltips carry the formatted text too
    (let ((svg (health-chart-render (car entry) (cdr entry) :backend 'svg)))
      (should-not (string-match-p "[0-9]\\.[0-9]\\{6,\\}" (replace-regexp-in-string
                                                           "\\(?:d\\|points\\|transform\\|viewBox\\)=\"[^\"]*\""
                                                           "" svg))))))

(ert-deftest health-chart-format-weight-bmi-shows-short-numbers ()
  (let ((text (substring-no-properties
               (health-chart-render "weight-bmi-trend"
                                    (cdr (assoc "weight-bmi-trend" health-chart-format-test--noisy))
                                    :backend 'text))))
    (should (string-match-p "latest [0-9]+\\.[0-9]\\b" text))))

;;; The biomarker adapter

(ert-deftest health-chart-format-biomarker-display-options-are-slots-not-numbers ()
  (let* ((env (list :schema "biomarker/v1" :kind "latest"
                    :data (vector (list :marker "weight" :marker_name "Body Weight"
                                        :taken_at "2026-01-01" :value_canonical 82.916685236
                                        :unit_canonical "kg" :ref_low 50.0 :ref_high 82.9))))
         (plain (health-chart-from-biomarker "lab-results" env))
         (two (health-chart-from-biomarker "lab-results" env :decimals 2 :sig-figs 4 :label-max 12)))
    ;; the number is the one that came
    (should (equal (plist-get (aref (plist-get plain :data) 0) :value) 82.916685236))
    (should (equal (plist-get (aref (plist-get two :data) 0) :value) 82.916685236))
    (should-not (plist-member plain :decimals))
    (should (= (plist-get two :decimals) 2))
    (should (= (plist-get two :sig_figs) 4))
    (should (= (plist-get two :label_max) 12))
    (health-chart-validate "lab-results" two)
    ;; the text rounds, the status does not: 82.9167 is above 82.9
    (let ((row (aref (plist-get (plist-get (eas-resolve "health/lab-results" plain) :data) :values) 0)))
      (should (equal (plist-get row :value_text) "82.9"))
      (should (equal (plist-get row :status) "high")))
    (should (string-match-p "82\\.92 kg"
                            (substring-no-properties
                             (health-chart-render "lab-results" two :backend 'text))))))

(ert-deftest health-chart-format-biomarker-skips-templates-without-the-slots ()
  (let* ((env (health-chart-read-bindings
               (expand-file-name "test/fixtures/biomarker/latest-all.json" health-chart-test-root)))
         (b (health-chart-from-biomarker "lab-panel" env :decimals 2)))
    (should-not (plist-member b :decimals))))

;;; No label touches a value in a 90x22 text view

(defconst health-chart-format-test--glyphs
  "▒▓░█▏│┬─○●◆▲▼■△▽◇"
  "Characters a chart draws right of its labels: fills, bars, markers.")

(cl-defun health-chart-format-test--lines (name bindings &optional (width 90) (height 22))
  "NAME drawn from BINDINGS as text, WIDTH by HEIGHT, as a list of lines."
  (split-string (substring-no-properties
                 (health-chart-render name bindings :backend 'text :width width :height height))
                "\n"))

(defun health-chart-format-test--label-lines (lines labels)
  "The LINES that carry one of LABELS (full text or its cut start, before an ellipsis)."
  (seq-filter
   (lambda (line)
     (seq-some (lambda (label)
                 (let ((head (car (split-string label "…"))))
                   (and (>= (length head) 6) (string-search head line))))
               labels))
   lines))

(defun health-chart-format-test--touching (line)
  "The first place in LINE where text runs straight into a value or a mark, or nil.
That is a letter, a closing parenthesis or an ellipsis directly followed by a
digit or a drawn glyph, a glyph directly followed by a letter, or the first drawn glyph with no space before it."
  (let ((glyphs health-chart-format-test--glyphs))
    (or (and (string-match (format "[[:alpha:])…][0-9%s]\\|[%s][[:alpha:]]" glyphs glyphs) line)
             (match-string 0 line))
        (and (string-match (format "[%s]" glyphs) line)
             (> (match-beginning 0) 0)
             (not (eq (aref line (1- (match-beginning 0))) ?\s))
             (substring line (max 0 (1- (match-beginning 0))) (1+ (match-beginning 0)))))))

(defun health-chart-format-test--check-no-touching (name bindings labels)
  "Render NAME from BINDINGS at 90x22 and assert no row of LABELS touches a value."
  (let* ((lines (health-chart-format-test--lines name bindings))
         (rows (health-chart-format-test--label-lines lines labels)))
    (should (>= (length rows) 2))
    (dolist (line rows)
      (should (<= (string-width line) 90))
      (should-not (health-chart-format-test--touching line))
      (should-not (string-match-p "[0-9]\\.[0-9]\\{5,\\}" line)))
    lines))

(defconst health-chart-format-test--long-labels
  '("Estimated Glomerular Filtration Rate (CKD-EPI)" "Baso (Absolute)" "Body Mass Index"
    "Hematocrit" "Cholesterol/HDL Ratio, calculated from the fasting panel")
  "Long and short analyte names, synthetic.")

(defun health-chart-format-test--noisy-value (i)
  "A float with computed noise, the I-th."
  (* (+ 1.0 (/ i 7.0)) 4.551020408163265))

(ert-deftest health-chart-format-grid-label-and-cells-do-not-touch-at-90x22 ()
  (let* ((days '("2025-01-15" "2025-03-15" "2025-05-15" "2025-07-15" "2025-09-15" "2025-11-15"))
         (rows (cl-loop for day in days for d from 0
                        append (cl-loop for label in health-chart-format-test--long-labels
                                        for i from 0
                                        collect (list :time day :analyte label
                                                      :value (* (health-chart-format-test--noisy-value (+ d i))
                                                                (if (= i 1) 0.01 1))
                                                      :ref_low (if (= i 1) 0.0 3.0)
                                                      :ref_high (if (= i 1) 0.2 6.0)))))
         (lines (health-chart-format-test--check-no-touching
                 "lab-status-grid" (list :data (vconcat rows))
                 (list "Baso (Absolute)" "Hematocrit" "Body Mass Index" "Estimated Glomerular"))))
    ;; the label column is cut with an ellipsis, not run into the cells
    (should (seq-some (lambda (l) (string-search "…" l)) lines))
    ;; values are short and keep what the limits show
    (should (seq-some (lambda (l) (string-match-p "0\\.0[0-9]+" l)) lines))))

(ert-deftest health-chart-format-grid-label-max-is-configurable ()
  (let* ((rows (vector (list :time "2025-01-15" :analyte "Estimated Glomerular Filtration Rate"
                             :value 82.916685236 :ref_low 60 :ref_high 120)))
         (short (string-join (health-chart-format-test--lines
                              "lab-status-grid" (list :data rows :label_max 10)) "\n"))
         (long (string-join (health-chart-format-test--lines
                             "lab-status-grid" (list :data rows :label_max 40 :title "x")) "\n")))
    (should (string-match-p "Estimated…" short))
    (should-not (string-match-p "Estimated Glomerular Filtration Rate" short))
    (should (string-match-p "Estimated Glomerular Filtr" long))))

(ert-deftest health-chart-format-lab-results-label-and-bar-do-not-touch-at-90x22 ()
  (health-chart-format-test--check-no-touching
   "lab-results"
   (list :data (vconcat
                (cl-loop for label in health-chart-format-test--long-labels
                         for i from 0
                         collect (list :analyte label :value (health-chart-format-test--noisy-value i)
                                       :unit "mL/min" :ref_low 3.0 :ref_high 6.0))))
   (list "Estimated Glomerular" "Baso (Absolute)" "Body Mass Index" "Hematocrit" "Cholesterol/HDL")))

(ert-deftest health-chart-format-lab-change-label-and-bar-do-not-touch-at-90x22 ()
  (health-chart-format-test--check-no-touching
   "lab-change"
   (list :data (vconcat
                (cl-loop for label in health-chart-format-test--long-labels
                         for i from 0
                         collect (list :analyte label :unit "mL/min"
                                       :before (health-chart-format-test--noisy-value i)
                                       :after (health-chart-format-test--noisy-value (+ i 3))
                                       :ref_low 3.0 :ref_high 6.0))))
   (list "Estimated Glomerular" "Baso (Absolute)" "Body Mass Index" "Hematocrit" "Cholesterol/HDL")))

(ert-deftest health-chart-format-lipid-panel-label-and-bar-do-not-touch-at-90x22 ()
  (health-chart-format-test--check-no-touching
   "lipid-panel"
   (list :data (vconcat
                (cl-loop for label in health-chart-format-test--long-labels
                         for i from 0
                         collect (list :analyte label :unit "mg/dL"
                                       :value (* 30 (health-chart-format-test--noisy-value i))
                                       :goal 100 :direction "below"
                                       :prior (* 31 (health-chart-format-test--noisy-value i))))))
   (list "Estimated Glomerular" "Baso (Absolute)" "Body Mass Index" "Hematocrit" "Cholesterol/HDL")))

;;; The grid at real terminal sizes

(defconst health-chart-format-test--grid-names
  '("Baso (Absolute)" "Platelets" "Thyroid Stimulating Hormone" "Body Mass Index"
    "Estimated Glomerular Filtration Rate (CKD-EPI)" "Hematocrit" "Glucose" "Glycated Hemoglobin"
    "LDL cholesterol" "HDL cholesterol" "Triglycerides" "Sodium" "Potassium" "Chloride"
    "Calcium" "Albumin" "Bilirubin" "ALT" "AST" "Creatinine" "BUN" "Ferritin" "Vitamin D"
    "Cobalamin" "Free Thyroxine" "Magnesium" "Zinc" "RBC" "WBC" "MCV" "MCH" "RDW" "Neutrophils"
    "Lymphocytes" "Monocytes")
  "Thirty-five synthetic analyte names, long and short.")

(defun health-chart-format-test--grid-data (dates)
  "Synthetic grid rows: DATES draw dates of every name in `health-chart-format-test--grid-names'."
  (vconcat
   (cl-loop for d below dates
            append (cl-loop for name in health-chart-format-test--grid-names
                            for i from 0
                            for scale = (pcase (mod i 4) (0 0.02) (1 1.0) (2 27.7) (_ 90.8))
                            collect (list :time (format "2025-%02d-15" (1+ d)) :analyte name
                                          :value (* scale (+ 0.8 (/ (mod (+ d i) 9) 10.0)))
                                          :ref_low (* scale 0.7) :ref_high (* scale 1.5))))))

(defun health-chart-format-test--grid-lines (dates cols rows &rest bindings)
  "The lab-status-grid of DATES draws, COLS by ROWS text cells, as lines."
  (split-string (substring-no-properties
                 (health-chart-render "lab-status-grid"
                                      (append (list :title "Results" :data (health-chart-format-test--grid-data dates)) bindings)
                                      :backend 'text :width cols :height rows))
                "\n"))

(defun health-chart-format-test--first-drawn (line)
  "The index of the first drawn glyph in LINE (a fill, marker, tick or swatch), or nil."
  (string-match (format "[%s]" health-chart-format-test--glyphs) line))

(defun health-chart-format-test--cells (line)
  "How many status glyphs of cells LINE holds in its plot (its legend swatch excluded)."
  (let ((n 0) (start 0))
    (while (string-match "[\u25c6\u25cf\u25b2\u25bc\u25c7?] [0-9-]" line start)
      (setq n (1+ n) start (match-end 0)))
    n))

(ert-deftest health-chart-format-grid-label-never-touches-the-first-value ()
  "At common terminal sizes, with 7 and 12 draws of 35 markers, a space
separates every label from the first value, and no cell loses its text."
  (dolist (size '((90 22) (105 26) (140 40)))
    (dolist (dates '(7 12))
      (let* ((lines (health-chart-format-test--grid-lines dates (car size) (cadr size)))
             (cells nil))
        (dolist (line lines)
          (should (<= (string-width line) (car size)))
          (when-let* ((i (health-chart-format-test--first-drawn line)))
            ;; the first drawn character has a space (or the margin) before it
            (should (or (= i 0) (eq (aref line (1- i)) ?\s))))
          (should-not (health-chart-format-test--touching line))
          (let ((n (health-chart-format-test--cells line)))
            (when (> n 0) (push n cells))))
        (let ((case-name (format "%dx%d with %d draws" (car size) (cadr size) dates)))
          ;; every drawn row shows the same number of whole cells, at least 3
          (should (equal (cons case-name (seq-uniq cells))
                         (cons case-name (list (car cells)))))
          (should (>= (car cells) (min dates 3)))
          (should (<= (car cells) dates)))))))

(ert-deftest health-chart-format-grid-shows-the-latest-draws-that-fit ()
  (let* ((narrow (health-chart-format-test--grid-lines 12 90 22))
         (wide (health-chart-format-test--grid-lines 7 140 40))
         (cells (lambda (lines) (apply #'max (mapcar #'health-chart-format-test--cells lines)))))
    (should (< (funcall cells narrow) 12))
    (should (= (funcall cells wide) 7))
    ;; the subtitle says what was left out, and it is the oldest draws that go
    (should (seq-some (lambda (l) (string-match-p (format "latest %d of 12 draws" (funcall cells narrow)) l))
                      narrow))
    (should-not (seq-some (lambda (l) (string-match-p "latest .* of 7 draws" l)) wide))
    (should (seq-some (lambda (l) (string-match-p "2025-12-15" l)) narrow))
    (should-not (seq-some (lambda (l) (string-match-p "2025-01-15" l)) narrow))))

(ert-deftest health-chart-format-grid-max-draws-is-configurable ()
  (let ((three (health-chart-format-test--grid-lines 7 140 40 :max_draws 3))
        (all (health-chart-format-test--grid-lines 12 90 22 :max_draws 0)))
    (should (= (apply #'max (mapcar #'health-chart-format-test--cells three)) 3))
    (should (seq-some (lambda (l) (string-match-p "latest 3 of 7 draws" l)) three))
    ;; 0 asks for every draw, squeezed or not
    (should-not (seq-some (lambda (l) (string-match-p "latest .* of 12 draws" l)) all))
    ;; the biomarker adapter passes it on
    (let ((b (health-chart-from-biomarker
              "lab-status-grid" (health-chart-biomarker-test--fixture "latest-all") :max-draws 2)))
      (should (= (plist-get b :max_draws) 2)))))

(ert-deftest health-chart-format-latest-draws-transform ()
  (let* ((rows (vector (list :time "2025-01-15" :v 1) (list :time "2025-03-15T08:00" :v 2)
                       (list :time "2025-03-15T09:00" :v 3) (list :time "2025-05-15" :v 4)))
         (keep (lambda (max) (mapcar (lambda (r) (plist-get r :v))
                                     (append (health-chart-fit--latest rows (list :max max)) nil)))))
    (should (equal (funcall keep 2) '(2 3 4)))
    (should (equal (funcall keep 1) '(4)))
    (should (equal (funcall keep 0) '(1 2 3 4)))
    (should (equal (funcall keep nil) '(1 2 3 4)))
    (should (equal (funcall keep 9) '(1 2 3 4)))))

(provide 'health-chart-format-test)
;;; health-chart-format-test.el ends here
