;;; health-chart-status-test.el --- the color rule, the theme and its reach -*- lexical-binding: t; -*-

;;; Commentary:

;; The one rule (red out of range, yellow near a limit, green in range,
;; grey without a range), the configuration that sets its colors and
;; margin, and a scan of every template for the invariants that make
;; "one color meaning everywhere" true.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'health-chart)
(require 'health-chart-test-support)
(require 'health-chart-biomarker-test)

(defmacro health-chart-test-with-theme (theme template-theme &rest body)
  "Run BODY with `health-chart-theme' THEME and `health-chart-template-theme' TEMPLATE-THEME."
  (declare (indent 2))
  `(let ((health-chart-theme ,theme) (health-chart-template-theme ,template-theme))
     ,@body))

;;; The rule: two-sided range 0..100, margin 0.2 = 20 units

(ert-deftest health-chart-status-two-sided-boundaries ()
  (health-chart-test-with-theme nil nil
    (pcase-dolist (`(,value . ,want)
                   '((-0.01 . low) (0 . near) (0.5 . near) (19.99 . near) (20 . ok)
                     (50 . ok) (80 . ok) (80.01 . near) (99 . near) (100 . near)
                     (100.01 . high) (250 . high)))
      (should (equal (cons value (health-chart-status value 0 100)) (cons value want))))))

(ert-deftest health-chart-status-exactly-at-a-limit-is-in-range-not-out ()
  (should (eq (health-chart-status 3.9 3.9 5.6) 'near))
  (should (eq (health-chart-status 5.6 3.9 5.6) 'near))
  (should (eq (health-chart-status 3.89 3.9 5.6) 'low))
  (should (eq (health-chart-status 5.61 3.9 5.6) 'high)))

(ert-deftest health-chart-status-the-inner-edge-of-the-margin-is-green ()
  (should (equal (health-chart-status-limits 0 100) '(20.0 . 80.0)))
  (should (eq (health-chart-status 20 0 100) 'ok))
  (should (eq (health-chart-status 80 0 100) 'ok)))

(ert-deftest health-chart-status-one-sided-ranges-use-the-bound ()
  ;; upper limit only: yellow from 90 - 0.2 * 90 = 72 up to 90
  (should (equal (health-chart-status-limits nil 90) '(nil . 72.0)))
  (pcase-dolist (`(,value . ,want) '((-500 . ok) (0 . ok) (72 . ok) (72.5 . near)
                                     (90 . near) (90.5 . high)))
    (should (equal (cons value (health-chart-status value nil 90)) (cons value want))))
  ;; lower limit only: yellow from 40 up to 40 + 0.2 * 40 = 48
  (should (equal (health-chart-status-limits 40 nil) '(48.0 . nil)))
  (pcase-dolist (`(,value . ,want) '((39.9 . low) (40 . near) (47.9 . near) (48 . ok)
                                     (500 . ok)))
    (should (equal (cons value (health-chart-status value 40 nil)) (cons value want)))))

(ert-deftest health-chart-status-negative-bounds-use-the-magnitude ()
  (should (equal (health-chart-status-limits nil -10) '(nil . -12.0)))
  (should (eq (health-chart-status -11 nil -10) 'near))
  (should (eq (health-chart-status -13 nil -10) 'ok)))

(ert-deftest health-chart-status-no-range-is-unknown-never-green ()
  (should (eq (health-chart-status 5 nil nil) 'unknown))
  (should (eq (health-chart-status 5 :null :null) 'unknown))
  (should (eq (health-chart-status 5 "x" nil) 'unknown))
  (should (eq (health-chart-status nil 0 100) 'unknown))
  (should (eq (health-chart-status "5" 0 100) 'unknown))
  (should (eq (health-chart-status :null 0 100) 'unknown))
  (should (eq (health-chart-status 0.0e+NaN 0 100) 'unknown)))

(ert-deftest health-chart-status-margin-argument ()
  (should (eq (health-chart-status 9 0 100 0.1) 'near))
  (should (eq (health-chart-status 11 0 100 0.1) 'ok))
  ;; 0 turns the yellow zone off: a limit itself is green
  (should (eq (health-chart-status 0 0 100 0) 'ok))
  (should (eq (health-chart-status 100 0 100 0) 'ok))
  (should (eq (health-chart-status -1 0 100 0) 'low))
  ;; half the width from both sides leaves only the middle green
  (should (eq (health-chart-status 50 0 100 0.5) 'ok))
  (should (eq (health-chart-status 49 0 100 0.5) 'near))
  ;; an invalid margin falls back to the default
  (should (eq (health-chart-status 19 0 100 "x") 'near))
  (should (eq (health-chart-status 21 0 100 "x") 'ok)))

(ert-deftest health-chart-status-explicit-warn-edges-replace-the-margin ()
  (should (eq (health-chart-status 6 0 100 nil 5 nil) 'ok))
  (should (eq (health-chart-status 4 0 100 nil 5 nil) 'near))
  (should (eq (health-chart-status 90 0 100 nil nil 95) 'ok))
  (should (eq (health-chart-status 96 0 100 nil nil 95) 'near))
  ;; the other side keeps the computed edge
  (should (eq (health-chart-status 79 0 100 nil 5 nil) 'ok))
  (should (eq (health-chart-status 81 0 100 nil 5 nil) 'near))
  ;; a warn edge on a side without a limit is ignored
  (should (eq (health-chart-status 5 nil 100 nil 50 nil) 'ok)))

(ert-deftest health-chart-status-degenerate-range ()
  (should (eq (health-chart-status 5 5 5) 'ok))
  (should (eq (health-chart-status 4.9 5 5) 'low))
  (should (eq (health-chart-status 5.1 5 5) 'high)))

;;; Spans, text and bands

(ert-deftest health-chart-status-range-text ()
  (should (equal (health-chart-status-range-text 3.9 5.6) "3.9 to 5.6"))
  (should (equal (health-chart-status-range-text 4.0 6) "4 to 6"))
  (should (equal (health-chart-status-range-text nil 90) "≤ 90"))
  (should (equal (health-chart-status-range-text 40 nil) "≥ 40"))
  (should (equal (health-chart-status-range-text nil nil) "no range")))

(ert-deftest health-chart-status-bands-from-a-range ()
  (let ((bands (append (health-chart-status-bands 10 110) nil)))
    (should (equal (mapcar (lambda (b) (plist-get b :status)) bands)
                   '("low" "near" "ok" "near" "high")))
    (should (equal (mapcar (lambda (b) (cons (plist-get b :low) (plist-get b :high))) bands)
                   '((0 . 10) (10 . 30.0) (30.0 . 90.0) (90.0 . 110) (110 . 210)))))
  ;; a range that starts at 0 has nothing below it
  (should (equal (mapcar (lambda (b) (plist-get b :status))
                         (append (health-chart-status-bands 0 100) nil))
                 '("near" "ok" "near" "high")))
  (should (equal (mapcar (lambda (b) (plist-get b :status))
                         (append (health-chart-status-bands nil 90) nil))
                 '("ok" "near" "high"))))

(ert-deftest health-chart-status-category-bands ()
  (let ((bands [(:label "a" :low 0 :high 10 :status "low")
                (:label "b" :low 10 :high 20 :status "ok")
                (:label "c" :low 20 :high 30 :status "high")
                (:label "d" :low 30 :high 40)]))
    (should (eq (health-chart-status-band 0 bands) 'low))
    (should (eq (health-chart-status-band 9.99 bands) 'low))
    (should (eq (health-chart-status-band 10 bands) 'ok))
    (should (eq (health-chart-status-band 20 bands) 'high))
    ;; a band without a status, a gap and a non-number are unknown
    (should (eq (health-chart-status-band 35 bands) 'unknown))
    (should (eq (health-chart-status-band 40 bands) 'unknown))
    (should (eq (health-chart-status-band 41 bands) 'unknown))
    (should (eq (health-chart-status-band -1 bands) 'unknown))
    (should (eq (health-chart-status-band "x" bands) 'unknown))
    ;; only the topmost band holds its upper edge
    (should (eq (health-chart-status-band 30 [(:label "x" :low 0 :high 30 :status "ok")]) 'ok))
    (should (eq (health-chart-status-band 10 [(:low 0 :high 10 :status "ok")
                                              (:low 10 :high 20 :status "high")]) 'high))))

;;; The eas transform

(defun health-chart-test--status-rows (rows params)
  "The statuses ROWS get from the health-status transform with PARAMS."
  (mapcar (lambda (row) (plist-get row :status))
          (append (health-chart-status--transform (vconcat rows) params) nil)))

(ert-deftest health-chart-status-transform-constant-range ()
  (health-chart-test-with-theme nil nil
    (should (equal (health-chart-test--status-rows
                    '((:value -1) (:value 0) (:value 50) (:value 100) (:value 101) (:value :null))
                    '(:low 0 :high 100))
                   '("low" "near" "ok" "near" "high" "unknown")))
    (should (equal (health-chart-test--status-rows '((:value 5)) '(:low :null)) '("unknown")))
    (should (equal (health-chart-test--status-rows '((:value 5)) nil) '("unknown")))))

(ert-deftest health-chart-status-transform-row-overrides ()
  (health-chart-test-with-theme nil nil
    ;; per row: a warn_margin, a warn_low, a warn_high beat the call and the theme
    (should (equal (health-chart-test--status-rows
                    '((:value 9 :warn_margin 0.05) (:value 4 :warn_low 5) (:value 96 :warn_high 95)
                      (:value 9))
                    '(:low 0 :high 100 :margin 0.2))
                   '("ok" "near" "near" "near")))
    ;; the call's margin beats the theme's
    (health-chart-test-with-theme '(:warn-margin 0.5) nil
      (should (equal (health-chart-test--status-rows '((:value 30)) '(:low 0 :high 100 :margin 0.1))
                     '("ok")))
      (should (equal (health-chart-test--status-rows '((:value 30)) '(:low 0 :high 100))
                     '("near"))))))

(ert-deftest health-chart-status-transform-per-row-limits ()
  (should (equal (health-chart-test--status-rows
                  '((:value 5 :ref_low 0 :ref_high 100)   ; near
                    (:value 5 :ref_low :null :ref_high 100) ; ok, one-sided
                    (:value 5)                              ; unknown
                    (:value 500 :ref_low 0 :ref_high 100)) ; high
                  '(:low_field "ref_low" :high_field "ref_high" :margin 0.2))
                 '("near" "ok" "unknown" "high"))))

(ert-deftest health-chart-status-transform-adds-the-display-fields ()
  (let* ((row (aref (health-chart-status--transform
                     [(:value 101 :note "x")] '(:low 0 :high 100 :margin 0.2))
                    0)))
    (should (equal (plist-get row :status) "high"))
    (should (equal (plist-get row :status_label) "high"))
    (should (equal (plist-get row :status_flag) "H"))
    (should (equal (plist-get row :range_text) "0 to 100"))
    (should (equal (plist-get row :note) "x"))
    ;; band fields for a constant range
    (should (equal (plist-get row :zone_low) 20.0))
    (should (equal (plist-get row :zone_high) 80.0))
    (should (= (plist-get row :band_lo) 0))
    (should (= (plist-get row :band_hi) 100)))
  (let ((row (aref (health-chart-status--transform
                    [(:value 5)] '(:low 0 :high 100 :prefix "sys"))
                   0)))
    (should (equal (plist-get row :sys) "near"))
    (should (equal (plist-get row :sys_label) "near limit"))
    (should-not (plist-member row :status))))

(ert-deftest health-chart-status-transform-pads-a-one-sided-band-from-the-data ()
  (let ((row (aref (health-chart-status--transform
                    [(:value 40) (:value 80)] '(:high 90))
                   0)))
    (should (< (plist-get row :band_lo) 40))
    (should (= (plist-get row :band_hi) 90))
    (should-not (plist-member row :zone_low))
    (should (equal (plist-get row :zone_high) 72.0))))

(ert-deftest health-chart-status-transform-labels-can-be-replaced ()
  (let ((row (aref (health-chart-status--transform
                    [(:value 5)] '(:low 0 :high 100 :labels (:near "borderline")))
                   0)))
    (should (equal (plist-get row :status_label) "borderline"))))

(ert-deftest health-chart-band-status-transform ()
  (let ((rows (health-chart-status--band-transform
               [(:value 4) (:value 15) (:value 99)]
               '(:bands [(:label "lo" :low 0 :high 10 :status "low")
                         (:label "mid" :low 10 :high 20 :status "ok")]))))
    (should (equal (mapcar (lambda (r) (plist-get r :status)) (append rows nil))
                   '("low" "ok" "unknown")))
    (should (equal (plist-get (aref rows 1) :band_label) "mid"))
    (should (equal (plist-get (aref rows 2) :band_label) "no band"))))

;;; Configuration

(ert-deftest health-chart-theme-defaults-are-the-shipped-colors ()
  (health-chart-test-with-theme nil nil
    (should (equal (health-chart-theme-get :bad) "#d03b3b"))
    (should (equal (health-chart-theme-get :warn) "#e09a00"))
    (should (= (health-chart-theme-get :warn-margin) 0.2))))

(ert-deftest health-chart-theme-precedence ()
  (health-chart-test-with-theme '(:bad "#111111" :warn-margin 0.3)
      '(("lab-trend" :bad "#222222"))
    (should (equal (health-chart-theme-get :bad) "#111111"))
    (should (equal (health-chart-theme-get :bad "lab-trend") "#222222"))
    (should (equal (health-chart-theme-get :bad "lab-results") "#111111"))
    (should (= (health-chart-theme-get :warn-margin "lab-trend") 0.3))
    (should (equal (health-chart-theme-get :ok "lab-trend") "#2b9348"))))

(defun health-chart-test--default (template slot)
  "The default of SLOT (a keyword) of TEMPLATE as `eas-template-bind' sees it."
  (plist-get (plist-get (health-chart-describe-template template) :slots) slot))

(ert-deftest health-chart-theme-fills-the-slot-defaults-of-every-template ()
  (health-chart-test-with-theme '(:bad "#101010" :warn "#202020" :ok "#303030" :unknown "#404040"
                                  :warn-margin 0.35)
      nil
    (dolist (name (health-chart-template-names))
      (let ((slots (plist-get (health-chart-describe-template name) :slots)))
        (cl-loop for (key slot) on '(:bad "bad_color" :warn "warn_color" :ok "ok_color"
                                     :unknown "unknown_color" :warn-margin "warn_margin")
                 by #'cddr
                 for def = (plist-get slots (eas-key slot))
                 when def
                 do (should (equal (plist-get def :default) (health-chart-theme-get key))))))))

(ert-deftest health-chart-theme-one-change-reaches-every-status-template ()
  (health-chart-test-with-theme '(:bad "#b00b1e" :warn "#fedcba" :ok "#0a0b0c") nil
    (dolist (name '("lab-results" "lab-trend"))
      (let ((svg (health-chart-render name (health-chart-example name) :backend 'svg)))
        (should (string-match-p "#b00b1e" svg))
        (should (string-match-p "#0a0b0c" svg))
        (should-not (string-match-p "#d03b3b" svg))
        (should-not (string-match-p "#2b9348" svg))))))

(ert-deftest health-chart-theme-per-template-override-leaves-others-alone ()
  (health-chart-test-with-theme nil '(("lab-trend" :bad "#b00b1e"))
    (should (string-match-p "#b00b1e" (health-chart-render "lab-trend" (health-chart-example "lab-trend")
                                                           :backend 'svg)))
    (should-not (string-match-p "#b00b1e" (health-chart-render "lab-results" (health-chart-example "lab-results")
                                                               :backend 'svg)))))

(ert-deftest health-chart-theme-a-binding-wins ()
  (health-chart-test-with-theme '(:bad "#b00b1e") '(("lab-trend" :bad "#c0ffee"))
    (let ((svg (health-chart-render "lab-trend"
                                    (plist-put (copy-sequence (health-chart-example "lab-trend"))
                                               :bad_color "#123456")
                                    :backend 'svg)))
      (should (string-match-p "#123456" svg))
      (should-not (string-match-p "#b00b1e" svg))
      (should-not (string-match-p "#c0ffee" svg)))))

(ert-deftest health-chart-theme-warning-margin-moves-the-yellow-zone ()
  (let ((bindings (list :data [(:time "2026-01-01" :value 4.0) (:time "2026-01-02" :value 4.7)]
                        :low 2.0 :high 5.0)))
    (health-chart-test-with-theme nil nil
      (should (equal (health-chart-test--rows-status "lab-trend" bindings) '("ok" "near")))
      ;; globally
      (health-chart-test-with-theme '(:warn-margin 0.05) nil
        (should (equal (health-chart-test--rows-status "lab-trend" bindings) '("ok" "ok"))))
      ;; for one template
      (health-chart-test-with-theme nil '(("lab-trend" :warn-margin 0.5))
        (should (equal (health-chart-test--rows-status "lab-trend" bindings) '("near" "near"))))
      ;; in the binding
      (should (equal (health-chart-test--rows-status "lab-trend" (append bindings '(:warn_margin 0.05)))
                     '("ok" "ok"))))))

(defun health-chart-test--rows-status (name bindings)
  "The statuses template NAME gives each data row of BINDINGS, as it resolves them.
This is the whole path: slot defaults, theme, binding, transform."
  (mapcar (lambda (row) (plist-get row :status))
          (append (plist-get (plist-get (eas-resolve (plist-get (health-chart--template name) :name)
                                                     bindings)
                                        :data)
                             :values)
                  nil)))

(ert-deftest health-chart-theme-never-holds-a-clinical-value ()
  (should-not (seq-find #'numberp (cl-loop for (k v) on health-chart-theme-defaults by #'cddr
                                           unless (memq k '(:warn-margin :sig-figs :label-max)) collect v))))

;;; Per-row overrides and missing ranges, end to end

(ert-deftest health-chart-warn-margin-is-validated-in-rows-and-slots ()
  (dolist (name (health-chart-template-names))
    (let* ((example (health-chart-example name))
           (tables (plist-get (health-chart-describe-template name) :tables)))
      (cl-loop for (table spec) on tables by #'cddr
               when (plist-member (plist-get spec :fields) :warn_margin)
               do (let ((rows (vconcat (plist-get example table))))
                    (aset rows 0 (plist-put (copy-sequence (aref rows 0)) :warn_margin 2))
                    (health-chart-test-should-code
                     "out_of_range" (format "%s[0].warn_margin" (substring (symbol-name table) 1))
                     (lambda () (health-chart-validate name (plist-put (copy-sequence example) table rows)))))))))

(ert-deftest health-chart-warn-edges-must-lie-inside-the-range ()
  (let* ((b (health-chart-example "lab-results"))
         (rows (vconcat (plist-get b :data))))
    (aset rows 0 (list :analyte "A" :value 5 :ref_low 3 :ref_high 9 :warn_low 2))
    (health-chart-test-should-code
     "warn_outside_range" nil
     (lambda () (health-chart-validate "lab-results" (plist-put (copy-sequence b) :data rows))))
    (aset rows 0 (list :analyte "A" :value 5 :ref_low 3 :ref_high 9 :warn_high 10))
    (health-chart-test-should-code
     "warn_outside_range" nil
     (lambda () (health-chart-validate "lab-results" (plist-put (copy-sequence b) :data rows))))))

(ert-deftest health-chart-lab-results-colors-by-row-end-to-end ()
  (health-chart-test-with-theme nil nil
    (let ((b (list :data [(:analyte "at-low" :value 0 :ref_low 0 :ref_high 100)
                          (:analyte "inside" :value 10 :ref_low 0 :ref_high 100)
                          (:analyte "clear" :value 50 :ref_low 0 :ref_high 100)
                          (:analyte "out" :value 101 :ref_low 0 :ref_high 100)
                          (:analyte "one-sided" :value 50 :ref_high 100)
                          (:analyte "none" :value 50)
                          (:analyte "row-margin" :value 10 :ref_low 0 :ref_high 100 :warn_margin 0.05)
                          (:analyte "row-edge" :value 10 :ref_low 0 :ref_high 100 :warn_low 15)])))
      (should (equal (health-chart-biomarker-test--statuses "lab-results" b)
                     '("near" "near" "ok" "high" "ok" "unknown" "ok" "near"))))))

;;; Every template, scanned

(defun health-chart-test--template-json (name)
  "The raw JSON of template NAME as parsed by eas."
  (eas-json-read-file (expand-file-name (format "templates/%s.json" name) health-chart-test-root)))

(defun health-chart-test--walk (value fn)
  "Call FN on every string inside VALUE, a parsed JSON structure."
  (cond ((stringp value) (funcall fn value))
        ((vectorp value) (seq-doseq (v value) (health-chart-test--walk v fn)))
        ((and (consp value) (keywordp (car value)))
         (cl-loop for (_k v) on value by #'cddr do (health-chart-test--walk v fn)))))

(defun health-chart-test--hue (hex)
  "The HSL hue of HEX (#rrggbb) in degrees and its saturation, as (HUE . SAT)."
  (let* ((r (/ (string-to-number (substring hex 1 3) 16) 255.0))
         (g (/ (string-to-number (substring hex 3 5) 16) 255.0))
         (b (/ (string-to-number (substring hex 5 7) 16) 255.0))
         (mx (max r g b)) (mn (min r g b)) (d (- mx mn))
         (l (/ (+ mx mn) 2.0))
         (s (if (zerop d) 0.0 (/ d (- 1.0 (abs (- (* 2 l) 1.0))))))
         (h (cond ((zerop d) 0.0)
                  ((= mx r) (* 60.0 (mod (/ (- g b) d) 6)))
                  ((= mx g) (* 60.0 (+ 2 (/ (- b r) d))))
                  (t (* 60.0 (+ 4 (/ (- r g) d)))))))
    (cons h s)))

(defun health-chart-test--status-hue-p (hex)
  "Non-nil when HEX is a saturated red, yellow or green."
  (pcase-let ((`(,h . ,s) (health-chart-test--hue hex)))
    (and (> s 0.25)
         (or (< h 25.0) (> h 335.0)         ; red (and the pinks of ECG paper)
             (and (>= h 25.0) (<= h 70.0))  ; orange and yellow
             (and (> h 70.0) (< h 165.0)))))) ; yellow-green and green

(ert-deftest health-chart-no-template-or-example-uses-a-status-hue ()
  "Red, yellow and green belong to the theme; no template or example may name one."
  (let (hits)
    (dolist (name (health-chart-template-names))
      (dolist (data (list (health-chart-test--template-json name)
                          (health-chart-example name)))
        (health-chart-test--walk
         data
         (lambda (s)
           (let ((start 0))
             (while (string-match "#[0-9a-fA-F]\\{6\\}\\b" s start)
               (let ((hex (downcase (match-string 0 s))))
                 (when (health-chart-test--status-hue-p hex)
                   (push (format "%s: %s" name hex) hits)))
               (setq start (match-end 0))))))))
    (should-not (delete-dups hits))))

(ert-deftest health-chart-theme-slots-carry-no-static-default-in-any-template ()
  "A template's JSON never repeats the theme: the defaults live in one place."
  (dolist (name (health-chart-template-names))
    (let ((slots (plist-get (plist-get (health-chart-test--template-json name) :x-eas) :slots)))
      (cl-loop for (_key slot) on health-chart-theme-slots by #'cddr
               for def = (plist-get slots (eas-key slot))
               when def do (should-not (plist-member def :default))))))

(ert-deftest health-chart-no-template-carries-a-clinical-default ()
  "Ranges, cut-offs, goals and category bands are data: never a slot default."
  (dolist (name (health-chart-template-names))
    (let ((slots (plist-get (plist-get (health-chart-test--template-json name) :x-eas) :slots)))
      (cl-loop for (key def) on slots by #'cddr
               for slot = (substring (symbol-name key) 1)
               when (and (string-match-p "\\`\\(\\(.*_\\)?\\(low\\|high\\)\\|bands\\|goal\\|target.*\\)\\'" slot)
                         (plist-member def :default))
               do (should (member (plist-get def :default) '(nil :null [])))))))

(ert-deftest health-chart-status-legends-use-the-same-words ()
  "A legend scale for the status words lists `health-chart-status-labels'.
Templates that take an optimal range also list \"suboptimal\"; the others
list the words without it."
  (let* ((all (mapcar #'cdr health-chart-status-labels))
         (plain (remove "suboptimal" all))
         (seen 0))
    (dolist (name (health-chart-template-names))
      (let (domains)
        (let ((walk nil))
          (setq walk (lambda (v)
                       (cond ((vectorp v)
                              (when (and (> (length v) 0) (stringp (aref v 0))
                                         (member "in range" (append v nil)))
                                (push (append v nil) domains))
                              (seq-doseq (x v) (funcall walk x)))
                             ((and (consp v) (keywordp (car v)))
                              (cl-loop for (_k x) on v by #'cddr do (funcall walk x))))))
          (funcall walk (health-chart-test--template-json name)))
        (dolist (d domains)
          (cl-incf seen)
          ;; time-in-range names its five bands instead of judging one value
          (should (equal (cons name d)
                         (cons name (cond ((equal name "time-in-range")
                                           '("very low" "low" "in range" "high" "very high"))
                                          ((member name health-chart-status-test--optimal-templates)
                                           all)
                                          (t plain))))))))
    (should (> seen 5))))

(defconst health-chart-status-test--optimal-templates
  '("lab-results" "lab-status-grid" "lab-change" "lab-trend" "lipid-panel")
  "The templates that judge against an optimal range inside the reference range.")

(ert-deftest health-chart-lab-recency-uses-no-status-colors ()
  (let ((svg (health-chart-render "lab-recency" (health-chart-example "lab-recency") :backend 'svg)))
    (dolist (key '(:bad :warn :ok))
      (should-not (string-match-p (regexp-quote (health-chart-theme-get key)) svg)))))

;;; Reference range against optimal range

(ert-deftest health-chart-status-reference-and-optimal-both ()
  "Reference 100..199, optimal 100..180: red only outside the reference range."
  (health-chart-test-with-theme nil nil
    (pcase-dolist (`(,value . ,want)
                   '((99.99 . low) (100 . ok) (150 . ok)
                     (180 . ok) (180.01 . suboptimal) (184 . suboptimal)
                     (199 . suboptimal) (199.01 . high) (250 . high)))
      (should (eq (health-chart-status value 100 199 nil nil nil 100 180) want)))))

(ert-deftest health-chart-status-exactly-at-the-reference-limit-is-not-red ()
  (health-chart-test-with-theme nil nil
    (should (eq (health-chart-status 39 39 nil nil nil nil 60 nil) 'suboptimal))
    (should (eq (health-chart-status 38.99 39 nil nil nil nil 60 nil) 'low))
    (should (eq (health-chart-status 199 nil 199 nil nil nil nil 180) 'suboptimal))
    (should (eq (health-chart-status 199.5 nil 199 nil nil nil nil 180) 'high))))

(ert-deftest health-chart-status-exactly-at-the-optimal-limit-is-optimal ()
  (health-chart-test-with-theme nil nil
    (should (eq (health-chart-status 60 39 nil nil nil nil 60 nil) 'ok))
    (should (eq (health-chart-status 59.99 39 nil nil nil nil 60 nil) 'suboptimal))
    (should (eq (health-chart-status 180 nil 199 nil nil nil nil 180) 'ok))
    (should (eq (health-chart-status 180.01 nil 199 nil nil nil nil 180) 'suboptimal))))

(ert-deftest health-chart-status-owner-examples ()
  "HDL 52 (reference >= 39, optimal > 60) and total cholesterol 184
(reference 100-199, optimal < 180) are suboptimal, never red."
  (health-chart-test-with-theme nil nil
    (should (eq (health-chart-status 52 39 nil nil nil nil 60 nil) 'suboptimal))
    (should (eq (health-chart-status 184 100 199 nil nil nil nil 180) 'suboptimal))
    (should (equal (health-chart-status-label 'suboptimal) "suboptimal"))))

(ert-deftest health-chart-status-reference-only-keeps-the-margin ()
  "Without an optimal range the near-limit margin applies as before."
  (health-chart-test-with-theme nil nil
    (should (eq (health-chart-status 10 0 100) 'near))
    (should (eq (health-chart-status 50 0 100) 'ok))
    (should (eq (health-chart-status -1 0 100) 'low))
    (should (eq (health-chart-status 10 0 100 nil nil nil nil nil) 'near))))

(ert-deftest health-chart-status-optimal-only-is-never-red ()
  "No reference limit: outside the optimal range is suboptimal, inside ok."
  (health-chart-test-with-theme nil nil
    (should (eq (health-chart-status 50 nil nil nil nil nil 40 60) 'ok))
    (should (eq (health-chart-status 40 nil nil nil nil nil 40 60) 'ok))
    (should (eq (health-chart-status 60 nil nil nil nil nil 40 60) 'ok))
    (should (eq (health-chart-status 39.9 nil nil nil nil nil 40 60) 'suboptimal))
    (should (eq (health-chart-status 60.1 nil nil nil nil nil 40 60) 'suboptimal))
    (should (eq (health-chart-status 5 nil nil nil nil nil nil 60) 'ok))))

(ert-deftest health-chart-status-optimal-outside-reference-is-ignored ()
  "An optimal limit wider than the reference limit on its side changes nothing."
  (health-chart-test-with-theme nil nil
    (should (eq (health-chart-status 10 0 100 nil nil nil -5 120) 'near))
    (should (eq (health-chart-status 50 0 100 nil nil nil -5 120) 'ok))))

(ert-deftest health-chart-status-optimal-on-one-side-keeps-the-margin-on-the-other ()
  (health-chart-test-with-theme nil nil
    ;; reference 0..100, optimal upper limit 80: low side keeps the 20% margin
    (should (eq (health-chart-status 10 0 100 nil nil nil nil 80) 'near))
    (should (eq (health-chart-status 30 0 100 nil nil nil nil 80) 'ok))
    (should (eq (health-chart-status 90 0 100 nil nil nil nil 80) 'suboptimal))))

(ert-deftest health-chart-status-transform-optimal-fields ()
  (health-chart-test-with-theme nil nil
    (let* ((rows (vector (list :value 52 :ref_low 39 :opt_low 60)
                         (list :value 184 :ref_low 100 :ref_high 199 :opt_high 180)
                         (list :value 30 :ref_low 39 :opt_low 60)))
           (spec '(:value "value" :low_field "ref_low" :high_field "ref_high"
                          :opt_low_field "opt_low" :opt_high_field "opt_high"))
           (out (seq-into (health-chart-status--transform rows spec) 'list)))
      (should (equal (mapcar (lambda (r) (plist-get r :status)) out)
                     '("suboptimal" "suboptimal" "low")))
      (should (equal (plist-get (nth 0 out) :status_label) "suboptimal"))
      (should (equal (plist-get (nth 0 out) :status_flag) ""))
      (should (equal (plist-get (nth 2 out) :status_flag) "L"))
      (should (equal (plist-get (nth 1 out) :range_text) "100 to 199 (optimal \u2264 180)")))))

(ert-deftest health-chart-lipid-panel-optimal-goal-with-a-reference-limit ()
  "Goal = optimal limit, ref_limit = reference limit: yellow between, red beyond."
  (let* ((rows (vector (list :analyte "HDL" :value 52 :unit "mg/dL" :goal 60 :direction "above"
                             :ref_limit 39)
                       (list :analyte "Total" :value 184 :unit "mg/dL" :goal 180 :direction "below"
                             :ref_limit 199)
                       (list :analyte "Total2" :value 205 :unit "mg/dL" :goal 180 :direction "below"
                             :ref_limit 199)
                       (list :analyte "HDL2" :value 70 :unit "mg/dL" :goal 60 :direction "above"
                             :ref_limit 39)
                       (list :analyte "LDL" :value 128 :unit "mg/dL" :goal 100 :direction "below")))
         (b (list :data rows))
         (text (substring-no-properties (health-chart-render "lipid-panel" b :backend 'text)))
         (line (lambda (name) (seq-find (lambda (l) (string-match-p (concat "\\`\\s-*" name " ") l))
                                        (split-string text "\n")))))
    (should (eq t (health-chart-validate "lipid-panel" b)))
    (should (string-match-p "goal >60).*suboptimal" (funcall line "HDL")))
    (should (string-match-p "goal <180).*suboptimal" (funcall line "Total")))
    (should (string-match-p "goal <180).*high" (funcall line "Total2")))
    (should (string-match-p "goal >60).*in range" (funcall line "HDL2")))
    (should (string-match-p "goal <100).*high" (funcall line "LDL")))
    ;; the goal stays visible as text
    (should (string-match-p "goal <180" text))
    (should (string-match-p "goal >60" text))
    (should (string-match-p "suboptimal" text))))

(provide 'health-chart-status-test)
;;; health-chart-status-test.el ends here
