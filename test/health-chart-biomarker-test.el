;;; health-chart-biomarker-test.el --- the biomarker/v1 input adapter -*- lexical-binding: t; -*-

;;; Commentary:

;; Synthetic envelopes only (test/fixtures/biomarker/).  The adapter is
;; pure: these tests also run it with every process and file primitive
;; replaced by an error.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'health-chart)
(require 'health-chart-biomarker)
(require 'health-chart-test-support)

(defun health-chart-biomarker-test--fixture (name)
  "The synthetic envelope test/fixtures/biomarker/NAME.json, parsed."
  (health-chart-read-bindings
   (expand-file-name (concat "test/fixtures/biomarker/" name ".json") health-chart-test-root)))

(defun health-chart-biomarker-test--rows (bindings table)
  "The rows of TABLE in BINDINGS as a list."
  (append (plist-get bindings table) nil))

(defun health-chart-biomarker-test--row (bindings table field value)
  "The row of TABLE in BINDINGS whose FIELD is VALUE."
  (seq-find (lambda (row) (equal (plist-get row field) value))
            (health-chart-biomarker-test--rows bindings table)))

(defun health-chart-biomarker-test--no-nulls-p (value)
  "Non-nil when the parsed JSON VALUE holds no :null anywhere."
  (cond ((eq value :null) nil)
        ((vectorp value) (seq-every-p #'health-chart-biomarker-test--no-nulls-p value))
        ((and (consp value) (keywordp (car value)))
         (cl-loop for (_k v) on value by #'cddr always (health-chart-biomarker-test--no-nulls-p v)))
        (t t)))

(defun health-chart-biomarker-test--statuses (name bindings)
  "The status every data row of template NAME gets from BINDINGS, resolved."
  (mapcar (lambda (row) (plist-get row :status))
          (append (plist-get (plist-get (eas-resolve (plist-get (health-chart--template name) :name)
                                                     bindings)
                                        :data)
                             :values)
                  nil)))

(defun health-chart-biomarker-test--check (name bindings)
  "Assert BINDINGS validate against template NAME and render as text; return them."
  (should (eq t (health-chart-validate name bindings)))
  (should (health-chart-biomarker-test--no-nulls-p bindings))
  (let ((text (substring-no-properties (health-chart-render name bindings :backend 'text))))
    (should (> (length text) 200)))
  bindings)

;;; lab-results

(ert-deftest health-chart-biomarker-lab-results ()
  (let* ((env (health-chart-biomarker-test--fixture "latest-all"))
         (b (health-chart-biomarker-test--check "lab-results" (health-chart-from-biomarker "lab-results" env)))
         (rows (health-chart-biomarker-test--rows b :data)))
    ;; the qualified crp row has no numeric value and is skipped
    (should (= (length rows) 6))
    (let ((a1c (health-chart-biomarker-test--row b :data :analyte "Hemoglobin A1c")))
      (should (= (plist-get a1c :value) 5.9))
      (should (equal (plist-get a1c :unit) "%"))
      (should (= (plist-get a1c :ref_low) 4.0))
      (should (= (plist-get a1c :ref_high) 5.6)))
    ;; one-sided ranges keep only their limit, a missing range keeps none
    (let ((ldl (health-chart-biomarker-test--row b :data :analyte "LDL cholesterol")))
      (should-not (plist-member ldl :ref_low))
      (should (= (plist-get ldl :ref_high) 4.9)))
    (let ((hdl (health-chart-biomarker-test--row b :data :analyte "HDL cholesterol")))
      (should (= (plist-get hdl :ref_low) 1.0))
      (should-not (plist-member hdl :ref_high)))
    (let ((lpa (health-chart-biomarker-test--row b :data :analyte "Lipoprotein(a)")))
      (should-not (plist-member lpa :ref_low))
      (should-not (plist-member lpa :ref_high)))
    ;; the colors those ranges give: LDL 3.9 is inside its reference range
    ;; (<= 4.9) but over its optimal limit (3.4): suboptimal, not red
    (let ((ldl (health-chart-biomarker-test--row b :data :analyte "LDL cholesterol")))
      (should (= (plist-get ldl :opt_high) 3.4))
      (should-not (plist-member ldl :opt_low)))
    (should (equal (health-chart-biomarker-test--statuses "lab-results" b)
                   '("high" "ok" "suboptimal" "low" "near" "unknown")))))

(ert-deftest health-chart-biomarker-markers-and-category-filters ()
  (let ((env (health-chart-biomarker-test--fixture "latest-all")))
    (should (= (length (plist-get (health-chart-from-biomarker "lab-results" env :category "lipids") :data)) 3))
    (should (= (length (plist-get (health-chart-from-biomarker "lab-results" env :markers '("hba1c" "ldl")) :data)) 2))
    (should (equal (plist-get (health-chart-from-biomarker "lab-results" env :title "Mine") :title) "Mine"))
    (health-chart-test-should-code
     "no_rows" nil (lambda () (health-chart-from-biomarker "lab-results" env :markers '("nope"))))))

;;; lab-status-grid, lab-change

(ert-deftest health-chart-biomarker-lab-status-grid ()
  (let* ((b (health-chart-biomarker-test--check
             "lab-status-grid"
             (health-chart-from-biomarker "lab-status-grid"
                                          (health-chart-biomarker-test--fixture "measurements-lipids"))))
         (rows (health-chart-biomarker-test--rows b :data)))
    (should (= (length rows) 6))
    ;; oldest draw first, as the template requires
    (should (equal (mapcar (lambda (r) (plist-get r :time)) rows)
                   (sort (mapcar (lambda (r) (plist-get r :time)) rows) #'string<)))
    (let ((hdl (seq-find (lambda (r) (and (equal (plist-get r :analyte) "HDL cholesterol")
                                          (equal (plist-get r :time) "2026-03-01")))
                         rows)))
      (should (= (plist-get hdl :value) 0.9))
      (should (= (plist-get hdl :ref_low) 1.0))
      (should-not (plist-member hdl :ref_high)))))

(ert-deftest health-chart-biomarker-lab-change ()
  (let* ((b (health-chart-biomarker-test--check
             "lab-change"
             (health-chart-from-biomarker "lab-change"
                                          (health-chart-biomarker-test--fixture "measurements-lipids"))))
         (hdl (health-chart-biomarker-test--row b :data :analyte "HDL cholesterol")))
    (should (= (length (plist-get b :data)) 3))
    (should (= (plist-get hdl :before) 1.2))
    (should (= (plist-get hdl :after) 0.9)))
  ;; one result per marker cannot be a change
  (health-chart-test-should-code
   "too_few_results" nil
   (lambda () (health-chart-from-biomarker "lab-change" (health-chart-biomarker-test--fixture "latest-all")))))

;;; lab-trend, lab-panel, lipid-panel

(ert-deftest health-chart-biomarker-lab-trend ()
  (let* ((b (health-chart-biomarker-test--check
             "lab-trend"
             (health-chart-from-biomarker "lab-trend"
                                          (health-chart-biomarker-test--fixture "measurements-hba1c")))))
    (should (= (length (plist-get b :data)) 5))
    (should (= (plist-get b :low) 4.0))
    (should (= (plist-get b :high) 5.6))
    (should (eq (plist-get b :show_optimal) t))
    (should (= (plist-get b :opt_low) 4.5))
    (should (= (plist-get b :opt_high) 5.3))
    (should (equal (plist-get b :y_title) "Hemoglobin A1c (%)"))
    (should (equal (plist-get b :title) "Hemoglobin A1c")))
  ;; a one-sided range leaves the other slot out, so the template sees it as missing
  (let ((b (health-chart-biomarker-test--check
            "lab-trend"
            (health-chart-from-biomarker "lab-trend"
                                         (health-chart-biomarker-test--fixture "measurements-lipids")
                                         :marker "hdl"))))
    (should (= (plist-get b :low) 1.0))
    (should-not (plist-member b :high))
    (should-not (plist-member b :show_optimal))))

(ert-deftest health-chart-biomarker-lab-trend-needs-one-marker ()
  (health-chart-test-should-code
   "marker_required" nil
   (lambda () (health-chart-from-biomarker "lab-trend" (health-chart-biomarker-test--fixture "latest-all"))))
  (health-chart-test-should-code
   "marker_not_found" nil
   (lambda () (health-chart-from-biomarker "lab-trend" (health-chart-biomarker-test--fixture "latest-all")
                                           :marker "nope"))))

(ert-deftest health-chart-biomarker-lab-panel ()
  (let* ((b (health-chart-biomarker-test--check
             "lab-panel"
             (health-chart-from-biomarker "lab-panel"
                                          (health-chart-biomarker-test--fixture "measurements-lipids"))))
         (hdl (health-chart-biomarker-test--row b :panels :analyte "hdl")))
    (should (= (length (plist-get b :panels)) 3))
    (should (= (length (plist-get b :data)) 6))
    (should (equal (plist-get hdl :label) "HDL cholesterol"))
    (should (= (plist-get hdl :low) 1.0))
    (should-not (plist-member hdl :high))))

(ert-deftest health-chart-biomarker-lipid-panel ()
  (let* ((b (health-chart-biomarker-test--check
             "lipid-panel"
             (health-chart-from-biomarker "lipid-panel"
                                          (health-chart-biomarker-test--fixture "measurements-lipids"))))
         (ldl (health-chart-biomarker-test--row b :data :analyte "LDL cholesterol"))
         (hdl (health-chart-biomarker-test--row b :data :analyte "HDL cholesterol"))
         (trig (health-chart-biomarker-test--row b :data :analyte "Triglycerides")))
    ;; the optimal upper limit is the goal, the reference one otherwise
    (should (= (plist-get ldl :goal) 3.4))
    (should (equal (plist-get ldl :direction) "below"))
    (should (= (plist-get ldl :prior) 4.4))
    (should (= (plist-get hdl :goal) 1.0))
    (should (equal (plist-get hdl :direction) "above"))
    (should (= (plist-get trig :goal) 1.7)))
  ;; a marker with no limit has no goal: no chart at all
  (health-chart-test-should-code
   "no_goals" nil
   (lambda () (health-chart-from-biomarker "lipid-panel" (health-chart-biomarker-test--fixture "latest-all")
                                           :markers '("lpa")))))

;;; a1c-trend, weight-bmi-trend

(ert-deftest health-chart-biomarker-a1c-trend ()
  (let* ((b (health-chart-biomarker-test--check
             "a1c-trend"
             (health-chart-from-biomarker "a1c-trend"
                                          (health-chart-biomarker-test--fixture "measurements-hba1c"))))
         (bands (append (plist-get b :bands) nil)))
    (should (= (length (plist-get b :data)) 5))
    ;; bands cut from the data's range 4.0..5.6 with the 0.2 margin (1.6 wide, 0.32)
    (should (equal (mapcar (lambda (x) (plist-get x :status)) bands)
                   '("low" "near" "ok" "near" "high")))
    (should (equal (mapcar (lambda (x) (plist-get x :low)) (cdr bands)) '(4.0 4.32 5.28 5.6)))
    (should (= (plist-get b :target) 5.3)))
  ;; explicit bands win
  (let ((bands [(:label "x" :low 0 :high 10 :status "ok")]))
    (should (equal (plist-get (health-chart-from-biomarker
                               "a1c-trend" (health-chart-biomarker-test--fixture "measurements-hba1c")
                               :bands bands)
                              :bands)
                   bands))))

(ert-deftest health-chart-biomarker-weight-bmi-trend ()
  (let* ((env (health-chart-biomarker-test--fixture "measurements-body"))
         (b (health-chart-biomarker-test--check "weight-bmi-trend"
                                                (health-chart-from-biomarker "weight-bmi-trend" env))))
    (should (= (plist-get b :height_m) 1.78))
    (should (= (length (plist-get b :data)) 4))
    (should (= (plist-get (car (append (plist-get b :data) nil)) :weight_kg) 82.0))
    (should (= (length (plist-get b :bands)) 5))
    (should (= (plist-get (health-chart-from-biomarker "weight-bmi-trend" env :height-m 1.8) :height_m) 1.8)))
  ;; without a height or bands there is nothing honest to draw
  (let ((no-height (vconcat (seq-remove (lambda (r) (member (plist-get r :marker) '("height")))
                                        (append (plist-get (health-chart-biomarker-test--fixture "measurements-body") :data) nil))))
        (no-bmi (vconcat (seq-remove (lambda (r) (member (plist-get r :marker) '("bmi")))
                                     (append (plist-get (health-chart-biomarker-test--fixture "measurements-body") :data) nil)))))
    (health-chart-test-should-code
     "height_required" nil (lambda () (health-chart-from-biomarker "weight-bmi-trend" no-height)))
    (health-chart-test-should-code
     "no_range" nil (lambda () (health-chart-from-biomarker "weight-bmi-trend" no-bmi)))))

;;; Envelope forms and errors

(ert-deftest health-chart-biomarker-accepts-text-and-bare-rows ()
  (let* ((file (expand-file-name "test/fixtures/biomarker/latest-all.json" health-chart-test-root))
         (text (with-temp-buffer (insert-file-contents file) (buffer-string)))
         (parsed (health-chart-biomarker-test--fixture "latest-all")))
    (should (equal (health-chart-from-biomarker "lab-results" text)
                   (health-chart-from-biomarker "lab-results" parsed)))
    (should (equal (health-chart-from-biomarker "lab-results" (plist-get parsed :data))
                   (health-chart-from-biomarker "lab-results" parsed)))))

(ert-deftest health-chart-biomarker-rejects-what-is-not-an-envelope ()
  (health-chart-test-should-code
   "not_biomarker_envelope" nil
   (lambda () (health-chart-from-biomarker "lab-results" '(:schema "chart/v1" :data []))))
  (health-chart-test-should-code
   "not_biomarker_envelope" nil
   (lambda () (health-chart-from-biomarker "lab-results" '(:schema "biomarker/v1"))))
  (health-chart-test-should-code
   "not_biomarker_envelope" nil
   (lambda () (health-chart-from-biomarker "lab-results" 42)))
  (health-chart-test-should-code
   "no_rows" nil
   (lambda () (health-chart-from-biomarker "lab-results" (health-chart-biomarker-test--fixture "latest-empty"))))
  (health-chart-test-should-code
   "unsupported_template" nil
   (lambda () (health-chart-from-biomarker "sleep-duration" (health-chart-biomarker-test--fixture "latest-all")))))

(ert-deftest health-chart-biomarker-is-pure ()
  "No process, no file, no network: only the envelope it is handed."
  (let ((env (health-chart-biomarker-test--fixture "measurements-body"))
        (all (health-chart-biomarker-test--fixture "latest-all"))
        (lipids (health-chart-biomarker-test--fixture "measurements-lipids"))
        (forbidden (lambda (&rest _) (error "impure"))))
    (cl-letf (((symbol-function 'call-process) forbidden)
              ((symbol-function 'call-process-region) forbidden)
              ((symbol-function 'process-file) forbidden)
              ((symbol-function 'start-process) forbidden)
              ((symbol-function 'make-process) forbidden)
              ((symbol-function 'shell-command-to-string) forbidden)
              ((symbol-function 'insert-file-contents) forbidden)
              ((symbol-function 'find-file-noselect) forbidden)
              ((symbol-function 'url-retrieve-synchronously) forbidden))
      (dolist (name health-chart-biomarker-templates)
        (should (health-chart-from-biomarker
                 name (pcase name
                        ("weight-bmi-trend" env)
                        ((or "lab-results") all)
                        (_ lipids))
                 :marker (pcase name ("lab-trend" "ldl") ("a1c-trend" "ldl")))))))
  ;; and the source says so
  (let ((source (with-temp-buffer
                  (insert-file-contents (expand-file-name "src/health-chart-biomarker.el" health-chart-test-root))
                  (buffer-string))))
    (dolist (call '("call-process" "start-process" "make-process" "insert-file-contents"
                    "with-temp-file" "write-region" "shell-command"))
      (should-not (string-match-p (format "(%s[ )]" call) source)))))

(ert-deftest health-chart-biomarker-fixtures-are-synthetic ()
  (dolist (file (directory-files (expand-file-name "test/fixtures/biomarker" health-chart-test-root) t "\\.json\\'"))
    (let ((env (health-chart-read-bindings file)))
      (should (equal (plist-get env :schema) "biomarker/v1"))
      (seq-doseq (row (plist-get env :data))
        (should (equal (plist-get row :person) "synthetic-a"))
        (should (member "synthetic" (append (plist-get row :tags) nil)))))))

(provide 'health-chart-biomarker-test)
;;; health-chart-biomarker-test.el ends here
