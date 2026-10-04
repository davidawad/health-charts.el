;;; health-chart-test-helpers.el --- Shared fixtures for the health-chart tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Fixture paths, synthetic data, golden-file comparison and a
;; deterministic rendering environment.  Regenerate golden files with
;; HEALTH_CHART_UPDATE_GOLDEN=1 make test, then review the diff.

;;; Code:

(require 'ert)
(require 'health-chart)

(defconst health-chart-test-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "The test directory.")

(defconst health-chart-test-fixtures
  (expand-file-name "fixtures" health-chart-test-dir)
  "The fixture directory.")

(defun health-chart-test-fixture (name)
  "Absolute path of fixture NAME."
  (expand-file-name name health-chart-test-fixtures))

(defun health-chart-test-read (name)
  "Contents of fixture NAME."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8-unix))
      (insert-file-contents (health-chart-test-fixture name)))
    (buffer-string)))

(defun health-chart-test-read-utf8 (file)
  "Contents of FILE decoded as UTF-8, whatever the platform default."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (buffer-string)))

(defun health-chart-test-ms (&optional person)
  "Synthetic canonical measurements, for PERSON only when given."
  (let ((ms (health-chart--example-measurements)))
    (if person (health-chart-filter ms :person person) ms)))

(defun health-chart-test-m (&rest props)
  "A canonical measurement from PROPS over a plain LDL-C default."
  (health-chart-source-normalize
   (append props (list :person "alex" :marker "ldl_c" :value 100 :unit "mg/dL"
                       :date "2025-01-01"))))

(defun health-chart-test-golden (name actual)
  "Compare ACTUAL, without text properties, with golden fixture NAME."
  (let ((file (expand-file-name (concat "golden/" name) health-chart-test-fixtures))
        (text (substring-no-properties actual)))
    (when (getenv "HEALTH_CHART_UPDATE_GOLDEN")
      (let ((coding-system-for-write 'utf-8-unix))
        (make-directory (file-name-directory file) t)
        (write-region text nil file nil 'silent)))
    (should (file-exists-p file))
    (should (equal text (with-temp-buffer
                          (let ((coding-system-for-read 'utf-8-unix))
                            (insert-file-contents file))
                          (buffer-string))))))

(defmacro health-chart-test-env (&rest body)
  "Run BODY with every customization that affects output at its default."
  (declare (indent 0) (debug t))
  `(let ((health-chart-width 72)
         (health-chart-height 10)
         (health-chart-show-ref-range t)
         (health-chart-show-optimal-range t)
         (health-chart-sparkline-width 12)
         (health-chart-date-format "%Y-%m-%d")
         (health-chart-svg-theme 'light)
         (health-chart-svg-colors nil)
         (health-chart-svg-width 640)
         (health-chart-svg-height 280)
         (health-chart-svg-font-size 12)
         (health-chart-default-person nil)
         (health-chart-backend 'auto)
         (health-chart-graphic-backends '(vega-lite gnuplot))
         (health-chart-terminal-backends '(text))
         (health-chart-theme 'light)
         (health-chart-colors nil)
         (health-chart-image-width 720)
         (health-chart-image-height 360)
         (health-chart-image-scale 1)
         (health-chart-font-family "DejaVu Sans")
         (health-chart-font-size 12)
         (health-chart-template-directories nil)
         (health-chart-source-function #'health-chart-source-static)
         (health-chart-source-static-data (health-chart--example-measurements)))
     ,@body))

(provide 'health-chart-test-helpers)
;;; health-chart-test-helpers.el ends here
