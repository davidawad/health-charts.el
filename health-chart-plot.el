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
(require 'health-chart-model)
(require 'health-chart-text)
(require 'health-chart-svg)

(defcustom health-chart-backend 'auto
  "Rendering backend: `text', `svg', or `auto'.
`auto' uses SVG when the selected frame can display SVG images, else
unicode text."
  :type '(choice (const auto) (const text) (const svg))
  :group 'health-charts)

(defcustom health-chart-empty-text "no data"
  "Text shown in a buffer when a chart has nothing to draw."
  :type 'string
  :group 'health-charts)

;; -----------------------------------------------------------------------
;; Errors: (MESSAGE :code CODE ...), the message naming the fix.
;; -----------------------------------------------------------------------

(define-error 'health-chart-unknown-kind
  "health-chart: unknown chart kind" 'health-chart-error)
(define-error 'health-chart-invalid-data
  "health-chart: invalid chart data" 'health-chart-error)

(defun health-chart--invalid (index fmt &rest args)
  "Signal `health-chart-invalid-data' at element INDEX; FMT/ARGS the reason."
  (signal 'health-chart-invalid-data
          (list (format "element %d: %s" index (apply #'format fmt args))
                :code "invalid_data" :index index)))

;; -----------------------------------------------------------------------
;; Synthetic example data -- two made-up people, nine markers, six draws.
;; -----------------------------------------------------------------------

(defconst health-chart--example-dates
  '("2024-03-04" "2024-06-03" "2024-09-02" "2024-12-02" "2025-03-03" "2025-06-02")
  "Draw dates of the example data.")

(defconst health-chart--example-markers
  ;; marker unit ref-low ref-high opt-low opt-high  alex values  sam values
  '(("ldl_c" "mg/dL" 0 100 nil 70 (131 124 108 96 112 88) (92 95 88 84 79 74))
    ("hdl_c" "mg/dL" 40 nil 60 nil (52 55 58 57 54 61) (64 66 63 67 70 68))
    ("triglycerides" "mg/dL" 0 150 nil 100 (162 140 121 118 134 104) (88 92 81 79 85 76))
    ("apob" "mg/dL" 0 90 nil 80 (104 99 91 86 93 84) (71 73 69 66 64 62))
    ("glucose" "mg/dL" 70 99 72 90 (97 101 94 92 99 93) (86 84 88 85 83 87))
    ("hba1c" "%" nil 5.7 nil 5.3 (5.6 5.8 5.5 5.4 5.6 5.3) (5.1 5.0 5.2 5.1 5.0 5.1))
    ("vitamin_d" "ng/mL" 30 100 40 60 (24 31 38 45 36 48) (52 49 55 58 51 54))
    ("tsh" "mIU/L" 0.4 4.0 0.5 2.5 (1.9 2.2 2.0 2.6 2.4 2.1) (1.4 1.6 1.5 1.3 1.7 1.5))
    ("crp" "mg/L" nil 3.0 nil 1.0 (2.4 3.6 1.8 1.2 2.1 3.4) (0.6 0.5 0.9 0.4 0.7 0.5)))
  "Example markers: (MARKER UNIT REF-LOW REF-HIGH OPT-LOW OPT-HIGH ALEX SAM).")

(defun health-chart--example-measurements (&optional persons)
  "Synthetic canonical measurements for PERSONS (default both)."
  (let ((persons (or persons '("alex" "sam"))))
    (cl-loop
     for person in persons
     append (cl-loop
             for (marker unit rl rh ol oh alex sam) in health-chart--example-markers
             append (cl-loop for date in health-chart--example-dates
                             for v in (if (equal person "alex") alex sam)
                             collect (let ((m (list :person person :marker marker :value v
                                                    :unit unit :date date :ref-low rl
                                                    :ref-high rh :opt-low ol :opt-high oh)))
                                       (health-chart-source-normalize
                                        (plist-put m :flag (let ((s (health-chart-status m)))
                                                             (if (memq s '(low high)) s 'normal))))))))))

;; -----------------------------------------------------------------------
;; Shapes and kinds -- registries, so the whole surface is enumerable.
;; -----------------------------------------------------------------------

(defun health-chart--validate-measurements (data)
  "Signal unless DATA (already normalized) is a list of valid measurements."
  (unless (listp data)
    (signal 'health-chart-invalid-data
            (list (format "measurements must be a list, got %S" data) :code "invalid_data")))
  (cl-loop
   for m in data for i from 0
   do (let ((marker (plist-get m :marker)) (date (plist-get m :date)))
        (unless (and (stringp marker) (not (string-empty-p marker)))
          (health-chart--invalid i "needs a non-empty \"marker\", got %S" marker))
        (unless (health-chart-date-p date)
          (health-chart--invalid i "needs \"date\" as YYYY-MM-DD, got %S" date))
        (unless (numberp (plist-get m :value))
          (health-chart--invalid i "needs a numeric \"value\", got %S" (plist-get m :value)))
        (dolist (key '(:ref-low :ref-high :opt-low :opt-high))
          (let ((v (plist-get m key)))
            (unless (or (null v) (numberp v))
              (health-chart--invalid i "%s must be a number or null, got %S" key v))))
        (dolist (pair '((:ref-low . :ref-high) (:opt-low . :opt-high)))
          (let ((lo (plist-get m (car pair))) (hi (plist-get m (cdr pair))))
            (when (and lo hi (> lo hi))
              (health-chart--invalid i "%s %s exceeds %s %s (swap them)"
                                     (car pair) lo (cdr pair) hi)))))))

(defun health-chart--normalize-series (data)
  "DATA as a list of numbers, oldest first.
DATA is numbers in order, (DATE . VALUE) or (DATE VALUE) pairs, or the
measurements of one marker; pairs and measurements are sorted by date."
  (let ((items (append data nil)))
    (cond
     ((cl-every #'numberp items) items)
     ((cl-every (lambda (p) (and (consp p) (stringp (car p)))) items)
      (mapcar (lambda (p) (if (consp (cdr p)) (cadr p) (cdr p)))
              (seq-sort-by #'car #'string< items)))
     ((cl-every #'consp items)
      (let ((ms (health-chart-source-normalize-list items)))
        (when (cdr (health-chart-markers ms))
          (signal 'health-chart-invalid-data
                  (list (format "a sparkline shows one marker, got %s; filter with `health-chart-filter'"
                                (string-join (health-chart-markers ms) ", "))
                        :code "invalid_data")))
        (mapcar (lambda (m) (plist-get m :value)) (health-chart-sort-by-date ms))))
     (t items))))

(defun health-chart--validate-series (data)
  "Signal unless DATA (already normalized) is a list of numbers."
  (cl-loop for v in data for i from 0
           unless (numberp v)
           do (health-chart--invalid i "expected a number, got %S" v)))

(defvar health-chart-shapes
  `((measurements
     :doc "biomarker/v1 measurements: plists (:marker :date :value [:person :unit
:ref-low :ref-high :opt-low :opt-high :flag :category]), alists or JSON
objects with the same members (snake_case accepted), or a biomarker/v1
envelope {\"schema\":\"biomarker/v1\",\"measurements\":[...]}.  Any order."
     :example ,(health-chart--example-measurements)
     :normalize health-chart-source-normalize-list
     :validator health-chart--validate-measurements)
    (series
     :doc "Numbers oldest first, or (DATE . VALUE) pairs, or measurements."
     :example (131 124 108 96 112 88)
     :normalize health-chart--normalize-series
     :validator health-chart--validate-series))
  "Data shapes: (SHAPE :doc :example :normalize FN :validator FN).
:normalize turns any accepted input into the canonical form (and must be
idempotent); :validator signals `health-chart-invalid-data' with :index.")

(defvar health-chart-kinds
  '((timeseries :shape measurements :text health-chart-text-timeseries
                :svg health-chart-svg-timeseries :check health-chart--check-one-marker
                :doc "One marker over time with reference and optimal bands shaded.")
    (panel :shape measurements :text health-chart-text-panel :svg health-chart-svg-panel
           :doc "Small multiples: a compact time series per marker (a panel dashboard).")
    (table :shape measurements :text health-chart-text-table :svg health-chart-svg-table
           :doc "Sparkline table: marker | latest | trend | flag | reference.")
    (bullet :shape measurements :text health-chart-text-bullet :svg health-chart-svg-bullet
            :doc "Range bars: where each marker's latest value sits in its ranges.")
    (heatmap :shape measurements :text health-chart-text-heatmap :svg health-chart-svg-heatmap
             :doc "Markers by draw dates, each cell the draw's status (out-of-range map).")
    (compare :shape measurements :text health-chart-text-compare :svg health-chart-svg-compare
             :check health-chart--check-one-marker
             :doc "One marker over time for several people, overlaid.")
    (delta :shape measurements :text health-chart-text-delta :svg health-chart-svg-delta
           :check health-chart--check-delta
           :doc "Percent change per marker between two draws, toward or away from target.")
    (sparkline :shape series :text health-chart-text-sparkline :svg health-chart-svg-sparkline
               :doc "One-row sparkline of plain numbers, for tables and mode lines."))
  "Chart kinds: (KIND :shape SHAPE :text FN :svg FN :doc STRING [:check FN]).
Renderers are called as (FN DATA &rest PROPS) with normalized DATA and
return a string, or nil when there is nothing to draw.  :check (DATA
PROPS) validates props that select from DATA.")

(defun health-chart--check-one-marker (data props)
  "Signal unless PROPS' :marker, when given, occurs in DATA."
  (when-let* ((marker (plist-get props :marker)))
    (unless (member marker (health-chart-markers data))
      (signal 'health-chart-invalid-data
              (list (format "no measurements for marker %S; markers present: %s" marker
                            (string-join (health-chart-markers data) ", "))
                    :code "unknown_marker" :marker marker)))))

(defun health-chart--check-delta (data props)
  "Signal unless PROPS' :from and :to, when given, are draw dates in DATA."
  (dolist (key '(:from :to))
    (when-let* ((d (plist-get props key)))
      (unless (member d (health-chart-dates data))
        (signal 'health-chart-invalid-data
                (list (format "%s %S is not a draw date; dates present: %s" key d
                              (string-join (health-chart-dates data) ", "))
                      :code "unknown_date" :date d))))))

(defun health-chart-register-kind (kind &rest spec)
  "Register (or replace) chart KIND with SPEC (:shape :text :svg :doc [:check]).
:shape must name an entry of `health-chart-shapes'."
  (unless (assq (plist-get spec :shape) health-chart-shapes)
    (signal 'health-chart-error
            (list (format "unknown shape %S; known: %S" (plist-get spec :shape)
                          (mapcar #'car health-chart-shapes))
                  :code "unknown_shape")))
  (setf (alist-get kind health-chart-kinds) spec)
  kind)

(defun health-chart--kind (kind)
  "KIND's registry plist, or signal `health-chart-unknown-kind'."
  (or (alist-get kind health-chart-kinds)
      (signal 'health-chart-unknown-kind
              (list (format "%S is not a chart kind; use one of %s (see `health-chart-list-kinds')"
                            kind (mapconcat #'symbol-name (mapcar #'car health-chart-kinds) ", "))
                    :code "unknown_kind" :kind kind))))

(defun health-chart--shape (kind)
  "The shape plist of KIND."
  (alist-get (plist-get (health-chart--kind kind) :shape) health-chart-shapes))

(defun health-chart-normalize (kind data)
  "DATA in KIND's canonical form (see `health-chart-shapes')."
  (if-let* ((fn (plist-get (health-chart--shape kind) :normalize)))
      (condition-case err (funcall fn data)
        (health-chart-source-error (signal (car err) (cdr err)))
        (health-chart-error
         (signal 'health-chart-invalid-data (list (cadr err) :code "invalid_data")))
        (wrong-type-argument
         (signal 'health-chart-invalid-data
                 (list (format "cannot read data as %s: %S" (plist-get (health-chart--kind kind) :shape)
                               err)
                       :code "invalid_data"))))
    data))

;;;###autoload
(defun health-chart-validate (kind data &rest props)
  "Return t when DATA fits KIND's shape and PROPS, else signal a typed error.
`health-chart-invalid-data' carries the offending element's :index.
Empty DATA is valid: it renders as nothing."
  (let* ((entry (health-chart--kind kind))
         (data (health-chart-normalize kind data))
         (backend (plist-get props :backend)))
    (unless (memq backend '(nil auto text svg))
      (signal 'health-chart-invalid-data
              (list (format ":backend must be text, svg or auto, got %S" backend)
                    :code "invalid_prop")))
    (when data
      (funcall (plist-get (health-chart--shape kind) :validator) data)
      (when-let* ((check (plist-get entry :check)))
        (funcall check data props)))
    t))

;; -----------------------------------------------------------------------
;; Backend
;; -----------------------------------------------------------------------

(defun health-chart--plist-drop (plist &rest keys)
  "PLIST without KEYS."
  (cl-loop for (k v) on plist by #'cddr
           unless (memq k keys) append (list k v)))

(defun health-chart--backend-decision (backend)
  "(CONCRETE-BACKEND . REASON) for BACKEND (nil = `health-chart-backend')."
  (pcase (or backend health-chart-backend)
    ('svg '(svg . "requested svg"))
    ('text '(text . "requested text"))
    (_ (if (and (display-images-p) (image-type-available-p 'svg))
           '(svg . "auto: this frame displays SVG images")
         '(text . "auto: this frame cannot display SVG images")))))

(defun health-chart-resolve-backend (backend)
  "Concrete backend (`text' or `svg') for BACKEND (nil = the default)."
  (car (health-chart--backend-decision backend)))

(defun health-chart--renderer-args (backend props)
  "The keyword args the BACKEND renderer receives for caller PROPS."
  (if (eq backend 'svg)
      (append (when (plist-get props :pixel-width) (list :width (plist-get props :pixel-width)))
              (when (plist-get props :pixel-height) (list :height (plist-get props :pixel-height)))
              (health-chart--plist-drop props :backend :width :height :pixel-width :pixel-height))
    (health-chart--plist-drop props :backend :pixel-width :pixel-height)))

;; -----------------------------------------------------------------------
;; Explain: the pure plan
;; -----------------------------------------------------------------------

(defun health-chart--data-summary (kind data)
  "Counts describing normalized DATA for KIND, for explain and provenance."
  (if (eq (plist-get (health-chart--kind kind) :shape) 'series)
      (append (list :points (length data))
              (when data (list :min (apply #'min data) :max (apply #'max data))))
    (let ((dates (health-chart-dates data)))
      (list :points (length data)
            :markers (health-chart--vec (health-chart-markers data))
            :persons (health-chart--vec (health-chart-persons data))
            :from (car dates) :to (car (last dates))
            :out-of-range (seq-count #'health-chart-out-of-range-p data)))))

;;;###autoload
(defun health-chart-explain (kind data &rest props)
  "Return the plan `health-chart-plot' would follow for KIND, DATA, PROPS.
Nothing is rendered.
A plist: :kind :shape :valid (t, or the error message) :backend
:backend-reason :renderer :args, and when valid a data summary (:points
:markers :persons :from :to :out-of-range).  Pure: never signals for
bad DATA."
  (let* ((entry (health-chart--kind kind))
         (decision (health-chart--backend-decision (plist-get props :backend)))
         (valid (condition-case err (apply #'health-chart-validate kind data props)
                  (error (error-message-string err)))))
    (append
     (list :kind kind :shape (plist-get entry :shape) :valid valid
           :backend (car decision) :backend-reason (cdr decision)
           :renderer (plist-get entry (if (eq (car decision) 'svg) :svg :text))
           :args (health-chart--renderer-args (car decision) props))
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
                       (if (eq (plist-get (health-chart--kind kind) :shape) 'series) "points" "measurements")
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
KIND is a key of `health-chart-kinds' (`health-chart-list-kinds'); DATA
must fit its shape (`health-chart-validate').  PROPS: :backend (text,
svg or auto), :width/:height (text columns/rows), :pixel-width
/:pixel-height (SVG), :title, :person, :marker, :ref and :optimal (show
the bands), and per-kind props (:from/:to for delta, :columns for
panel).  Returns nil when there is nothing to draw."
  (let* ((entry (health-chart--kind kind))
         (data (health-chart-normalize kind data))
         (backend (health-chart-resolve-backend (plist-get props :backend))))
    (apply #'health-chart-validate kind data props)
    (let ((out (apply (plist-get entry (if (eq backend 'svg) :svg :text)) data
                      (health-chart--renderer-args backend props))))
      (if (and out (eq backend 'svg))
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

(defun health-chart--insert-rendered (out backend)
  "Insert rendered OUT for BACKEND at point."
  (cond
   ((or (null out) (equal out ""))
    (insert (propertize health-chart-empty-text 'face 'health-chart-dim)))
   ((eq backend 'svg) (insert-image (create-image out 'svg t :ascent 'center) "[chart]"))
   (t (insert out))))

(defun health-chart--usable-backend (backend)
  "BACKEND resolved, falling back to text when SVG cannot be displayed."
  (let ((b (health-chart-resolve-backend backend)))
    (if (and (eq b 'svg) (not (image-type-available-p 'svg))) 'text b)))

;;;###autoload
(defun health-chart-plot-insert (kind data &rest props)
  "Insert DATA as a KIND chart at point.  PROPS as in `health-chart-plot'.
Falls back to text when SVG is requested but cannot be displayed."
  (let ((backend (health-chart--usable-backend (plist-get props :backend))))
    (health-chart--insert-rendered
     (apply #'health-chart-plot kind data :backend backend props) backend)))

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
                                   health-chart-svg-width))))))

(defun health-chart-plot-refresh ()
  "Re-render this buffer's chart."
  (interactive)
  (pcase-let* ((`(,kind ,data ,props) health-chart-plot--spec)
               (backend (health-chart--usable-backend (plist-get props :backend)))
               (out (apply #'health-chart-plot kind data :backend backend
                           (health-chart-plot--fit-props props)))
               (inhibit-read-only t))
    (erase-buffer)
    (health-chart--insert-rendered out backend)
    (insert "\n")
    (goto-char (point-min))))

(defun health-chart-plot--toggle (key default)
  "Flip boolean prop KEY (DEFAULT when absent) of this chart and redraw."
  (let* ((props (nth 2 health-chart-plot--spec))
         (now (if (plist-member props key) (plist-get props key) default)))
    (setf (nth 2 health-chart-plot--spec) (plist-put (copy-sequence props) key (not now)))
    (health-chart-plot-refresh)
    (not now)))

(defun health-chart-plot-toggle-backend ()
  "Flip this buffer's chart between text and SVG."
  (interactive)
  (let* ((props (nth 2 health-chart-plot--spec))
         (now (health-chart-resolve-backend (plist-get props :backend))))
    (setf (nth 2 health-chart-plot--spec)
          (plist-put (copy-sequence props) :backend (if (eq now 'svg) 'text 'svg)))
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
