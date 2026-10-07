;;; screenshots.el --- Render every template's example into docs/screenshots -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Writes docs/screenshots/NAME.svg and NAME.png for every template, drawn
;; from its synthetic example bindings by `health-chart-render' (the SVG
;; backend) and rasterised with rsvg-convert.  Run from the repository
;; root:
;;
;;   make screenshots EAS=/path/to/eas.el
;;
;; HEALTH_CHART_SCREENSHOT_ONLY=name1,name2 limits the templates drawn.
;; The README catalog embeds the PNGs.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'health-chart)

(defconst health-chart-screenshots-root
  (file-name-directory (directory-file-name (file-name-directory (or load-file-name buffer-file-name))))
  "The repository root.")

(defun health-chart-screenshots--svg-width (name)
  "Template NAME's default SVG width in pixels."
  (car (append (plist-get (health-chart-describe-template name) :svg-size) nil)))

(let* ((dir (expand-file-name "docs/screenshots" health-chart-screenshots-root))
       (only (when-let* ((s (getenv "HEALTH_CHART_SCREENSHOT_ONLY"))) (split-string s ",")))
       (rsvg (or (executable-find "rsvg-convert")
                 (error "rsvg-convert not found; install librsvg"))))
  (make-directory dir t)
  (dolist (name (health-chart-template-names))
    (when (or (null only) (member name only))
      (let ((svg (expand-file-name (concat name ".svg") dir))
            (png (expand-file-name (concat name ".png") dir)))
        (health-chart-write name (health-chart-example name) svg :backend 'svg)
        (unless (zerop (call-process rsvg nil nil nil "-w" (number-to-string
                                                           (* 2 (health-chart-screenshots--svg-width name)))
                                     svg "-o" png))
          (error "rsvg-convert failed for %s" name))
        (delete-file svg)
        (message "wrote %s" png)))))

;;; screenshots.el ends here
