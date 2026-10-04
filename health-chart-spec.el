;;; health-chart-spec.el --- The neutral chart spec (chartspec/v1) -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A CHART SPEC (schema "chartspec/v1") is everything a backend needs to
;; draw one chart, already decided: title and subtitle, size, theme
;; colors, axes with their domains and ticks, the data rows (each with
;; its status as glyph and word), overlays (reference and optimal
;; bands, threshold lines, annotations) and legend entries.  Backends
;; only lay it out; they never judge a value or pick a marker.
;;
;; The plist form uses the JSON member names as keywords (:ref_low,
;; :status_label), arrays are vectors and null is nil, so
;;
;;   (equal spec (health-chart-spec-from-json (health-chart-spec-to-json spec)))
;;
;; holds.  docs/chartspec.md documents every member.  This file builds
;; specs from normalized data; `health-chart-spec' (health-chart-render.el)
;; is the public, normalizing entry point.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'health-chart-core)
(require 'health-chart-indicator)
(require 'health-chart-model)

(defconst health-chart-spec-schema "chartspec/v1"
  "The schema name every chart spec carries.")

(defcustom health-chart-theme 'auto
  "Color theme of image charts: `light', `dark' or `auto'.
`auto' follows the selected frame's background mode.  Override per call
with the :theme prop."
  :type '(choice (const auto) (const light) (const dark))
  :group 'health-charts)

(defcustom health-chart-colors nil
  "Per-role color overrides for image charts: alist ROLE -> \"#rrggbb\".
Roles are the members of the spec's colors object: surface, ink,
secondary, muted, grid, axis, ref_band, opt_band, optimal, normal,
suboptimal, low, high, unknown, improved, worsened, steady, on_target,
fresh, due, stale, undated."
  :type '(alist :key-type symbol :value-type string)
  :group 'health-charts)

(defcustom health-chart-image-width 720
  "Default width of image charts in CSS pixels (:pixel-width overrides)."
  :type 'natnum
  :group 'health-charts)

(defcustom health-chart-image-height 360
  "Default height of single-plot image charts in CSS pixels.
Multi-row kinds (panel, bullet, heatmap, delta, staleness) size their
height from their row count unless :pixel-height is given."
  :type 'natnum
  :group 'health-charts)

(defcustom health-chart-font-family "DejaVu Sans"
  "Font family image charts ask their backend for."
  :type 'string
  :group 'health-charts)

(defcustom health-chart-font-size 12
  "Base font size of image charts, in CSS pixels."
  :type 'natnum
  :group 'health-charts)

(defconst health-chart-spec-palettes
  '((light (surface . "#fcfcfb") (ink . "#0b0b0b") (secondary . "#52514e")
           (muted . "#898781") (grid . "#e1e0d9") (axis . "#c3c2b7")
           (ref_band . "#b8b7ad") (opt_band . "#0ca30c")
           (optimal . "#0ca30c") (normal . "#2a78d6") (suboptimal . "#e09a00")
           (low . "#d03b3b") (high . "#d03b3b") (unknown . "#898781")
           (improved . "#0ca30c") (worsened . "#d03b3b") (steady . "#898781")
           (on_target . "#2a78d6")
           (fresh . "#0ca30c") (due . "#e09a00") (stale . "#d03b3b") (undated . "#898781")
           (series "#2a78d6" "#eb6834" "#1baf7a" "#eda100"
                   "#e87ba4" "#008300" "#4a3aa7" "#e34948"))
    (dark (surface . "#1a1a19") (ink . "#ffffff") (secondary . "#c3c2b7")
          (muted . "#898781") (grid . "#2c2c2a") (axis . "#383835")
          (ref_band . "#6b6a64") (opt_band . "#0ca30c")
          (optimal . "#2bbf2b") (normal . "#3987e5") (suboptimal . "#fab219")
          (low . "#e66767") (high . "#e66767") (unknown . "#898781")
          (improved . "#2bbf2b") (worsened . "#e66767") (steady . "#898781")
          (on_target . "#3987e5")
          (fresh . "#2bbf2b") (due . "#fab219") (stale . "#e66767") (undated . "#898781")
          (series "#3987e5" "#d95926" "#199e70" "#c98500"
                  "#d55181" "#008300" "#9085e9" "#e66767")))
  "Light and dark palettes: role -> color, plus the ordered series colors.")

(defconst health-chart-spec-style
  '(:ref_band_opacity 0.28 :opt_band_opacity 0.14 :point_size 64
    :line_width 2 :grid_opacity 1)
  "Mark style every backend reads from the spec's style object.")

(defcustom health-chart-verdict-glyphs
  '((improved . "✔") (worsened . "✖") (on-target . "●") (steady . "→"))
  "Glyph for each change verdict, shown beside the verdict word."
  :type '(alist :key-type symbol :value-type string)
  :group 'health-charts)

;; -----------------------------------------------------------------------
;; Small helpers
;; -----------------------------------------------------------------------

(defun health-chart-spec--round (x &optional digits)
  "X rounded to DIGITS decimals (default 3), or nil when X is not a number."
  (when (numberp x)
    (let ((f (expt 10.0 (or digits 3))))
      (let ((r (/ (fround (* x f)) f)))
        (if (= r (ftruncate r)) (truncate r) r)))))

(defun health-chart-spec--theme (props)
  "The concrete theme name (a string) for PROPS' :theme or `health-chart-theme'."
  (let ((theme (or (plist-get props :theme) health-chart-theme)))
    (when (stringp theme) (setq theme (intern theme)))
    (symbol-name
     (if (memq theme '(light dark)) theme
       (if (and (display-graphic-p) (eq (frame-parameter nil 'background-mode) 'dark))
           'dark 'light)))))

(defun health-chart-spec--palette (theme)
  "The palette alist of THEME (a string)."
  (alist-get (intern theme) health-chart-spec-palettes))

(defun health-chart-spec--color (theme role)
  "Color of ROLE (a symbol) in THEME, honoring `health-chart-colors'."
  (or (alist-get role health-chart-colors)
      (alist-get role (health-chart-spec--palette theme))))

(defun health-chart-spec--colors (theme)
  "The colors object of a spec in THEME."
  (append
   (cl-loop for (role . c) in (health-chart-spec--palette theme)
            unless (eq role 'series)
            append (list (intern (format ":%s" role)) (health-chart-spec--color theme role)))
   (list :series (apply #'vector (or (alist-get 'series health-chart-colors)
                                     (alist-get 'series (health-chart-spec--palette theme)))))))

(defun health-chart-spec--rgb (hex)
  "HEX color \"#rrggbb\" as an integer 0xRRGGBB."
  (string-to-number (substring hex 1) 16))

(defun health-chart-spec--status-word (status)
  "The word for STATUS shown beside its glyph."
  (if (eq status 'unknown) "n/a" (symbol-name status)))

(defun health-chart-spec--legend-entry (key glyph word color)
  "A legend entry: KEY, GLYPH, WORD and COLOR; :label is glyph and word."
  (list :key key :glyph glyph :word word :label (format "%s %s" glyph word)
        :color color :rgb (health-chart-spec--rgb color)))

(defconst health-chart-spec-status-shapes
  '((optimal "circle" 7) (normal "square" 5) (suboptimal "diamond" 13)
    (low "triangle-down" 11) (high "triangle-up" 9) (unknown "cross" 2))
  "Point shape of each status: (STATUS VEGA-SHAPE GNUPLOT-POINTTYPE).
Shape is a second channel beside color, as the glyph is in text.")

(defun health-chart-spec--shape (status)
  "(:shape :pt) of STATUS."
  (let ((e (alist-get status health-chart-spec-status-shapes)))
    (list :shape (car e) :pt (cadr e))))

(defun health-chart-spec--status-legend (theme statuses)
  "Legend entries for STATUSES (symbols) in THEME, best first."
  (apply #'vector
         (mapcar (lambda (s)
                   (append (health-chart-spec--legend-entry
                            (symbol-name s) (health-chart-status-glyph s)
                            (health-chart-spec--status-word s)
                            (health-chart-spec--color theme s))
                           (health-chart-spec--shape s)))
                 (seq-filter (lambda (s) (memq s statuses)) health-chart-statuses))))

(defun health-chart-spec--role (sym)
  "Palette role symbol for SYM (hyphens as underscores)."
  (intern (replace-regexp-in-string "-" "_" (symbol-name sym))))

(defun health-chart-spec--verdict-label (verdict)
  "Glyph and word for change VERDICT (nil = n/a)."
  (if verdict
      (format "%s %s" (alist-get verdict health-chart-verdict-glyphs "?") verdict)
    "? n/a"))

;; -----------------------------------------------------------------------
;; Dates and axes
;; -----------------------------------------------------------------------

(defun health-chart-spec--add-months (date months)
  "DATE (YYYY-MM-DD) moved by MONTHS, on the first of the month."
  (let* ((y (string-to-number (substring date 0 4)))
         (m (+ (string-to-number (substring date 5 7)) months -1)))
    (format "%04d-%02d-01" (+ y (floor m 12)) (1+ (mod m 12)))))

(defun health-chart-spec--date-ticks (from to max-ticks)
  "Ticks for dates FROM..TO: at most MAX-TICKS month-aligned dates.
Each tick is (:date :label :ms :sec); the step grows from one month to
several years, labels being \"%b %Y\" below a year and \"%Y\" above."
  (let* ((span-months (max 1 (/ (- (health-chart-date-days to) (health-chart-date-days from)) 30.4)))
         (step (or (seq-find (lambda (s) (<= (/ span-months s) max-ticks)) '(1 2 3 6 12 24 60))
                   120))
         (fmt (if (>= step 12) "%Y" "%b %Y"))
         (start (let ((d (health-chart-spec--add-months from 1)))
                  ;; align to the step: January for yearly ticks, else a multiple
                  (while (/= 0 (mod (1- (string-to-number (substring d 5 7))) (min step 12)))
                    (setq d (health-chart-spec--add-months d 1)))
                  d))
         ticks)
    (cl-loop for d = start then (health-chart-spec--add-months d step)
             while (not (string< to d))
             do (let ((days (health-chart-date-days d)))
                  (push (list :date d :label (health-chart-format-date d fmt)
                              :ms (* days 86400000) :sec (* days 86400))
                        ticks)))
    (list :format fmt :step_months step :ticks (apply #'vector (nreverse ticks)))))

(defun health-chart-spec--date-axis (dates title width)
  "A temporal x axis over DATES (strings) titled TITLE, WIDTH pixels wide.
The domain is padded by 4% of the span (at least 20 days) each side."
  (let* ((d0 (health-chart-date-days (car dates)))
         (d1 (health-chart-date-days (car (last dates))))
         (pad (max 20 (round (* 0.04 (- d1 d0)))))
         (lo (health-chart-days-date (- d0 pad)))
         (hi (health-chart-days-date (+ d1 pad)))
         (ticks (health-chart-spec--date-ticks lo hi (max 2 (/ width 110)))))
    (list :type "temporal" :title (or title "")
          :domain (vector lo hi)
          :domain_ms (vector (* (- d0 pad) 86400000) (* (+ d1 pad) 86400000))
          :domain_sec (vector (* (- d0 pad) 86400) (* (+ d1 pad) 86400))
          :tick_format (plist-get ticks :format)
          :tick_step_months (plist-get ticks :step_months)
          :ticks (plist-get ticks :ticks))))

(defun health-chart-spec--floor-zero (range values)
  "RANGE (LO . HI) with LO raised to 0 when VALUES are all non-negative."
  (if (and range (< (car range) 0) (cl-every (lambda (v) (>= v 0)) values))
      (cons 0 (cdr range))
    range))

(defun health-chart-spec--value-axis (title range)
  "A quantitative axis titled TITLE over RANGE (LO . HI), or nil bounds."
  (list :type "quantitative" :title (or title "")
        :domain (if range
                    (vector (health-chart-spec--round (car range))
                            (health-chart-spec--round (cdr range)))
                  (vector nil nil))))

(defun health-chart-spec--no-axis (&optional type title)
  "An axis of TYPE (default nominal) titled TITLE with no domain."
  (list :type (or type "nominal") :title (or title "") :domain (vector nil nil)))

;; -----------------------------------------------------------------------
;; Rows, bands, annotations
;; -----------------------------------------------------------------------

(defun health-chart-spec--row (m theme ms &rest extra)
  "The data row for measurement M in THEME (labels looked up in MS), plus EXTRA."
  (let ((status (health-chart-status m)))
    (append
     (list :person (plist-get m :person) :marker (plist-get m :marker)
           :label (health-chart-marker-label-in (plist-get m :marker) ms)
           :date (plist-get m :date) :value (plist-get m :value)
           :unit (plist-get m :unit) :value_label (health-chart-fmt-value m)
           :status (symbol-name status) :glyph (health-chart-status-glyph status)
           :status_label (health-chart-status-label status)
           :color (health-chart-spec--color theme status)
           :rgb (health-chart-spec--rgb (health-chart-spec--color theme status)))
     (health-chart-spec--shape status)
     (list :ref_low (plist-get m :ref-low) :ref_high (plist-get m :ref-high)
           :opt_low (plist-get m :opt-low) :opt_high (plist-get m :opt-high))
     extra)))

(defun health-chart-spec--clamp (x lo hi)
  "X within LO..HI."
  (max lo (min hi x)))

(defun health-chart-spec--band-extent (band range)
  "BAND (LO . HI), either side nil, clamped to RANGE (LO . HI) as (Y . Y2).
Nil when BAND is nil or lies wholly outside RANGE."
  (when band
    (let ((y (health-chart-spec--clamp (or (car band) (car range)) (car range) (cdr range)))
          (y2 (health-chart-spec--clamp (or (cdr band) (cdr range)) (car range) (cdr range))))
      (when (< y y2)
        (cons (health-chart-spec--round y) (health-chart-spec--round y2))))))

(defun health-chart-spec--bands (model range theme)
  "Band objects for MODEL's :ref and :opt within RANGE, in THEME."
  (apply #'vector
         (delq nil
               (cl-loop for (key word role) in '((:ref "reference" ref_band) (:opt "optimal" opt_band))
                        for band = (plist-get model key)
                        for ext = (health-chart-spec--band-extent band range)
                        collect (when ext
                                  (list :key word
                                        :label (format "%s %s" word
                                                       (health-chart-fmt-range (car band) (cdr band)))
                                        :low (car band) :high (cdr band)
                                        :y (car ext) :y2 (cdr ext)
                                        :color (health-chart-spec--color theme role)
                                        :opacity (plist-get health-chart-spec-style
                                                            (if (eq key :ref) :ref_band_opacity
                                                              :opt_band_opacity))))))))

(defun health-chart-spec--band-fields (model range)
  "Flat band members of MODEL within RANGE: raw bounds and drawn extents."
  (let ((ref (plist-get model :ref)) (opt (plist-get model :opt)))
    (let ((re (health-chart-spec--band-extent ref range))
          (oe (health-chart-spec--band-extent opt range)))
      (list :ref_low (car ref) :ref_high (cdr ref)
            :opt_low (car opt) :opt_high (cdr opt)
            :ref_y (car re) :ref_y2 (cdr re) :opt_y (car oe) :opt_y2 (cdr oe)
            :ref_label (if ref (format "reference %s" (health-chart-fmt-range (car ref) (cdr ref))) "")
            :opt_label (if opt (format "optimal %s" (health-chart-fmt-range (car opt) (cdr opt))) "")))))

(defun health-chart-spec--overlays (&rest props)
  "An overlays object: band fields, then PROPS' :bands :thresholds :annotations."
  (append (or (plist-get props :fields)
              (list :ref_low nil :ref_high nil :opt_low nil :opt_high nil
                    :ref_y nil :ref_y2 nil :opt_y nil :opt_y2 nil :ref_label "" :opt_label ""))
          (list :bands (or (plist-get props :bands) [])
                :thresholds (or (plist-get props :thresholds) [])
                :annotations (or (plist-get props :annotations) []))))

(defun health-chart-spec--latest-annotation (m theme)
  "The \"latest VALUE\" annotation for measurement M in THEME."
  (let ((status (health-chart-status m)))
    (list :date (plist-get m :date) :value (plist-get m :value)
          :text (format "latest %s" (health-chart-fmt-value m))
          :status_label (health-chart-status-label status)
          :color (health-chart-spec--color theme status))))

(defun health-chart-spec--size (props height)
  "(:width :height) from PROPS' :pixel-width/:pixel-height, HEIGHT the default."
  (list :width (or (plist-get props :pixel-width) health-chart-image-width)
        :height (or (plist-get props :pixel-height) height health-chart-image-height)))

;; -----------------------------------------------------------------------
;; Envelope
;; -----------------------------------------------------------------------

(defun health-chart-spec--envelope (kind props body)
  "Wrap kind BODY (a plist) for KIND under PROPS into a full spec."
  (let* ((theme (health-chart-spec--theme props))
         (size (health-chart-spec--size props (plist-get body :height))))
    (list :schema health-chart-spec-schema
          :kind (format "%s" kind)
          :title (or (plist-get props :title) (plist-get body :title) (format "%s" kind))
          :subtitle (or (plist-get props :subtitle) (plist-get body :subtitle) "")
          :unit (or (plist-get body :unit) "")
          :width (plist-get size :width) :height (plist-get size :height)
          :text_width (or (plist-get props :width) health-chart-width)
          :text_height (or (plist-get props :height) (plist-get body :text_height)
                           (max 12 (* 2 health-chart-height)))
          :theme theme
          :font health-chart-font-family :font_size health-chart-font-size
          :colors (health-chart-spec--colors theme)
          :style health-chart-spec-style
          :x (or (plist-get body :x) (health-chart-spec--no-axis))
          :y (or (plist-get body :y) (health-chart-spec--no-axis))
          :layout (plist-get body :layout)
          :rows (or (plist-get body :rows) [])
          :overlays (or (plist-get body :overlays) (health-chart-spec--overlays))
          :legend (or (plist-get body :legend) [])
          :series (or (plist-get body :series) [])
          :panels (or (plist-get body :panels) [])
          :meta (plist-get body :meta))))

(defun health-chart-spec--width (props)
  "The pixel width PROPS ask for."
  (or (plist-get props :pixel-width) health-chart-image-width))

(defun health-chart-spec--meta (ms)
  "Provenance of measurements MS: count and date extent."
  (let ((dates (health-chart-dates ms)))
    (list :points (length ms) :from (car dates) :to (car (last dates))
          :persons (apply #'vector (health-chart-persons ms))
          :markers (apply #'vector (health-chart-markers ms)))))

;; -----------------------------------------------------------------------
;; Measurement kinds
;; -----------------------------------------------------------------------

(defun health-chart-spec--series-body (model theme props &optional ms)
  "Spec body for a single-marker series MODEL in THEME under PROPS.
MS supplies marker labels."
  (let* ((points (plist-get (car (plist-get model :lines)) :points))
         (chosen (mapcar #'cl-third points))
         (latest (plist-get model :latest))
         (range (health-chart-spec--floor-zero
                 (plist-get model :y-range) (mapcar (lambda (m) (plist-get m :value)) chosen)))
         (rows (cl-loop for m in chosen for i from 1
                        collect (health-chart-spec--row
                                 m theme (or ms chosen)
                                 :series (plist-get m :person)
                                 :latest (if (= i (length chosen)) 1 0))))
         (statuses (mapcar (lambda (r) (intern (plist-get r :status))) rows)))
    (list :title (format "%s · %s" (plist-get model :label) (or (plist-get model :person) "all"))
          :subtitle (format "latest %s on %s · %s" (health-chart-fmt-value latest)
                            (plist-get latest :date)
                            (health-chart-status-label (health-chart-status latest)))
          :unit (plist-get model :unit)
          :x (health-chart-spec--date-axis (health-chart-dates chosen) nil
                                           (health-chart-spec--width props))
          :y (health-chart-spec--value-axis (plist-get model :unit) range)
          :rows (apply #'vector rows)
          :overlays (health-chart-spec--overlays
                     :fields (health-chart-spec--band-fields model range)
                     :bands (health-chart-spec--bands model range theme)
                     :annotations (vector (health-chart-spec--latest-annotation latest theme)))
          :legend (health-chart-spec--status-legend theme statuses)
          :meta (health-chart-spec--meta chosen))))

(defun health-chart-spec-timeseries (ms props)
  "Spec body for a timeseries of measurements MS under PROPS."
  (when-let* ((model (apply #'health-chart-model-series ms props)))
    (health-chart-spec--series-body model (health-chart-spec--theme props) props ms)))

;; Two people's latest values can be close; their labels are stacked so
;; neither hides the other.
(defun health-chart-spec--label-ys (values previous range height)
  "Label heights (data units) for annotations at VALUES within RANGE.
Each label sits a line away from its value: below when the line arrives
from above (its PREVIOUS value, nil for none, is higher), else above;
then on the other side, or further out, when that would overlap a label
already placed (higher values are placed first).  HEIGHT is the chart's
pixel height, from which a text line's height in data units is
estimated.  Returns the heights in the order of VALUES."
  (let* ((range (or range (cons (apply #'min values) (apply #'max values))))
         (lo (car range)) (hi (cdr range))
         (line (* (- hi lo) (/ 20.0 (max 120 (- height 170)))))
         (placed nil)
         (order (sort (number-sequence 0 (1- (length values)))
                      (lambda (a b) (> (nth a values) (nth b values)))))
         (ys (make-vector (length values) nil)))
    (dolist (i order)
      (let* ((v (nth i values))
             (prev (nth i previous))
             (sides (if (and prev (> prev v)) (list (- v line) (+ v line))
                      (list (+ v line) (- v line))))
             (free (lambda (y) (and (< (+ lo (* 0.5 line)) y (- hi (* 0.5 line)))
                                    (cl-notany (lambda (p) (< (abs (- y p)) line)) placed))))
             (y (or (seq-find free sides)
                    (- (apply #'min v placed) line))))
        (setq y (max (+ lo (* 0.5 line)) (min (- hi (* 0.5 line)) y)))
        (push y placed)
        (aset ys i (health-chart-spec--round y))))
    (append ys nil)))

(defun health-chart-spec-compare (ms props)
  "Spec body overlaying one marker of MS for several people, under PROPS."
  (when-let* ((model (apply #'health-chart-model-series ms :compare t props)))
    (let* ((theme (health-chart-spec--theme props))
           (palette (or (alist-get 'series health-chart-colors)
                        (alist-get 'series (health-chart-spec--palette theme))))
           (shapes '(("circle" 7 "●") ("square" 5 "■") ("diamond" 13 "◆")
                     ("triangle-up" 9 "▲") ("cross" 2 "✚") ("triangle-down" 11 "▼")))
           (lines (plist-get model :lines))
           (range (health-chart-spec--floor-zero
                   (plist-get model :y-range)
                   (cl-loop for line in lines append (mapcar #'cadr (plist-get line :points)))))
           (series
            (cl-loop for line in lines for i from 0
                     for color = (nth (mod i (length palette)) palette)
                     for shape = (nth (mod i (length shapes)) shapes)
                     for latest = (cl-third (car (last (plist-get line :points))))
                     for name = (or (plist-get line :name) "all")
                     collect (list :name name
                                   :label (format "%s %s" (cl-caddr shape) name)
                                   :color color :rgb (health-chart-spec--rgb color)
                                   :shape (car shape) :pt (cadr shape) :glyph (cl-caddr shape)
                                   :latest_label (format "%s %s %s" name
                                                         (health-chart-fmt-value latest)
                                                         (health-chart-status-label
                                                          (health-chart-status latest))))))
           (rows (cl-loop for line in lines for s in series
                          for pts = (plist-get line :points)
                          append (cl-loop for p in pts for i from 1
                                          collect (health-chart-spec--row
                                                   (cl-third p) theme ms
                                                   :series (plist-get s :name)
                                                   :series_label (plist-get s :label)
                                                   :series_color (plist-get s :color)
                                                   :latest (if (= i (length pts)) 1 0)))))
           (chosen (cl-loop for line in lines append (mapcar #'cl-third (plist-get line :points)))))
      (list :title (format "%s · %s" (plist-get model :label)
                           (string-join (mapcar (lambda (s) (plist-get s :name)) series) " vs "))
            :subtitle (concat "latest: " (string-join (mapcar (lambda (s) (plist-get s :latest_label))
                                                              series)
                                                      " · "))
            :unit (plist-get model :unit)
            :x (health-chart-spec--date-axis (health-chart-dates chosen) nil
                                             (health-chart-spec--width props))
            :y (health-chart-spec--value-axis (plist-get model :unit) range)
            :rows (apply #'vector rows)
            :overlays (health-chart-spec--overlays
                       :fields (health-chart-spec--band-fields model range)
                       :bands (health-chart-spec--bands model range theme)
                       :annotations
                       (apply #'vector
                              (cl-loop for line in lines for s in series
                                       for m = (cl-third (car (last (plist-get line :points))))
                                       for label-y in (health-chart-spec--label-ys
                                                       (mapcar (lambda (line)
                                                                 (cadr (car (last (plist-get line :points)))))
                                                               lines)
                                                       (mapcar (lambda (line)
                                                                 (cadr (car (last (plist-get line :points) 2))))
                                                               lines)
                                                       range
                                                       (plist-get (health-chart-spec--size props nil) :height))
                                       collect (append (plist-put
                                                        (health-chart-spec--latest-annotation m theme)
                                                        :text (format "%s %s" (plist-get s :name)
                                                                      (health-chart-fmt-value m)))
                                                       (list :label_y label-y
                                                             :series (plist-get s :name)
                                                             :series_label (plist-get s :label)
                                                             :series_color (plist-get s :color))))))
            :legend (apply #'vector
                           (mapcar (lambda (s)
                                     (list :key (plist-get s :name) :glyph (plist-get s :glyph)
                                           :word (plist-get s :name) :label (plist-get s :label)
                                           :color (plist-get s :color) :rgb (plist-get s :rgb)
                                           :shape (plist-get s :shape) :pt (plist-get s :pt)))
                                   series))
            :series (apply #'vector series)
            :meta (health-chart-spec--meta chosen)))))

(defun health-chart-spec-panel (ms props)
  "Spec body for small multiples of MS under PROPS (:columns, :marker list)."
  (let* ((theme (health-chart-spec--theme props))
         (models (apply #'health-chart-model-panel ms props)))
    (when models
      (let* ((n (length models))
             (width (health-chart-spec--width props))
             (columns (or (plist-get props :columns) (min n (max 1 (min 4 (/ width 230))))))
             (nrows (ceiling n (float columns)))
             (cell-w (max 120 (- (/ (- width 30) columns) 50)))
             (cell-h 120)
             (all (cl-loop for model in models
                           append (mapcar #'cl-third (plist-get (car (plist-get model :lines)) :points))))
             ;; about one tick per 40 pixels of a cell: yearly over a few years
             (x (health-chart-spec--date-axis (health-chart-dates all) nil (round (* 2.75 cell-w))))
             panels rows statuses)
        (cl-loop
         for model in models for idx from 1
         do (let* ((range (health-chart-spec--floor-zero
                           (plist-get model :y-range)
                           (mapcar #'cadr (plist-get (car (plist-get model :lines)) :points))))
                   (fields (health-chart-spec--band-fields model range))
                   (latest (plist-get model :latest))
                   (status (health-chart-status latest))
                   (title (format "%s · %s" (plist-get model :label) (or (plist-get model :unit) "")))
                   (latest-label (format "%s  %s" (health-chart-fmt-value latest)
                                         (health-chart-status-label status)))
                   (pts (plist-get (car (plist-get model :lines)) :points)))
              (push status statuses)
              (push (append (list :index idx :marker (plist-get model :marker)
                                  :label (plist-get model :label) :title title
                                  :unit (plist-get model :unit)
                                  :latest_label latest-label
                                  :status (symbol-name status)
                                  :color (health-chart-spec--color theme status)
                                  :y_min (health-chart-spec--round (car range))
                                  :y_max (health-chart-spec--round (cdr range))
                                  :column (1+ (mod (1- idx) columns))
                                  :row (1+ (/ (1- idx) columns)))
                            fields)
                    panels)
              (cl-loop for p in pts for i from 1
                       for m = (cl-third p)
                       do (push (append (health-chart-spec--row
                                         m theme ms :series (plist-get m :person)
                                         :latest (if (= i (length pts)) 1 0)
                                         :panel title :panel_index idx
                                         :latest_label latest-label
                                         :y_min (health-chart-spec--round (car range))
                                         :y_max (health-chart-spec--round (cdr range)))
                                        (list :ref_y (plist-get fields :ref_y)
                                              :ref_y2 (plist-get fields :ref_y2)
                                              :opt_y (plist-get fields :opt_y)
                                              :opt_y2 (plist-get fields :opt_y2)))
                                rows))))
        (setq statuses (append (mapcar (lambda (r) (intern (plist-get r :status))) rows) statuses))
        (list :title (format "Panel · %s" (or (plist-get (car models) :person) "all"))
              :subtitle (format "%d markers, %s to %s" n (car (health-chart-dates all))
                                (car (last (health-chart-dates all))))
              ;; title and key, then per row a cell plus its header and dates
              :height (+ 150 (* nrows (+ cell-h 84)))
              :x x
              :y (health-chart-spec--no-axis "quantitative")
              :layout (list :columns columns :rows nrows :cell_width cell-w :cell_height cell-h)
              :overlays (health-chart-spec--overlays
                         :bands (vector (list :key "reference" :label "reference range"
                                              :color (health-chart-spec--color theme 'ref_band)
                                              :opacity (plist-get health-chart-spec-style :ref_band_opacity))
                                        (list :key "optimal" :label "optimal range"
                                              :color (health-chart-spec--color theme 'opt_band)
                                              :opacity (plist-get health-chart-spec-style :opt_band_opacity))))
              :rows (apply #'vector (nreverse rows))
              :panels (apply #'vector (nreverse panels))
              :legend (health-chart-spec--status-legend theme statuses)
              :meta (health-chart-spec--meta all))))))

(defun health-chart-spec--position (x domain)
  "X as a 0..1 position in DOMAIN (LO . HI), or nil when X is nil."
  (when x
    (health-chart-spec--round
     (health-chart-spec--clamp (/ (- x (car domain)) (float (- (cdr domain) (car domain)))) 0 1)
     4)))

(defun health-chart-spec-bullet (ms props)
  "Spec body of range bars for the latest draw of each marker in MS, under PROPS."
  (let* ((theme (health-chart-spec--theme props))
         (model (apply #'health-chart-model-bullet ms props)))
    (when model
      (let* ((n (length model))
             (rows
              (cl-loop
               for r in model for i from 1
               collect
               (let* ((dom (plist-get r :domain))
                      (latest (plist-get r :latest))
                      (ref (plist-get r :ref)) (opt (plist-get r :opt)))
                 (health-chart-spec--row
                  latest theme ms
                  :index i
                  :domain_lo (health-chart-spec--round (car dom))
                  :domain_hi (health-chart-spec--round (cdr dom))
                  :pos (health-chart-spec--position (plist-get r :value) dom)
                  :ref_x (and ref (or (health-chart-spec--position (car ref) dom) 0))
                  :ref_x2 (and ref (or (health-chart-spec--position (cdr ref) dom) 1))
                  :opt_x (and opt (or (health-chart-spec--position (car opt) dom) 0))
                  :opt_x2 (and opt (or (health-chart-spec--position (cdr opt) dom) 1))
                  :ref_range (if ref (health-chart-fmt-range (car ref) (cdr ref)) "")
                  :opt_range (if opt (health-chart-fmt-range (car opt) (cdr opt)) "")
                  :latest_label (format "%s  %s" (health-chart-fmt-value latest)
                                        (health-chart-status-label (plist-get r :status)))))))
             (person (plist-get (car rows) :person)))
        (list :title (format "Latest vs range · %s" (or person "all"))
              :subtitle "latest draw per marker, each on its own scale; shaded: reference and optimal ranges"
              :height (+ 130 (* n 34))
              :x (list :type "quantitative" :title nil :domain (vector 0 1))
              :y (list :type "nominal" :title nil
                       :domain (apply #'vector (mapcar (lambda (r) (plist-get r :label)) rows)))
              :rows (apply #'vector rows)
              :overlays (health-chart-spec--overlays
                         :bands (vector (list :key "reference" :label "reference range"
                                              :color (health-chart-spec--color theme 'ref_band)
                                              :opacity (plist-get health-chart-spec-style :ref_band_opacity))
                                        (list :key "optimal" :label "optimal range"
                                              :color (health-chart-spec--color theme 'opt_band)
                                              :opacity (plist-get health-chart-spec-style :opt_band_opacity))))
              :legend (health-chart-spec--status-legend
                       theme (mapcar (lambda (r) (intern (plist-get r :status))) rows))
              :meta (health-chart-spec--meta (mapcar (lambda (r) (plist-get r :latest)) model)))))))

(defun health-chart-spec-heatmap (ms props)
  "Spec body of the status heatmap (markers by draw dates) of MS, under PROPS."
  (let* ((theme (health-chart-spec--theme props))
         (model (apply #'health-chart-model-heatmap ms props))
         (dates (plist-get model :dates))
         (markers (plist-get model :rows)))
    (when (and dates markers)
      (let ((rows
             (cl-loop
              for r in markers for yi from 1
              append (cl-loop for c in (plist-get r :cells) for xi from 1
                              when c
                              collect (health-chart-spec--row
                                       c theme ms
                                       :x_index xi :y_index yi
                                       :date_label (health-chart-format-date (plist-get c :date) "%b %Y")
                                       :cell_label (format "%s %s"
                                                           (health-chart-status-glyph
                                                            (health-chart-status c))
                                                           (health-chart-fmt (plist-get c :value)))
                                       :out (plist-get r :out))))))
        (list :title (format "Status by draw · %s" (or (plist-get model :person) "all"))
              :subtitle (format "%d markers × %d draws; %d out of range"
                                (length markers) (length dates)
                                (seq-count (lambda (r) (member (plist-get r :status) '("low" "high")))
                                           rows))
              :height (+ 150 (* 30 (length markers)))
              :x (list :type "ordinal" :title nil
                       :domain (apply #'vector dates)
                       :labels (apply #'vector (mapcar (lambda (d) (health-chart-format-date d "%b %Y"))
                                                       dates)))
              :y (list :type "nominal" :title nil
                       :domain (apply #'vector (mapcar (lambda (r) (plist-get r :label)) markers)))
              :rows (apply #'vector rows)
              :legend (health-chart-spec--status-legend
                       theme (mapcar (lambda (r) (intern (plist-get r :status))) rows))
              :meta (health-chart-spec--meta
                     (health-chart-filter ms :person (plist-get model :person))))))))

(defun health-chart-spec--end-labels (rows extent floor width forms &optional halves)
  "Pick end labels for bar ROWS and an axis bound giving them room.
EXTENT is the longest bar, FLOOR the least bound wanted, WIDTH the
chart's pixel width.  FORMS are functions of a row returning its label,
longest first; the first form whose widest label fits beside the longest
bar is used (the last one when none fits).  HALVES is 2 when bars
diverge from a centred zero, else 1.  Character widths are estimated
\(7.5 px each), as no font metrics are at hand; the category labels left
of the plot are each row's :label.  Returns (BOUND . TEXTS)."
  (let* ((char 7.5)
         (widest (lambda (xs) (apply #'max 1 (mapcar #'string-width xs))))
         (plot (- width (* char (funcall widest (mapcar (lambda (r) (plist-get r :label)) rows)))
                  110))
         (span (/ (float plot) (or halves 1)))
         (fit (lambda (texts)
                (let ((free (- span (+ 18 (* char (funcall widest texts))))))
                  (when (>= free (* 0.3 span)) (* extent (/ span free))))))
         (choice (or (cl-loop for form in forms
                              for texts = (mapcar form rows)
                              for bound = (funcall fit texts)
                              when bound return (cons bound texts))
                     (cons (/ extent 0.3) (mapcar (car (last forms)) rows)))))
    (cons (ceiling (max floor (car choice))) (cdr choice))))

(defun health-chart-spec-delta (ms props)
  "Spec body of percent-change bars between two draws of MS, under PROPS."
  (let* ((theme (health-chart-spec--theme props))
         (model (apply #'health-chart-model-delta ms props))
         (rows (plist-get model :rows)))
    (when rows
      (let* ((scale (apply #'max 1 (mapcar (lambda (r) (abs (or (plist-get r :pct) 0))) rows)))
             (out
              (cl-loop
               for r in rows for i from 1
               collect
               (let* ((verdict (plist-get r :verdict))
                      (role (if verdict (health-chart-spec--role verdict) 'unknown))
                      (color (health-chart-spec--color theme role)))
                 (list :index i :marker (plist-get r :marker) :label (plist-get r :label)
                       :unit (plist-get r :unit) :before (plist-get r :before)
                       :after (plist-get r :after)
                       :change (health-chart-spec--round (plist-get r :change))
                       :pct (health-chart-spec--round (or (plist-get r :pct) 0) 1)
                       :pct_label (if (plist-get r :pct) (format "%+.1f%%" (plist-get r :pct)) "n/a")
                       :value_label (string-trim-right
                                     (format "%s → %s %s" (health-chart-fmt (plist-get r :before))
                                             (health-chart-fmt (plist-get r :after))
                                             (or (plist-get r :unit) "")))
                       :side (if (< (or (plist-get r :pct) 0) 0) "neg" "pos")
                       :verdict (if verdict (symbol-name verdict) "unknown")
                       :glyph (if verdict (alist-get verdict health-chart-verdict-glyphs "?") "?")
                       :verdict_label (health-chart-spec--verdict-label verdict)
                       :color color :rgb (health-chart-spec--rgb color)))))
             (labels (health-chart-spec--end-labels
                      out scale (* 1.25 scale) (health-chart-spec--width props)
                      (list (lambda (r) (format "%s · %s" (plist-get r :pct_label)
                                                (plist-get r :value_label)))
                            (lambda (r) (format "%s %s" (plist-get r :pct_label)
                                                (plist-get r :glyph))))
                      2))
             (lim (car labels))
             (out (cl-mapcar (lambda (r text) (append r (list :text text))) out (cdr labels)))
             (present (delete-dups (mapcar (lambda (r) (plist-get r :verdict)) rows))))
        (list :title (format "Change %s → %s · %s" (plist-get model :from) (plist-get model :to)
                             (or (plist-get model :person) "all"))
              :subtitle "percent change per marker; judged toward or away from target"
              :height (+ 130 (* 30 (length rows)))
              :x (list :type "quantitative" :title "% change since the earlier draw"
                       :domain (vector (- lim) lim))
              :y (list :type "nominal" :title nil
                       :domain (apply #'vector (mapcar (lambda (r) (plist-get r :label)) out)))
              :rows (apply #'vector out)
              :overlays (health-chart-spec--overlays
                         :thresholds (vector (list :value 0 :label "no change" :axis "x"
                                                   :color (health-chart-spec--color theme 'axis))))
              :legend (apply #'vector
                             (delq nil
                                   (mapcar (lambda (v)
                                             (when (memq v present)
                                               (health-chart-spec--legend-entry
                                                (if v (symbol-name v) "unknown")
                                                (if v (alist-get v health-chart-verdict-glyphs "?") "?")
                                                (if v (symbol-name v) "n/a")
                                                (health-chart-spec--color
                                                 theme (if v (health-chart-spec--role v) 'unknown)))))
                                           '(improved on-target steady worsened nil))))
              :meta (list :points (* 2 (length rows)) :from (plist-get model :from)
                          :to (plist-get model :to)))))))

;; -----------------------------------------------------------------------
;; Indicator kinds
;; -----------------------------------------------------------------------

(defun health-chart-spec-staleness (values props)
  "Spec body of days since each indicator VALUES' draw, under PROPS."
  (let* ((theme (health-chart-spec--theme props))
         (model (apply #'health-chart-model-staleness values props))
         (rows (plist-get model :rows)))
    (when rows
      (let* ((scale (plist-get model :scale))
             (out
              (cl-loop
               for r in rows for i from 1
               collect
               (let* ((state (plist-get r :state))
                      (color (health-chart-spec--color theme state)))
                 (list :index i :id (plist-get r :id) :label (plist-get r :label)
                       :date (plist-get r :date) :days (plist-get r :days)
                       :bar (or (plist-get r :days) 0)
                       :days_label (if (plist-get r :days) (format "%d d" (plist-get r :days)) "no draw")
                       :state (symbol-name state)
                       :glyph (alist-get state health-chart-staleness-glyphs "?")
                       :state_label (health-chart-staleness-label state)
                       :color color :rgb (health-chart-spec--rgb color)
                       :marker (plist-get r :marker) :person (plist-get r :person)))))
             (labels (health-chart-spec--end-labels
                      out (apply #'max 1 (mapcar (lambda (r) (plist-get r :bar)) out))
                      (* 1.05 scale) (health-chart-spec--width props)
                      (list (lambda (r) (format "%s · %s" (plist-get r :days_label)
                                                (plist-get r :state_label)))
                            (lambda (r) (format "%s %s" (plist-get r :days_label)
                                                (plist-get r :glyph))))))
             (lim (car labels))
             (out (cl-mapcar (lambda (r text) (append r (list :text text))) out (cdr labels)))
             (states (mapcar (lambda (r) (plist-get r :state)) rows)))
        (list :title (health-chart-model-indicator-title values "Days since draw")
              :subtitle (format "as of %s; due after %d d, stale after %d d"
                                (plist-get model :as-of) (plist-get model :due) (plist-get model :stale))
              :height (+ 160 (* 34 (length rows)))
              :x (list :type "quantitative" :title "days since draw" :domain (vector 0 lim))
              :y (list :type "nominal" :title nil
                       :domain (apply #'vector (mapcar (lambda (r) (plist-get r :label)) out)))
              :rows (apply #'vector out)
              :overlays (health-chart-spec--overlays
                         :thresholds (vector (list :value (plist-get model :due)
                                                   :label (format "due after %d d" (plist-get model :due))
                                                   :axis "x" :key "due"
                                                   :color (health-chart-spec--color theme 'due))
                                             (list :value (plist-get model :stale)
                                                   :label (format "stale after %d d" (plist-get model :stale))
                                                   :axis "x" :key "stale"
                                                   :color (health-chart-spec--color theme 'stale))))
              :legend (apply #'vector
                             (delq nil (mapcar (lambda (s)
                                                 (when (memq s states)
                                                   (health-chart-spec--legend-entry
                                                    (symbol-name s)
                                                    (alist-get s health-chart-staleness-glyphs "?")
                                                    (symbol-name s)
                                                    (health-chart-spec--color theme s))))
                                               '(fresh due stale undated))))
              :meta (list :points (length rows) :as_of (plist-get model :as-of)))))))

;; -----------------------------------------------------------------------
;; Generic bodies: kinds known only by a template
;; -----------------------------------------------------------------------

(defun health-chart-spec-generic (ms props)
  "Spec body for template-only kinds over measurements MS, under PROPS.
Rows are every measurement; axes, bands and annotations follow the first
marker, as for a timeseries."
  (when ms
    (let* ((theme (health-chart-spec--theme props))
           (series (apply #'health-chart-spec-timeseries ms (list props)))
           (rows (mapcar (lambda (m) (health-chart-spec--row m theme ms :series (plist-get m :person)))
                         (health-chart-sort-by-date ms))))
      (append (list :rows (apply #'vector rows)
                    :legend (health-chart-spec--status-legend
                             theme (mapcar #'health-chart-status ms))
                    :meta (health-chart-spec--meta ms))
              series))))

(defun health-chart-spec-generic-indicators (values props)
  "Spec body for template-only kinds over indicator VALUES, under PROPS."
  (let ((theme (health-chart-spec--theme props)))
    (list :title (health-chart-model-indicator-title values "Indicators")
          :rows (apply #'vector
                       (mapcar (lambda (row)
                                 (let ((status (plist-get row :status)))
                                   (list :id (plist-get row :id) :label (plist-get row :label)
                                         :value (plist-get row :value) :unit (plist-get row :unit)
                                         :date (plist-get row :date)
                                         :status (symbol-name status)
                                         :status_label (health-chart-status-label status)
                                         :color (health-chart-spec--color theme status))))
                               (health-chart-model-scorecard values)))
          :legend (health-chart-spec--status-legend
                   theme (mapcar #'health-chart-indicator-status values)))))

;; -----------------------------------------------------------------------
;; Build and convert
;; -----------------------------------------------------------------------

(defun health-chart-spec-build (kind data props &optional builder)
  "The chart spec for KIND over normalized DATA under PROPS.
BUILDER is a function (DATA PROPS) returning the kind's body; nil or a
nil body yields a spec with no rows."
  (health-chart-spec--envelope kind props (and builder data (funcall builder data props))))

(defun health-chart-spec-to-json (spec &optional pretty)
  "SPEC as a JSON string; indented when PRETTY."
  (let ((json-encoding-pretty-print pretty)
        (json-encoding-default-indentation "  ")
        (json-encoding-separator (if pretty "," ", ")))
    (json-encode spec)))

(defun health-chart-spec-from-json (json)
  "The plist form of chart spec JSON (a string)."
  (let ((spec (json-parse-string json :object-type 'plist :array-type 'array
                                 :null-object nil :false-object nil)))
    (unless (equal (plist-get spec :schema) health-chart-spec-schema)
      (signal 'health-chart-error
              (list (format "not a %s spec (schema %S); build one with `health-chart-spec'"
                            health-chart-spec-schema (plist-get spec :schema))
                    :code "schema_mismatch")))
    spec))

(provide 'health-chart-spec)
;;; health-chart-spec.el ends here
