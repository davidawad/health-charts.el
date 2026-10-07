;;; health-chart.el --- Medical and health charts from data you supply, on eas -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el
;; Version: 2.1.0
;; Package-Requires: ((emacs "30.1") (eas "0.2.2"))
;; Keywords: hypermedia, tools

;; This file is not part of GNU Emacs.

;;; Commentary:

;; health-chart never fetches or supplies data.  The caller hands it
;; declarative JSON (or the same data as Lisp plists) bound to a
;; template's slots; the package validates that data strictly, with a
;; reason code and a JSON path for every failure, and draws it through
;; the eas chart engine as text in a terminal frame or as an SVG image
;; in a GUI frame.
;;
;; The API:
;;
;;   (health-chart-list-templates)             every template, one line each
;;   (health-chart-describe-template NAME)     slots, data shape, example
;;   (health-chart-example NAME)               bindings that render as-is
;;   (health-chart-validate NAME BINDINGS)     t, or `health-chart-invalid-data'
;;   (health-chart-check NAME BINDINGS)        t, or (:code :path :index :field :message)
;;   (health-chart-render NAME BINDINGS ...)   a string: SVG or text
;;   (health-chart-open NAME BINDINGS ...)     a live eas view in a buffer
;;   (health-chart-read-bindings FILE-OR-JSON) parse bindings from JSON

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'eas)
(require 'health-chart-eas)
(require 'health-chart-theme)
(require 'health-chart-status)
(require 'health-chart-fit)
(require 'health-chart-core)
(require 'health-chart-validate)

(defgroup health-chart nil
  "Medical and health charts drawn by eas from data you supply."
  :group 'hypermedia
  :prefix "health-chart-")

(defcustom health-chart-backend 'auto
  "How `health-chart-render' draws: `text', `svg' or `auto'.
`auto' draws SVG in a graphical frame that can show it, else text."
  :type '(choice (const auto) (const text) (const svg))
  :group 'health-chart)

(defconst health-chart--default-text-size '(90 24)
  "Columns and rows of a text chart whose template names no size.")

(defconst health-chart--default-svg-size '(900 400)
  "Width and height in pixels of an SVG chart whose template names no size.")

;;; Reading bindings

;;;###autoload
(defun health-chart-read-bindings (source)
  "Parse bindings from SOURCE, a JSON file name or a JSON string.
Objects become plists, arrays vectors, null `:null' (what eas reads)."
  (if (file-readable-p source)
      (eas-json-read-file source)
    (eas-json-parse source)))

;;; Catalog

;;;###autoload
(defun health-chart-list-templates ()
  "Every template as (NAME :group GROUP :doc DOC), sorted by group then name."
  (let ((rows (mapcar
               (lambda (name)
                 (let* ((meta (plist-get (health-chart--template name) :meta)))
                   (list name :group (or (plist-get (plist-get meta :health) :group) "other")
                         :doc (plist-get meta :doc))))
               (health-chart-template-names))))
    (sort rows (lambda (a b)
                 (let ((ga (plist-get (cdr a) :group)) (gb (plist-get (cdr b) :group)))
                   (if (equal ga gb) (string< (car a) (car b)) (string< ga gb)))))))

;;;###autoload
(defun health-chart-describe-template (name)
  "NAME's description as a plist.
:name, :doc, :group, :slots (eas's slot definitions), :tables (the
rows each data slot takes: field name to type), :rules, :example (the
bindings that render as-is) and the default :text-size and :svg-size."
  (let* ((template (health-chart--template name))
         (meta (plist-get template :meta))
         (health (plist-get meta :health)))
    (list :name (health-chart--short (plist-get template :name))
          :doc (plist-get meta :doc)
          :group (plist-get health :group)
          :slots (plist-get meta :slots)
          :tables (plist-get health :tables)
          :rules (plist-get health :rules)
          :slots-typed (plist-get health :slots)
          :example (eas-template-example (plist-get template :name))
          :text-size (or (plist-get health :text_size) health-chart--default-text-size)
          :svg-size (or (plist-get health :svg_size) health-chart--default-svg-size))))

;;;###autoload
(defun health-chart-example (name)
  "Bindings for template NAME that render as-is.  The data is synthetic."
  (eas-template-example (plist-get (health-chart--template name) :name)))

;;; Rendering

(defun health-chart--backend (backend)
  "BACKEND (`text', `svg' or `auto'/nil) as `text' or `svg'."
  (pcase (or backend health-chart-backend)
    ((or 'text 'svg) (or backend health-chart-backend))
    ('auto (if (and (display-graphic-p) (image-type-available-p 'svg)) 'svg 'text))
    (other (signal 'health-chart-backend-error
                   (list (format "Unknown backend %S; use text, svg or auto" other)
                         :code "unknown_backend" :path nil :index nil :field nil)))))

(defun health-chart--size (template backend props)
  "The eas :size for TEMPLATE on BACKEND from PROPS.
PROPS may hold :width, :height, :pixel-width and :pixel-height."
  (let* ((health (plist-get (plist-get template :meta) :health))
         (text (append (or (plist-get health :text_size) health-chart--default-text-size) nil))
         (svg (append (or (plist-get health :svg_size) health-chart--default-svg-size) nil)))
    (if (eq backend 'text)
        (list :cols (or (plist-get props :width) (car text))
              :rows (or (plist-get props :height) (cadr text)))
      (cons (or (plist-get props :pixel-width) (plist-get props :width) (car svg))
            (or (plist-get props :pixel-height) (plist-get props :height) (cadr svg))))))

(defun health-chart--bindings (bindings props)
  "BINDINGS with PROPS' :title laid over its title."
  (if (stringp (plist-get props :title))
      (plist-put (copy-sequence bindings) :title (plist-get props :title))
    bindings))

(defun health-chart--resolve (template bindings props)
  "The pure Vega-Lite spec of TEMPLATE for BINDINGS.
A string :font in PROPS becomes config.font."
  (let ((spec (eas-resolve (plist-get template :name) bindings))
        (font (plist-get props :font)))
    (if (stringp font)
        (plist-put spec :config (plist-put (copy-sequence (plist-get spec :config)) :font font))
      spec)))

;;;###autoload
(defun health-chart-render (name bindings &rest props)
  "Draw template NAME from BINDINGS and return it as a string.
BINDINGS is a plist keyed by slot (`health-chart-read-bindings' reads
JSON).  It is validated first (`health-chart-validate').  PROPS:
:backend `text', `svg' or `auto' (default `health-chart-backend');
:width and :height, text columns and rows or SVG pixels; :pixel-width
and :pixel-height for SVG when both kinds are in play; :title to
override the title slot; :font, an SVG font family.  The result is an
SVG document with the `svg' backend, propertized text (hover help and
the datum behind each cell) with `text'."
  (health-chart-validate name bindings)
  (let* ((template (health-chart--template name))
         (backend (health-chart--backend (plist-get props :backend)))
         (size (health-chart--size template backend props))
         (bindings (health-chart-fit-bindings template (health-chart--bindings bindings props)
                                              backend (if (eq backend 'text) (plist-get size :cols) (car size))))
         (spec (health-chart--resolve template bindings props))
         (scene (eas-compile spec :target backend :size size)))
    (if (eq backend 'text) (eas-text-render scene) (eas-svg-render scene))))

;;;###autoload
(defun health-chart-write (name bindings file &rest props)
  "Render template NAME from BINDINGS into FILE as SVG, or text for a .txt FILE.
PROPS are those of `health-chart-render'; :backend follows FILE's extension."
  (let ((out (apply #'health-chart-render name bindings
                    :backend (if (string-suffix-p ".txt" file) 'text 'svg) props)))
    (with-temp-file file
      (set-buffer-file-coding-system 'utf-8-unix)
      (insert (substring-no-properties out)))
    file))

;;;###autoload
(defun health-chart-insert (name bindings &rest props)
  "Insert template NAME drawn from BINDINGS at point, as an image or text.
PROPS are those of `health-chart-render'."
  (let ((out (apply #'health-chart-render name bindings props)))
    (if (string-prefix-p "<" (string-trim-left out))
        (insert-image (create-image out 'svg t))
      (insert out))))

;;;###autoload
(defun health-chart-open (name bindings &rest props)
  "Open template NAME from BINDINGS as a live eas view and show it.
Hover, crosshair and zoom come from eas.  PROPS: :backend `text' or
`svg' to force one, :id for the view's name.  A grid of draws is
fitted to the window again whenever the view is resized.  Returns the
view."
  (health-chart-validate name bindings)
  (let* ((template (health-chart--template name))
         (backend (and (plist-get props :backend) (health-chart--backend (plist-get props :backend))))
         (view (eas-view-open (plist-get template :name)
                              :bindings (health-chart-fit-bindings template bindings backend nil)
                              :id (plist-get props :id))))
    (health-chart-fit-watch view template bindings)
    (eas-show view backend)
    view))

;;;###autoload
(defun health-chart-demo (name)
  "Open template NAME over its synthetic example data."
  (interactive (list (completing-read "Template: " (health-chart-template-names) nil t)))
  (health-chart-open name (health-chart-example name)))

(require 'health-chart-biomarker)

(provide 'health-chart)
;;; health-chart.el ends here
