;;; health-chart-plot.el --- One entry point for every health chart kind -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; `health-chart-plot' KIND DATA &rest PROPS returns a chart as a string
;; (propertized unicode text, or an SVG document); `-plot-insert' puts it
;; at point and `-plot-view' shows it in a `health-chart-plot-mode'
;; buffer.  KIND is a key of `health-chart-kinds'; its :shape names an
;; entry of `health-chart-shapes', which normalizes and validates DATA.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)
(require 'health-chart-source)
(require 'health-chart-indicator)
(require 'health-chart-model)
(require 'health-chart-text)
(require 'health-chart-svg)
(require 'health-chart-kind)
(require 'health-chart-render)

(defcustom health-chart-empty-text "no data"
  "Text shown in a buffer when a chart has nothing to draw."
  :type 'string
  :group 'health-charts)

;; -----------------------------------------------------------------------
;; Backend
;; -----------------------------------------------------------------------

(defun health-chart--backend-decision (backend &optional kind format)
  "(BACKEND FORMAT REASON) for drawing KIND (default timeseries) with BACKEND.
BACKEND nil means `health-chart-backend'; FORMAT nil the natural one.
See `health-chart-select-backend'."
  (health-chart-select-backend (or kind 'timeseries) backend format))

(defun health-chart-resolve-backend (backend &optional kind)
  "Concrete backend name for BACKEND (nil = the default) drawing KIND."
  (car (health-chart--backend-decision backend kind)))

(defun health-chart--renderer-args (backend props)
  "The keyword args the BACKEND renderer receives for caller PROPS.
Native renderers get keyword args; template backends get the spec props."
  (if (eq backend 'svg)
      (append (when (plist-get props :pixel-width) (list :width (plist-get props :pixel-width)))
              (when (plist-get props :pixel-height) (list :height (plist-get props :pixel-height)))
              (health-chart--plist-drop props :backend :format :width :height :pixel-width :pixel-height))
    (health-chart--plist-drop props :backend :format :pixel-width :pixel-height)))

;; -----------------------------------------------------------------------
;; Explain: the pure plan
;; -----------------------------------------------------------------------

(defun health-chart--data-summary (kind data)
  "Counts describing normalized DATA for KIND, for explain and provenance."
  (pcase (plist-get (health-chart--kind kind) :shape)
    ('series
     (append (list :points (length data))
             (when data (list :min (apply #'min data) :max (apply #'max data)))))
    ('indicators
     (let ((dates (health-chart-dates data)))
       (list :points (length data)
             :indicators (health-chart--vec (health-chart-distinct :id data))
             :cohorts (health-chart--vec (health-chart-distinct :cohort data))
             :persons (health-chart--vec (health-chart-persons data))
             :from (car dates) :to (car (last dates))
             :out-of-range (seq-count (lambda (v) (memq (health-chart-indicator-status v) '(low high)))
                                      data))))
    (_
     (let ((dates (health-chart-dates data)))
      (list :points (length data)
            :markers (health-chart--vec (health-chart-markers data))
            :persons (health-chart--vec (health-chart-persons data))
            :from (car dates) :to (car (last dates))
            :out-of-range (seq-count #'health-chart-out-of-range-p data))))))

;;;###autoload
(defun health-chart-explain (kind data &rest props)
  "Return the plan `health-chart-plot' would follow for KIND, DATA, PROPS.
Nothing is rendered or run.
A plist: :kind :shape :valid (t, or the error message) :backend
:format :backend-reason :renderer :args; for a template backend also
:template (the file), :program (the generated Vega-Lite or gnuplot
source) and :steps (each step's exact :argv, the first reading
:program on stdin; :fallback when PNG/PDF may need rsvg-convert); and
when valid a data summary (:points :markers :persons :from :to
:out-of-range).  Pure: never signals for bad DATA."
  (let* ((entry (health-chart--kind kind))
         (decision (condition-case err
                       (health-chart--backend-decision (plist-get props :backend) kind
                                                       (plist-get props :format))
                     (health-chart-error (list nil nil (cadr err)))))
         (backend (car decision))
         (native (and backend (plist-get (health-chart--backend backend) :native)))
         (valid (condition-case err (apply #'health-chart-validate kind data props)
                  (error (error-message-string err))))
         (plan (and backend (not native) (eq valid t)
                    (condition-case err
                        (apply #'health-chart-render-explain kind data
                               :backend backend :format (cadr decision) props)
                      (health-chart-error (list :plan-error (cadr err)))))))
    (append
     (list :kind kind :shape (plist-get entry :shape) :valid valid
           :backend backend :format (cadr decision) :backend-reason (nth 2 decision)
           :renderer (if native (plist-get entry native) (plist-get plan :template))
           :args (health-chart--renderer-args backend props))
     (when plan
       (list :template (plist-get plan :template) :program (plist-get plan :program)
             :steps (plist-get plan :steps) :fallback (plist-get plan :fallback)
             :plan-error (plist-get plan :plan-error)))
     (when (eq valid t)
       (health-chart--data-summary kind (health-chart-normalize kind data))))))

;; -----------------------------------------------------------------------
;; Render
;; -----------------------------------------------------------------------

(defun health-chart--svg-provenance (svg kind data props)
  "SVG with a <title>/<desc> naming KIND, DATA's extent and PROPS' :title."
  (let* ((summary (health-chart--data-summary kind data))
         (title (replace-regexp-in-string
                 "[[:cntrl:]]" "" (format "%s" (or (plist-get props :title) (format "%s chart" kind))) t t))
         (desc (format "health-chart %s: %d %s%s" kind (plist-get summary :points)
                       (pcase (plist-get (health-chart--kind kind) :shape)
                         ('series "points") ('indicators "indicator values") (_ "measurements"))
                       (if (plist-get summary :from)
                           (format ", %s to %s" (plist-get summary :from) (plist-get summary :to))
                         "")))
         (end (and (string-prefix-p "<svg" svg) (string-search ">" svg))))
    (if (not end) svg
      (concat (substring svg 0 (1+ end))
              "<title>" (xml-escape-string title) "</title>"
              "<desc>" (xml-escape-string desc) "</desc>"
              (substring svg (1+ end))))))

;;;###autoload
(defun health-chart-plot (kind data &rest props)
  "Render DATA as a KIND chart and return it as a string.
KIND is a key of `health-chart-kinds' (`health-chart-list-kinds') or a
kind with a template (`health-chart-templates'); DATA must fit its shape
\(`health-chart-validate').  PROPS: :backend (auto, vega-lite, gnuplot,
text or svg; see `health-chart-backend'), :format (svg, png, pdf, text,
vega-lite; default svg where images show, else text), :width/:height
\(text columns/rows), :pixel-width/:pixel-height (images), :title,
:person, :marker, :ref and :optimal (show the bands), and per-kind props
\(:from/:to for delta, :columns for panel).  Returns nil when there is
nothing to draw."
  (let ((data (health-chart-normalize kind data)))
    (apply #'health-chart-validate kind data props)
    (pcase-let ((`(,_backend ,format ,out)
                 (apply #'health-chart-render-string kind data props)))
      (if (and out (eq format 'svg))
          (health-chart--svg-provenance out kind data props)
        out))))

;;;###autoload
(defun health-chart-plot-spec (spec)
  "Render chart SPEC, a plist (:kind KIND :data DATA . PROPS).
The same plain-data form the batch CLI reads as JSON."
  (apply #'health-chart-plot (plist-get spec :kind) (plist-get spec :data)
         (health-chart--plist-drop spec :kind :data)))

;;;###autoload
(defun health-chart-list-kinds ()
  "Every chart kind as (KIND :shape SHAPE :doc DOC), registry order."
  (mapcar (lambda (e) (list (car e) :shape (plist-get (cdr e) :shape)
                            :doc (plist-get (cdr e) :doc)))
          health-chart-kinds))

;;;###autoload
(defun health-chart-describe-kind (kind)
  "KIND's description: doc, shape doc, example data, renderers, props."
  (let* ((entry (health-chart--kind kind))
         (shape (health-chart--shape kind)))
    (list :kind kind :doc (plist-get entry :doc)
          :shape (plist-get entry :shape) :shape-doc (plist-get shape :doc)
          :example (plist-get shape :example)
          :text (plist-get entry :text) :svg (plist-get entry :svg)
          :renderers-defined (and (fboundp (plist-get entry :text))
                                  (fboundp (plist-get entry :svg)) t))))

;;;###autoload
(defun health-chart-sparkline (values &rest props)
  "One-row unicode sparkline string for VALUES (PROPS: :width :face).
Empty VALUES give \"\"."
  (or (apply #'health-chart-text-sparkline (health-chart--normalize-series values) props) ""))

;; -----------------------------------------------------------------------
;; Insert and view
;; -----------------------------------------------------------------------

(defun health-chart--insert-rendered (out format)
  "Insert rendered OUT, in FORMAT (svg, png or text), at point."
  (cond
   ((or (null out) (equal out ""))
    (insert (propertize health-chart-empty-text 'face 'health-chart-dim)))
   ((memq format '(svg png))
    (insert-image (create-image out format t :ascent 'center) "[chart]"))
   (t (insert out))))

(defun health-chart--usable-decision (kind backend)
  "(BACKEND FORMAT REASON) for KIND with BACKEND that this frame can show.
An image backend falls back to the terminal choice where images cannot
be displayed."
  (let ((d (health-chart--backend-decision backend kind)))
    (if (and (memq (cadr d) '(svg png))
             (not (and (display-images-p) (image-type-available-p (cadr d)))))
        (let ((health-chart-graphic-backends nil))
          (health-chart-select-backend kind 'auto 'text))
      d)))

(defun health-chart--usable-backend (backend &optional kind)
  "BACKEND resolved for KIND (default bullet) to one this frame can show."
  (car (health-chart--usable-decision (or kind 'bullet) backend)))

;;;###autoload
(defun health-chart-plot-insert (kind data &rest props)
  "Insert DATA as a KIND chart at point.  PROPS as in `health-chart-plot'.
Falls back to text when an image is requested but cannot be displayed."
  (pcase-let ((`(,backend ,format ,_) (health-chart--usable-decision kind (plist-get props :backend))))
    (health-chart--insert-rendered
     (apply #'health-chart-plot kind data :backend backend :format format props) format)))

(defvar-local health-chart-plot--spec nil
  "(KIND DATA PROPS) of the chart shown in this `health-chart-plot-mode' buffer.")

(defvar health-chart-plot-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "g") #'health-chart-plot-refresh)
    (define-key m (kbd "t") #'health-chart-plot-toggle-backend)
    (define-key m (kbd "r") #'health-chart-plot-toggle-ref)
    (define-key m (kbd "o") #'health-chart-plot-toggle-optimal)
    m)
  "Keymap for `health-chart-plot-mode'.")

(define-derived-mode health-chart-plot-mode special-mode "Health-Chart"
  "Major mode for a buffer showing one health chart.
\\{health-chart-plot-mode-map}"
  (setq truncate-lines t))

(defun health-chart-plot--fit-props (props)
  "PROPS with :width and :pixel-width filled in from the window if absent."
  (let* ((win (get-buffer-window (current-buffer) t))
         (cols (if win (window-body-width win) 80)))
    (append props
            (unless (plist-member props :width)
              (list :width (max 40 (min 120 (- cols 2)))))
            (unless (plist-member props :pixel-width)
              (list :pixel-width (if win (min 900 (max 400 (- (window-body-width win t) 20)))
                                   health-chart-image-width))))))

(defun health-chart-plot-refresh ()
  "Re-render this buffer's chart."
  (interactive)
  (pcase-let* ((`(,kind ,data ,props) health-chart-plot--spec)
               (`(,backend ,format ,_) (health-chart--usable-decision kind (plist-get props :backend)))
               (out (apply #'health-chart-plot kind data :backend backend :format format
                           (health-chart-plot--fit-props props)))
               (inhibit-read-only t))
    (erase-buffer)
    (health-chart--insert-rendered out format)
    (insert "\n")
    (goto-char (point-min))))

(defun health-chart-plot--toggle (key default)
  "Flip boolean prop KEY (DEFAULT when absent) of this chart and redraw."
  (let* ((props (nth 2 health-chart-plot--spec))
         (now (if (plist-member props key) (plist-get props key) default)))
    (setf (nth 2 health-chart-plot--spec) (plist-put (copy-sequence props) key (not now)))
    (health-chart-plot-refresh)
    (not now)))

(defun health-chart--toggled-backend (kind backend)
  "The backend to switch to from BACKEND for KIND: text <-> the image choice."
  (if (eq (cadr (health-chart--backend-decision backend kind)) 'text)
      (let ((b (car (ignore-errors (health-chart-select-backend kind 'auto 'svg)))))
        ;; no image backend installed: the native SVG renderer, as before
        (if (memq b '(nil text)) 'svg b))
    'text))

(defun health-chart-plot-toggle-backend ()
  "Flip this buffer's chart between text and an image backend."
  (interactive)
  (let* ((kind (car health-chart-plot--spec))
         (props (nth 2 health-chart-plot--spec)))
    (setf (nth 2 health-chart-plot--spec)
          (plist-put (copy-sequence props) :backend
                     (health-chart--toggled-backend kind (plist-get props :backend))))
    (health-chart-plot-refresh)))

(defun health-chart-plot-toggle-ref ()
  "Show or hide the reference-range band."
  (interactive)
  (message "Reference band %s"
           (if (health-chart-plot--toggle :ref health-chart-show-ref-range) "on" "off")))

(defun health-chart-plot-toggle-optimal ()
  "Show or hide the optimal-range band."
  (interactive)
  (message "Optimal band %s"
           (if (health-chart-plot--toggle :optimal health-chart-show-optimal-range) "on" "off")))

;;;###autoload
(defun health-chart-plot-view (kind data &rest props)
  "Show DATA as a KIND chart in a `health-chart-plot-mode' buffer; return it.
PROPS as in `health-chart-plot', plus :buffer (name, default
\"*health-chart*\")."
  (apply #'health-chart-validate kind data props)
  (let ((buf (get-buffer-create (or (plist-get props :buffer) "*health-chart*"))))
    (with-current-buffer buf
      (health-chart-plot-mode)
      (setq health-chart-plot--spec (list kind data (health-chart--plist-drop props :buffer))))
    (unless noninteractive (pop-to-buffer buf))
    (with-current-buffer buf (health-chart-plot-refresh))
    buf))

;;;###autoload
(defun health-chart-demo ()
  "Show every health-chart kind over built-in synthetic data."
  (interactive)
  (let ((ms (health-chart--example-measurements))
        (buf (get-buffer-create "*health-chart demo*")))
    (with-current-buffer buf
      (health-chart-plot-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (dolist (spec '((timeseries :person "alex" :marker "ldl_c")
                        (compare :marker "vitamin_d")
                        (table :person "alex") (bullet :person "alex")
                        (heatmap :person "alex") (delta :person "alex")
                        (panel :person "alex" :marker ("ldl_c" "apob" "glucose" "crp"))))
          (apply #'health-chart-plot-insert (car spec) ms (cdr spec))
          (insert "\n\n"))
        (dolist (kind '(scorecard cohort staleness))
          (health-chart-plot-insert kind (health-chart--example-indicator-values))
          (insert "\n\n"))
        (goto-char (point-min))))
    (unless noninteractive (pop-to-buffer buf))
    buf))

;; -----------------------------------------------------------------------
;; Health
;; -----------------------------------------------------------------------

(defun health-chart-plot-doctor-checks ()
  "Doctor rows: every kind renders its example in both backends; SVG support."
  (append
   (mapcar
    (lambda (entry)
      (let* ((kind (car entry))
             (example (plist-get (health-chart--shape kind) :example))
             (problem (condition-case err
                          (progn
                            (unless (stringp (health-chart-plot kind example :backend 'text))
                              (error "Text renderer returned nothing"))
                            (unless (string-prefix-p "<svg" (health-chart-plot kind example :backend 'svg))
                              (error "SVG renderer returned no document"))
                            nil)
                        (error (error-message-string err)))))
        (list :name (format "kind %s" kind) :status (if problem 'fail 'pass)
              :detail (or problem "renders its example as text and SVG")
              :remediation (when problem "fix the renderer or its registry entry"))))
    health-chart-kinds)
   (list (if (image-type-available-p 'svg)
             (list :name "svg-display" :status 'pass :detail "this Emacs displays SVG")
           (list :name "svg-display" :status 'skip
                 :detail "this Emacs cannot display SVG; charts fall back to text"
                 :remediation "build Emacs with librsvg for inline SVG")))))

(provide 'health-chart-plot)
;;; health-chart-plot.el ends here
