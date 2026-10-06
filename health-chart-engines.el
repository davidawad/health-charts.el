;;; health-chart-engines.el --- The vega-lite and gnuplot template backends -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Fill a backend's template for a chart spec and run its tool:
;; the :explain and :render functions of `health-chart-backends'.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)
(require 'health-chart-template)
(require 'health-chart-backend)
(require 'health-chart-tools)

;; -----------------------------------------------------------------------
;; vega-lite
;; -----------------------------------------------------------------------

(defun health-chart--template-program (backend spec format)
  "(FILE . PROGRAM): BACKEND's template for SPEC's kind filled for FORMAT."
  (let* ((plist (health-chart--backend backend))
         (kind (plist-get spec :kind))
         (file (or (health-chart-template-for backend kind)
                   (signal 'health-chart-backend-error
                           (list (format "no %s template for kind %s; add %s/%s%s to a directory of `health-chart-template-directories'"
                                         backend kind backend kind (plist-get plist :extension))
                                 :code "no_template" :backend backend :kind kind))))
         (context (append (list :data (plist-get spec :rows)
                                :format (symbol-name format)
                                :scale (or (plist-get spec :scale) 1))
                          spec)))
    (cons file (health-chart-template-fill (health-chart-template-read file) context
                                           (plist-get plist :language) file))))

(defun health-chart-vega-lite-explain (spec format &optional _out)
  "Return the vega-lite plan for SPEC in FORMAT (see `health-chart-backends')."
  (health-chart--vega-lite-plan (health-chart--template-program 'vega-lite spec format)
                                format (or (plist-get spec :scale) health-chart-image-scale)))

(defun health-chart--vega-lite-plan (filled format scale)
  "The vega-lite plan writing FORMAT at pixel ratio SCALE from FILLED.
FILLED is (TEMPLATE-FILE . PROGRAM): a filled user template, or the
Vega-Lite an eas template resolves to."
  (let* ((svg (health-chart--command health-chart-vl2svg-command "vl2svg" "vl2svg"))
         (rsvg (lambda (fmt)
                 (list (list :argv svg)
                       (list :argv (append health-chart-rsvg-convert-command
                                           (list "-f" fmt "-z" (format "%s" scale)))))))
         (direct (lambda (custom exe)
                   (list (list :argv (append (health-chart--command custom exe exe)
                                             (when (equal exe "vl2png")
                                               (list "-s" (format "%s" scale))))))))
         (raster (lambda (custom exe fmt)
                   (pcase (if (and (eq health-chart-vega-lite-raster 'auto)
                                   health-chart--vl-canvas-broken)
                              'rsvg-convert
                            health-chart-vega-lite-raster)
                     ('rsvg-convert (list :steps (funcall rsvg fmt)))
                     ('vl2png (list :steps (funcall direct custom exe)))
                     (_ (list :steps (funcall direct custom exe)
                              :fallback (funcall rsvg fmt)))))))
    (append (list :backend 'vega-lite :format format :template (car filled)
                  :program (cdr filled))
            (pcase format
              ('vega-lite (list :steps nil))
              ('svg (list :steps (list (list :argv svg))))
              ('png (funcall raster health-chart-vl2png-command "vl2png" "png"))
              ('pdf (funcall raster health-chart-vl2pdf-command "vl2pdf" "pdf"))
              (_ (signal 'health-chart-backend-error
                         (list (format "vega-lite cannot write %s; use svg, png, pdf or vega-lite" format)
                               :code "unsupported_format")))))))

;; -----------------------------------------------------------------------
;; gnuplot
;; -----------------------------------------------------------------------

(defun health-chart--gp-font (spec scale)
  "The gnuplot font string for SPEC at SCALE."
  (format "%s,%s" (plist-get spec :font)
          (health-chart-template--number (* scale (plist-get spec :font_size)))))

(defun health-chart-gnuplot-preamble (spec format out)
  "Return the gnuplot lines selecting FORMAT's terminal for SPEC, writing OUT."
  (let* ((w (plist-get spec :width)) (h (plist-get spec :height))
         (scale (or (plist-get spec :scale) health-chart-image-scale))
         (bg (plist-get (plist-get spec :colors) :surface))
         (q #'health-chart-template--gp-string))
    (string-join
     (delq nil
           (list
            (format "# health-chart: %s chart, %s, generated from a template" (plist-get spec :kind) format)
            "set encoding utf8"
            (pcase format
              ('svg (format "set terminal svg size %d,%d dynamic noenhanced font %s background %s"
                            w h (funcall q (health-chart--gp-font spec 1)) (funcall q bg)))
              ('png (format "set terminal pngcairo size %d,%d noenhanced font %s fontscale %s linewidth %s pointscale %s background %s"
                            (round (* scale w)) (round (* scale h))
                            (funcall q (health-chart--gp-font spec 1))
                            (health-chart-template--number scale)
                            (health-chart-template--number scale)
                            (health-chart-template--number scale) (funcall q bg)))
              ('pdf (format "set terminal pdfcairo size %sin,%sin noenhanced font %s background %s"
                            (health-chart-template--number (/ w 96.0))
                            (health-chart-template--number (/ h 96.0))
                            (funcall q (health-chart--gp-font spec 0.75)) (funcall q bg)))
              ('text (format "set terminal dumb noenhanced size %d,%d"
                             (plist-get spec :text_width) (plist-get spec :text_height)))
              (_ (signal 'health-chart-backend-error
                         (list (format "gnuplot cannot write %s; use svg, png, pdf or text" format)
                               :code "unsupported_format"))))
            (when (and out (memq format '(png pdf)))
              (format "set output %s" (funcall q (expand-file-name out))))
            "set datafile separator \"\\t\""
            "set datafile columnheaders"
            ""))
     "\n")))

(defun health-chart-gnuplot-explain (spec format &optional out)
  "Return the gnuplot plan for SPEC in FORMAT writing OUT.
The plan has the template, :program and :steps.
PNG and PDF are written by gnuplot itself to OUT (a temporary file when
OUT is nil); SVG and text come back on stdout."
  (let* ((filled (health-chart--template-program 'gnuplot spec format)))
    (list :backend 'gnuplot :format format :template (car filled)
          :program (concat (health-chart-gnuplot-preamble spec format out) (cdr filled)
                           (if (string-suffix-p "\n" (cdr filled)) "" "\n")
                           (if (memq format '(png pdf)) "unset output\n" ""))
          :steps (list (list :argv health-chart-gnuplot-command
                             :writes-file (and (memq format '(png pdf)) t))))))

(defun health-chart-gnuplot-render (spec format out)
  "Render SPEC with gnuplot as FORMAT to OUT, or return the output.
gnuplot writes PNG and PDF itself (to a temporary file when OUT is nil)."
  (cond
   ((not (memq format '(png pdf)))
    (health-chart--render-plan (health-chart-gnuplot-explain spec format out) format out))
   (out
    (let ((plan (health-chart-gnuplot-explain spec format out)))
      (health-chart--pipe (plist-get plan :steps) (plist-get plan :program) nil)
      out))
   (t
    (let ((tmp (make-temp-file "health-chart" nil (alist-get format health-chart-formats))))
      (unwind-protect
          (progn (health-chart-gnuplot-render spec format tmp)
                 (health-chart--read-bytes tmp))
        (delete-file tmp))))))

(defun health-chart-vega-lite-render (spec format out)
  "Render SPEC with Vega-Lite as FORMAT to OUT, or return the output."
  (health-chart--render-plan (health-chart-vega-lite-explain spec format out) format out))

(provide 'health-chart-engines)
;;; health-chart-engines.el ends here
