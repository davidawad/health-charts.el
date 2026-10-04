;;; health-chart-backend.el --- Rendering backend registry and options -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; The registry of rendering backends (`health-chart-backends'), their
;; customization, and template lookup.  See health-chart-render.el.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)
(require 'health-chart-template)

(define-error 'health-chart-backend-error
  "health-chart: rendering backend failed" 'health-chart-error)

;; -----------------------------------------------------------------------
;; Customization
;; -----------------------------------------------------------------------

(defcustom health-chart-backend 'auto
  "Rendering backend: `auto', `vega-lite', `gnuplot', `text' or `svg'.
`auto' picks per chart: in a frame that shows images the first of
`health-chart-graphic-backends' that is installed and has a template for
the kind, in a terminal the first of `health-chart-terminal-backends',
else native text.  `svg' (the native SVG renderer) is obsolete.
Override per call with the :backend prop."
  :type '(choice (const auto) (const vega-lite) (const gnuplot) (const text)
                 (const :tag "svg (native, obsolete)" svg))
  :group 'health-charts)

(defcustom health-chart-graphic-backends '(vega-lite gnuplot)
  "Backends `auto' tries, in order, where images can be shown."
  :type '(repeat symbol)
  :group 'health-charts)

(defcustom health-chart-terminal-backends '(gnuplot text)
  "Backends `auto' tries, in order, in a terminal (text output)."
  :type '(repeat symbol)
  :group 'health-charts)

(defcustom health-chart-image-scale 1
  "Pixel ratio of PNG output: 2 renders a 720px-wide chart 1440 pixels wide.
Override per call with the :scale prop."
  :type 'number
  :group 'health-charts)

(defcustom health-chart-vl2svg-command nil
  "Command (a list: program and arguments) rendering Vega-Lite to SVG.
nil: vl2svg on variable `exec-path', else
npx -p vega -p vega-lite -p vega-cli vl2svg."
  :type '(choice (const :tag "Auto" nil) (repeat string))
  :group 'health-charts)

(defcustom health-chart-vl2png-command nil
  "Command (a list) rendering Vega-Lite to PNG; nil for vl2png (or npx).
vl2png needs node-canvas; without it PNG comes from vl2svg piped
through `health-chart-rsvg-convert-command'."
  :type '(choice (const :tag "Auto" nil) (repeat string))
  :group 'health-charts)

(defcustom health-chart-vl2pdf-command nil
  "Command (a list) rendering Vega-Lite to PDF; nil for vl2pdf (or npx).
Like vl2png it needs node-canvas, and falls back to rsvg-convert."
  :type '(choice (const :tag "Auto" nil) (repeat string))
  :group 'health-charts)

(defcustom health-chart-vega-lite-raster 'auto
  "How the vega-lite backend makes PNG and PDF.
`auto': vl2png / vl2pdf, falling back to vl2svg + rsvg-convert when they
fail (node-canvas missing) -- the fallback is then remembered for the
session; `vl2png': only vl2png / vl2pdf; `rsvg-convert': always vl2svg +
rsvg-convert."
  :type '(choice (const auto) (const vl2png) (const rsvg-convert))
  :group 'health-charts)

(defcustom health-chart-rsvg-convert-command '("rsvg-convert")
  "Command (a list) converting SVG on stdin to PNG or PDF on stdout."
  :type '(repeat string)
  :group 'health-charts)

(defcustom health-chart-gnuplot-command '("gnuplot")
  "Command (a list) running a gnuplot script read from stdin."
  :type '(repeat string)
  :group 'health-charts)

(defcustom health-chart-tool-directories
  (pcase system-type
    ('windows-nt
     (delq nil (list (when-let* ((pf (getenv "ProgramFiles")))
                       (expand-file-name "gnuplot/bin" pf))
                     (when-let* ((appdata (getenv "APPDATA")))
                       (expand-file-name "npm" appdata)))))
    ('darwin '("/opt/homebrew/bin" "/usr/local/bin")))
  "Directories searched for tools after variable `exec-path'.
A GUI Emacs often starts with a shorter PATH than a shell: on macOS it
misses Homebrew, on Windows the gnuplot installer and npm's global
directory are not always on PATH.  Tools are looked up with
`executable-find', so on Windows gnuplot finds gnuplot.exe and vl2svg
finds npm's vl2svg.cmd shim."
  :type '(repeat directory)
  :group 'health-charts)

(defcustom health-chart-render-timeout 60
  "Seconds a backend tool may run before it is abandoned."
  :type 'natnum
  :group 'health-charts)

;; -----------------------------------------------------------------------
;; Registry
;; -----------------------------------------------------------------------

(defvar health-chart-backends
  '((vega-lite
     :doc "Vega-Lite templates rendered by vl2svg/vl2png/vl2pdf (npm vega-cli)."
     :language json :extension ".vl.json" :graphic t
     :formats (svg png pdf vega-lite)
     :available-p health-chart-vega-lite-available-p
     :explain health-chart-vega-lite-explain
     :render health-chart-vega-lite-render
     :install "npm install -g vega vega-lite vega-cli (needs Node.js; see the README's Requirements)")
    (gnuplot
     :doc "gnuplot templates rendered with the svg, pngcairo, pdfcairo or dumb terminal."
     :language gnuplot :extension ".gp" :graphic t
     :formats (svg png pdf text)
     :available-p health-chart-gnuplot-available-p
     :explain health-chart-gnuplot-explain
     :render health-chart-gnuplot-render
     :install "gnuplot 5.4 or later: apt install gnuplot-nox, brew install gnuplot, or winget install gnuplot.gnuplot")
    (text
     :doc "Native unicode renderers: last-resort terminal fallback; every kind."
     :native :text :formats (text)
     :available-p always)
    (svg
     :doc "Native SVG renderers (obsolete: never chosen by default, no new features)."
     :native :svg :obsolete t :formats (svg)
     :available-p always))
  "Rendering backends: (NAME . PLIST).
PLIST keys: :doc; :formats, the formats it writes (svg png pdf text
vega-lite); :available-p, a function of no arguments; for template
backends :language (json or gnuplot) and :extension (of its template
files), :explain (SPEC FORMAT &optional OUT) -> plan with the generated
:program and the exact :steps (argv and stdin), and :render (SPEC
FORMAT OUT) -> OUT, or the output as a string when OUT is nil; for
native backends :native, the `health-chart-kinds' renderer key.")

(defconst health-chart-formats
  '((svg . ".svg") (png . ".png") (pdf . ".pdf") (text . ".txt") (vega-lite . ".vl.json"))
  "Output formats and their file extensions.")

(defun health-chart--backend (name)
  "The registry plist of backend NAME, or signal."
  (or (alist-get name health-chart-backends)
      (signal 'health-chart-backend-error
              (list (format "unknown backend %S; use auto or one of %s" name
                            (mapconcat (lambda (b) (symbol-name (car b))) health-chart-backends ", "))
                    :code "unknown_backend" :backend name))))

(defun health-chart-backend-available-p (name)
  "Non-nil when backend NAME's tools are installed."
  (let ((fn (plist-get (health-chart--backend name) :available-p)))
    (and fn (funcall fn) t)))

(defun health-chart-template-for (backend kind)
  "Return the template file of BACKEND for KIND, or nil (always for natives)."
  (when-let* ((ext (plist-get (health-chart--backend backend) :extension)))
    (health-chart-template-find backend kind ext)))

(provide 'health-chart-backend)
;;; health-chart-backend.el ends here
