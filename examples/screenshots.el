;;; screenshots.el --- Render every templated kind with every backend -*- lexical-binding: t; -*-

;; Usage: [HEALTH_CHART_SCREENSHOT_KINDS="strip dual"] emacs -Q --batch -L . -l examples/screenshots.el [OUT-DIR]
;; (the environment variable limits the kinds drawn).
;; Writes OUT-DIR/<backend>/<kind>.png (default docs/screenshots) at
;; 1200 pixels wide from the synthetic examples/sample-panel.json.
;; Needs vl2svg (+ rsvg-convert or node-canvas) and gnuplot.

;;; Code:

(require 'health-chart)

(defconst health-chart-screenshots-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "The examples directory.")

(defun health-chart-screenshots-sample ()
  "The synthetic sample panel as canonical measurements."
  (health-chart-source-normalize-list
   (json-parse-string
    (with-temp-buffer
      (insert-file-contents (expand-file-name "sample-panel.json" health-chart-screenshots-dir))
      (buffer-string))
    :object-type 'alist :array-type 'list :null-object nil)))

(defun health-chart-screenshots-indicators (ms)
  "Indicator values for alex from MS, as of a fixed day.
Each member is (ID CUTOFF . PARAMS): CUTOFF, when non-nil, keeps only
draws before that date, so the staleness chart shows fresh, due, stale
and (for a marker the sample lacks) undated rows."
  (mapcar (lambda (member)
            (pcase-let ((`(,id ,cutoff . ,params) member))
              (apply #'health-chart-indicator-evaluate id
                     (if cutoff
                         (seq-filter (lambda (m) (string< (plist-get m :date) cutoff)) ms)
                       ms)
                     :as-of "2025-10-01" :cohort "sample" :person "alex" params)))
          '(("health.cardio.apob" nil)
            ("health.cardio.lp-a" "2024-02-01")
            ("health.biomarker.latest" nil :marker "ldl-c")
            ("health.metabolic.hba1c" "2025-04-01")
            ("health.biomarker.latest" "2024-09-01" :marker "tsh")
            ("health.inflammation.hs-crp" nil)
            ("health.vitamin-d" "2025-04-01")
            ("health.biomarker.latest" nil :marker "homocysteine"))))

(defconst health-chart-screenshots-specs
  '((timeseries :person "alex" :marker "ldl-c")
    (panel :person "alex")
    (bullet :person "alex")
    (heatmap :person "alex")
    (compare :marker "vitamin-d")
    (delta :person "alex")
    (staleness)
    (trend :person "alex" :marker "ldl-c")
    (lollipop :person "alex" :marker "hscrp")
    (strip :person "alex")
    (dumbbell :person "alex")
    (dual :person "alex" :marker ("glucose" "hba1c"))
    (inrange :person "alex"))
  "Each templated kind with its screenshot props.")

(defun health-chart-screenshots (&optional dir)
  "Render every kind of `health-chart-screenshots-specs' per backend into DIR."
  (let* ((dir (or dir (expand-file-name "../docs/screenshots" health-chart-screenshots-dir)))
         (ms (health-chart-screenshots-sample))
         (alex (health-chart-filter ms :person "alex"))
         (health-chart-theme 'light))
    (dolist (backend '(vega-lite gnuplot))
      (make-directory (expand-file-name (symbol-name backend) dir) t)
      (pcase-dolist (`(,kind . ,props) health-chart-screenshots-specs)
        (when (or (null (getenv "HEALTH_CHART_SCREENSHOT_KINDS"))
                  (member (symbol-name kind)
                          (split-string (getenv "HEALTH_CHART_SCREENSHOT_KINDS") "[ ,]+" t)))
          (let ((file (expand-file-name (format "%s/%s.png" backend kind) dir))
                (data (if (eq kind 'staleness)
                          (health-chart-screenshots-indicators alex)
                        ms)))
            (condition-case err
                (progn (apply #'health-chart-write kind data file
                              :backend backend :pixel-width 800 :scale 1.5 props)
                       (message "wrote %s" file))
              (error (message "FAILED %s/%s: %s" backend kind
                              (error-message-string err))))))))))

(when noninteractive
  (health-chart-screenshots (car command-line-args-left))
  (setq command-line-args-left nil))

;;; screenshots.el ends here
