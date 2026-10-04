;;; reports.el --- Stamp every Org report template against the sample panel -*- lexical-binding: t; -*-

;; Usage: emacs -Q --batch -L . -l examples/reports.el [OUT-DIR]
;; Writes OUT-DIR/NAME.org (default examples/reports), its NAME-assets/
;; chart images and NAME.html for every bundled report template, from
;; the synthetic examples/sample-panel.json (person alex, period
;; 2024-10-01 to 2025-09-30).  Needs vl2svg and gnuplot for the images;
;; genetics.el is not loaded, so genetics blocks hold their note.
;; examples/report-screenshot.sh turns one HTML export into the README
;; image.

;;; Code:

(require 'health-chart)
(require 'health-chart-org)
(require 'ox-html)

(defconst health-chart-reports-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "The examples directory.")

(defconst health-chart-reports-context
  '(:person "alex" :date "2025-10-01" :since "2024-10-01" :until "2025-09-30")
  "Placeholder values every sample report is stamped with.")

(defconst health-chart-reports-style
  "<style>body{max-width:60rem;margin:2rem auto;padding:0 1rem;font-family:'DejaVu Sans',sans-serif;line-height:1.45;color:#222}
img{max-width:100%;height:auto}table{border-collapse:collapse;margin:1rem 0}
td,th{padding:.25rem .6rem;border-bottom:1px solid #ddd}th{text-align:left}
figure p{font-size:.9rem;color:#555}.subtitle{color:#666}</style>"
  "Stylesheet of the sample HTML exports.")

(defun health-chart-reports-sample ()
  "The synthetic sample panel, parsed."
  (json-parse-string
   (with-temp-buffer
     (insert-file-contents (expand-file-name "sample-panel.json" health-chart-reports-dir))
     (buffer-string))
   :object-type 'alist :array-type 'list :null-object nil))

(defun health-chart-reports (&optional dir)
  "Stamp, refresh and export every report template into DIR."
  (let* ((dir (file-name-as-directory
               (expand-file-name (or dir "reports") health-chart-reports-dir)))
         (health-chart-source-function #'health-chart-source-static)
         (health-chart-source-static-data (health-chart-reports-sample))
         (health-chart-org-template-directories nil)
         (org-export-time-stamp-file nil)
         (org-html-validation-link nil)
         (org-html-postamble nil)
         (org-html-head-include-scripts nil)
         (org-html-head-extra health-chart-reports-style)
         (make-backup-files nil))
    (make-directory dir t)
    (dolist (tpl (health-chart-org-template-list))
      (let* ((name (plist-get tpl :name))
             (org (expand-file-name (concat name ".org") dir)))
        (let ((assets (health-chart-org-asset-dir org)))
          (when (file-directory-p assets) (delete-directory assets t)))
        (apply #'health-chart-org-new-report name org health-chart-reports-context)
        (with-current-buffer (find-file-noselect org)
          (random name)               ; reproducible heading ids
          (org-export-to-file 'html (expand-file-name (concat name ".html") dir))
          (kill-buffer))
        (message "wrote %s" org)))))

(when noninteractive
  (health-chart-reports (car command-line-args-left))
  (setq command-line-args-left nil))

;;; reports.el ends here
