;;; health-chart-render.el --- Interchangeable rendering backends driven by templates -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Lisp prepares the data, a template draws it.  `health-chart-spec'
;; turns data into a neutral chart spec (chartspec/v1); a BACKEND fills
;; its template for the chart's kind with that spec and runs its tool:
;;
;;   vega-lite  templates/vega-lite/KIND.vl.json -> vl2svg / vl2png /
;;              vl2pdf (PNG and PDF fall back to vl2svg | rsvg-convert
;;              when node-canvas is missing); format vega-lite returns
;;              the filled JSON itself
;;   gnuplot    templates/gnuplot/KIND.gp -> gnuplot with the svg,
;;              pngcairo, pdfcairo or dumb (text) terminal
;;   text       the native unicode renderers: the last-resort terminal
;;              fallback, and the only renderer of table, sparkline,
;;              scorecard and cohort
;;   svg        the native SVG renderers: obsolete, never chosen by
;;              default, kept for callers that ask for them by name
;;
;; `health-chart-backends' is the registry (name -> plist).  Selection,
;; when the caller says :backend auto (the default): a GUI frame (or an
;; image format) takes the first of `health-chart-graphic-backends' that
;; is available and has a template for the kind, a terminal the first of
;; `health-chart-terminal-backends'; failing both, native text.
;;
;; Entry points: `health-chart-render' (an image object in a GUI, else
;; text; or any format as a string), `health-chart-write' (to a file,
;; format from the extension), `health-chart-render-explain' (the exact
;; argv and generated program, pure), `health-chart-templates'.
;; Programs reach tools on stdin or in temporary files; no shell is
;; involved, so no value is ever shell-interpolated.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)
(require 'health-chart-kind)
(require 'health-chart-spec)
(require 'health-chart-template)
(require 'health-chart-backend)
(require 'health-chart-tools)
(require 'health-chart-engines)

;;;###autoload
(defun health-chart-templates ()
  "Every available template as (:backend :kind :path :source), backend order.
:source is user for a file in `health-chart-template-directories', else
bundled.  A user's file shadows the bundled template of the same kind."
  (cl-loop for (name . plist) in health-chart-backends
           for ext = (plist-get plist :extension)
           when ext
           append (mapcar (lambda (entry)
                            (list :backend name :kind (car entry) :path (cdr entry)
                                  :source (if (file-in-directory-p (cdr entry)
                                                                   health-chart-template-bundled-directory)
                                              'bundled 'user)))
                          (health-chart-template-list name ext))))

(defun health-chart--template-kind-p (kind)
  "Non-nil when some template backend has a template for KIND."
  (seq-some (lambda (b) (health-chart-template-for (car b) kind)) health-chart-backends))

(defun health-chart--template-kind-entry (kind)
  "A registry entry for template-only KIND, or nil when no template exists."
  (when (health-chart--template-kind-p kind)
    (list :shape 'measurements :template-only t
          :doc (format "Template-only kind %s (measurements)." kind))))

(add-hook 'health-chart-kind-fallback-functions #'health-chart--template-kind-entry)

;; -----------------------------------------------------------------------
;; The spec
;; -----------------------------------------------------------------------

(defun health-chart--spec-builder (kind)
  "The spec body builder of KIND: its :spec, else a generic one by shape."
  (let ((entry (health-chart--kind kind)))
    (or (plist-get entry :spec)
        (if (eq (plist-get entry :shape) 'indicators)
            #'health-chart-spec-generic-indicators
          #'health-chart-spec-generic))))

;;;###autoload
(defun health-chart-spec (kind data &rest props)
  "The chartspec/v1 plist for KIND over DATA under PROPS.  Pure.
DATA is anything KIND's shape accepts (biomarker/v1 JSON or envelope,
plists, alists); it is normalized and validated first.  PROPS: :person
:marker :title :subtitle :theme (light/dark) :pixel-width :pixel-height
:width/:height (text columns/rows) :ref :optimal, and per-kind props.
`health-chart-spec-to-json' gives the JSON form; docs/chartspec.md the
schema."
  (let ((data (health-chart-normalize kind data)))
    (apply #'health-chart-validate kind data (health-chart--plist-drop props :backend :format))
    (health-chart-spec-build kind data props (health-chart--spec-builder kind))))

;; -----------------------------------------------------------------------
;; Selection
;; -----------------------------------------------------------------------

(defun health-chart--graphic-context-p ()
  "Non-nil when the selected frame can show SVG or PNG images."
  (and (display-images-p)
       (or (image-type-available-p 'svg) (image-type-available-p 'png))))

(defun health-chart--image-format ()
  "The image format this Emacs displays: png when it lacks librsvg, else svg."
  (if (and (not (image-type-available-p 'svg)) (image-type-available-p 'png)) 'png 'svg))

(defun health-chart--supports-p (backend kind format)
  "Non-nil when BACKEND can draw KIND in FORMAT (nil: any of its formats)."
  (let ((plist (health-chart--backend backend)))
    (and (or (null format) (memq format (plist-get plist :formats)))
         (if (plist-get plist :native)
             (fboundp (plist-get (health-chart--kind kind) (plist-get plist :native)))
           (health-chart-template-for backend kind)))))

(defun health-chart-select-backend (kind &optional backend format)
  "(BACKEND FORMAT REASON) for drawing KIND.
BACKEND nil means `health-chart-backend'; FORMAT nil means the natural
format: svg where images show (png when this Emacs was built without
librsvg; text for native text), text in a terminal.  REASON says why,
for `health-chart-explain'."
  (let* ((requested (or backend health-chart-backend))
         (graphic (if format (not (eq format 'text)) (health-chart--graphic-context-p))))
    (if (not (eq requested 'auto))
        (let* ((plist (health-chart--backend requested))
               (formats (plist-get plist :formats))
               (fmt (or format
                        (cond ((and graphic (memq (health-chart--image-format) formats))
                               (health-chart--image-format))
                              ((memq 'text formats) 'text)
                              (t (car formats))))))
          (when (and (plist-get plist :native)
                     (not (functionp (plist-get (health-chart--kind kind) (plist-get plist :native)))))
            (signal 'health-chart-backend-error
                    (list (format "backend %s has no renderer for %s, a kind drawn by templates only; use %s"
                                  requested kind
                                  (mapconcat #'symbol-name
                                             (seq-filter (lambda (b) (and (assq b health-chart-backends)
                                                                          (health-chart-template-for b kind)))
                                                         health-chart-graphic-backends)
                                             " or "))
                          :code "unsupported_kind" :backend requested :kind kind)))
          (unless (memq fmt formats)
            (signal 'health-chart-backend-error
                    (list (format "backend %s cannot write %s; it writes %s" requested fmt
                                  (mapconcat #'symbol-name formats ", "))
                          :code "unsupported_format" :backend requested :format fmt)))
          (list requested fmt (format "requested %s" requested)))
      (let* ((order (if graphic health-chart-graphic-backends health-chart-terminal-backends))
             (want (or format (if graphic (health-chart--image-format) 'text)))
             (pick (seq-find (lambda (b)
                               (and (assq b health-chart-backends)
                                    (health-chart--supports-p b kind want)
                                    (health-chart-backend-available-p b)))
                             order)))
        (cond
         (pick (list pick want (format "auto: %s; %s is the first of %s installed with a %s template"
                                       (if graphic "images can be shown" "terminal")
                                       pick order kind)))
         ((and (or (null format) (memq want '(text svg)))
               (health-chart--supports-p 'text kind 'text))
          (list 'text 'text (format "auto: no backend of %s is installed with a %s template; native text"
                                    order kind)))
         (t (signal 'health-chart-backend-error
                    (list (format "no installed backend writes %s %s; install one of %s (see `health-chart-doctor')"
                                  kind want order)
                          :code "no_backend" :kind kind :format want))))))))


;; -----------------------------------------------------------------------
;; Render and write
;; -----------------------------------------------------------------------

(defun health-chart--render-props (props)
  "PROPS without the render-only ones."
  (health-chart--plist-drop props :backend :format :scale))

(defun health-chart-render-explain (kind data &rest props)
  "The plan `health-chart-render' follows for KIND, DATA and PROPS.  Pure.
A plist: :backend :format :reason, and for template backends :template,
:program (the filled template plus terminal lines) and :steps (each an
:argv run with the previous output on stdin; the first gets :program),
with :fallback steps when PNG/PDF may need rsvg-convert."
  (pcase-let* ((`(,backend ,format ,reason)
                (health-chart-select-backend kind (plist-get props :backend) (plist-get props :format)))
               (plist (health-chart--backend backend)))
    (append (list :backend backend :format format :reason reason)
            (if (plist-get plist :native)
                (list :renderer (plist-get (health-chart--kind kind) (plist-get plist :native)))
              (let ((spec (append (apply #'health-chart-spec kind data (health-chart--render-props props))
                                  (list :scale (or (plist-get props :scale) health-chart-image-scale)))))
                (health-chart--plist-drop (funcall (plist-get plist :explain) spec format
                                                   (plist-get props :out))
                                          :backend :format))))))

(defun health-chart--render-native (backend kind data props)
  "Native BACKEND (text or svg) drawing KIND of DATA under PROPS."
  (let ((data (health-chart-normalize kind data)))
    (apply #'health-chart-validate kind data (health-chart--plist-drop props :format :scale :out))
    (apply (plist-get (health-chart--kind kind) (plist-get (health-chart--backend backend) :native))
           data
           (if (eq backend 'svg)
               (append (when (plist-get props :pixel-width) (list :width (plist-get props :pixel-width)))
                       (when (plist-get props :pixel-height) (list :height (plist-get props :pixel-height)))
                       (health-chart--plist-drop props :backend :format :scale :out :width :height
                                                 :pixel-width :pixel-height))
             (health-chart--plist-drop props :backend :format :scale :out :pixel-width :pixel-height)))))

(defun health-chart-render-string (kind data &rest props)
  "Render KIND of DATA under PROPS; return (BACKEND FORMAT OUTPUT).
OUTPUT is a string (bytes for png and pdf), or nil when there is
nothing to draw.  PROPS' :out writes the output to that file instead,
OUTPUT then being the file name.  When the backend is `auto' and the
chosen one's tools cannot write the format (Vega-Lite PNG with neither
a working vl2png nor rsvg-convert, as on Windows), the next installed
backend of `health-chart-graphic-backends' draws it."
  (condition-case err
      (apply #'health-chart--render-string kind data props)
    (health-chart-backend-error
     (let ((next (and (equal (plist-get (cddr err) :code) "backend_missing")
                      (health-chart--next-backend kind props))))
       (if next
           (apply #'health-chart-render-string kind data :backend next props)
         (signal (car err) (cdr err)))))))

(defun health-chart--next-backend (kind props)
  "The installed backend after the one `auto' chose for KIND under PROPS.
Nil unless PROPS leave the backend to `auto' and set a :format."
  (let ((format (plist-get props :format)))
    (when (and format (eq (or (plist-get props :backend) health-chart-backend) 'auto))
      (let ((tried (car (health-chart-select-backend kind 'auto format))))
        (seq-find (lambda (b)
                    (and (assq b health-chart-backends)
                         (health-chart--supports-p b kind format)
                         (health-chart-backend-available-p b)))
                  (cdr (memq tried health-chart-graphic-backends)))))))

(defun health-chart--render-string (kind data &rest props)
  "`health-chart-render-string' of KIND, DATA and PROPS without the fallback."
  (pcase-let* ((`(,backend ,format ,_reason)
                (health-chart-select-backend kind (plist-get props :backend) (plist-get props :format)))
               (plist (health-chart--backend backend))
               (out (plist-get props :out)))
    (list backend format
          (if (plist-get plist :native)
              (let ((s (health-chart--render-native backend kind data props)))
                (if (and out s) (progn (health-chart--write-bytes (substring-no-properties s) out) out) s))
            (let ((spec (append (apply #'health-chart-spec kind data (health-chart--render-props
                                                                     (health-chart--plist-drop props :out)))
                                (list :scale (or (plist-get props :scale) health-chart-image-scale)))))
              (when (> (length (plist-get spec :rows)) 0)
                (funcall (plist-get plist :render) spec format out)))))))

;;;###autoload
(defun health-chart-render (kind data &rest props)
  "Render DATA as a KIND chart with the selected backend.
With no :format, return an image object where the frame shows images
\(SVG, or PNG when this Emacs lacks SVG) and a text string in a
terminal.  With :format (svg png pdf text vega-lite) return that output
as a string -- raw bytes for png and pdf.  PROPS also take :backend
\(auto vega-lite gnuplot text svg), :scale (PNG pixel ratio) and every
`health-chart-spec' prop.  KIND may be any kind with a template, also
one known only by a file in `health-chart-template-directories'.
Returns nil when there is nothing to draw."
  (if (plist-get props :format)
      (nth 2 (apply #'health-chart-render-string kind data props))
    (let* ((graphic (health-chart--graphic-context-p))
           (format (and graphic (health-chart--image-format))))
      (pcase-let ((`(,_backend ,fmt ,out)
                   (apply #'health-chart-render-string kind data
                          (if format
                              (condition-case nil
                                  (progn (health-chart-select-backend kind (plist-get props :backend) format)
                                         (append (list :format format) props))
                                (health-chart-backend-error props))
                            props))))
        (cond ((null out) nil)
              ((memq fmt '(svg png)) (create-image out fmt t :ascent 'center))
              (t out))))))

(defun health-chart-format-of-file (file)
  "The output format FILE's extension names, or signal."
  (or (car (seq-find (lambda (f) (string-suffix-p (cdr f) (downcase file) t))
                     (append '((vega-lite . ".vl.json") (vega-lite . ".json"))
                             health-chart-formats)))
      (signal 'health-chart-backend-error
              (list (format "cannot tell a format from %s; end it in .svg, .png, .pdf, .txt or .vl.json"
                            (file-name-nondirectory file))
                    :code "unknown_format" :file file))))

;;;###autoload
(defun health-chart-write (kind data file &rest props)
  "Write DATA as a KIND chart to FILE; return FILE.
The format comes from FILE's extension (.svg .png .pdf .txt .vl.json);
PROPS as in `health-chart-render'.  Signals when nothing can be drawn."
  (let* ((file (expand-file-name file))
         (format (health-chart-format-of-file file)))
    (or (nth 2 (apply #'health-chart-render-string kind data
                      (append (list :format format :out file) props)))
        (signal 'health-chart-invalid-data
                (list (format "nothing to draw for %s; check :person and :marker" kind)
                      :code "empty_chart")))))

;; -----------------------------------------------------------------------
;; Health
;; -----------------------------------------------------------------------

(defun health-chart-render-doctor-checks ()
  "Doctor rows: each backend's tools, and every template fills its kind's example."
  (append
   (cl-loop for (name . plist) in health-chart-backends
            unless (plist-get plist :native)
            collect (if (health-chart-backend-available-p name)
                        (list :name (format "backend %s" name) :status 'pass
                              :detail (format "installed; formats %s"
                                              (mapconcat #'symbol-name (plist-get plist :formats) " ")))
                      (list :name (format "backend %s" name) :status 'skip
                            :detail "not installed; charts use the next backend"
                            :remediation (plist-get plist :install))))
   (list (if (health-chart--rsvg-available-p)
             (list :name "rsvg-convert" :status 'pass
                   :detail "PNG/PDF from SVG when node-canvas is missing")
           (list :name "rsvg-convert" :status 'skip
                 :detail "not installed; vega-lite PNG/PDF then needs node-canvas (vl2png), SVG works without it"
                 :remediation "apt install librsvg2-bin, brew install librsvg, or choco install rsvg-convert")))
   (mapcar
    (lambda (tpl)
      (let* ((kind (plist-get tpl :kind))
             (problem
              (condition-case err
                  (let* ((entry (health-chart--kind kind))
                         (example (plist-get (alist-get (plist-get entry :shape) health-chart-shapes)
                                             :example))
                         (spec (health-chart-spec kind example))
                         (plan (funcall (plist-get (health-chart--backend (plist-get tpl :backend)) :explain)
                                        spec (if (eq (plist-get tpl :backend) 'vega-lite) 'vega-lite 'svg))))
                    (when (eq (plist-get tpl :backend) 'vega-lite)
                      (ignore (json-parse-string (plist-get plan :program))))
                    nil)
                (error (error-message-string err)))))
        (list :name (format "template %s/%s" (plist-get tpl :backend) kind)
              :status (if problem 'fail 'pass)
              :detail (or problem (format "fills from the %s example (%s)" kind
                                          (abbreviate-file-name (plist-get tpl :path))))
              :remediation (when problem "fix the template's placeholders (docs/chartspec.md)"))))
    (health-chart-templates))))

(provide 'health-chart-render)
;;; health-chart-render.el ends here
