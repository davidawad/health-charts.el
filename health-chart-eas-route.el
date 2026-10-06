;;; health-chart-eas-route.el --- health-chart kinds drawn by eas templates -*- lexical-binding: t; -*-

;; Copyright (C) 2026 David Awad

;; Author: David Awad <me@davidaw.ad>
;; URL: https://github.com/davidawad/health-charts.el

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Every templated kind has an eas template (templates/eas/).
;; `health-chart-eas-kinds' maps a kind to its template and to the
;; function that builds the template's bindings from the kind's data and
;; props: it selects the measurements (person, marker, draws), names the
;; theme's colors, and writes the words a chart carries (title,
;; subtitle).  Everything else -- status, bands, positions, verdicts --
;; is a domain transform inside the chart document (health-chart-eas.el).
;;
;;   `health-chart-eas-bindings'  the slots of KIND's template
;;   `health-chart-eas-resolve'   the pure Vega-Lite spec they resolve to
;;   `health-chart-eas-scene'     its scene on the svg or text target
;;   `health-chart-eas-render'    that scene drawn, as a string
;;   `health-chart-eas-view'      a live, interactive eas view
;;   `health-chart-show'          the same, shown in a buffer
;;   `health-chart-eas-parity'    checks, as data, that the template
;;                                plots the numbers the kind's own spec
;;                                (`health-chart-spec') carries
;;
;; The `eas' backend of `health-chart-backends' calls these.  eas is a
;; soft dependency: without it on `load-path' the backend is unavailable
;; and `auto' falls through to the other backends.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'eas)
(require 'health-chart-core)
(require 'health-chart-kind)
(require 'health-chart-model)
(require 'health-chart-spec)
(require 'health-chart-spec-gallery)
(require 'health-chart-spec-dual)
(require 'health-chart-eas)

(defvar health-chart-width)
(defvar health-chart-image-width)
(defvar health-chart-image-height)

;;; Bindings, shared pieces

(defun health-chart-eas--bool (value)
  "VALUE as a JSON boolean."
  (if value t :false))

(defun health-chart-eas--person (person)
  "PERSON for a title: its name, else \"all\"."
  (or person "all"))

(defun health-chart-eas--theme-colors (theme)
  "The slot members naming THEME's palette roles: ink, bands, grid."
  (let ((c (lambda (role) (health-chart-spec--color theme role))))
    (list :ink (funcall c 'ink) :secondary (funcall c 'secondary)
          :muted (funcall c 'muted) :surface (funcall c 'surface)
          :grid (funcall c 'grid)
          :ref_color (funcall c 'ref_band) :opt_color (funcall c 'opt_band))))

(defun health-chart-eas--config (theme)
  "The Vega-Lite config object of THEME: background, axes, legend, title."
  (let ((c (lambda (role) (health-chart-spec--color theme role))))
    (list :background (funcall c 'surface)
          :view (list :stroke :null)
          :axis (list :labelColor (funcall c 'secondary) :titleColor (funcall c 'secondary)
                      :gridColor (funcall c 'grid) :domainColor (funcall c 'axis)
                      :tickColor (funcall c 'axis))
          :legend (list :labelColor (funcall c 'secondary) :orient "bottom"
                        :direction "horizontal")
          :title (list :color (funcall c 'ink) :subtitleColor (funcall c 'secondary)
                       :anchor "start"))))

(defun health-chart-eas--status-slots (theme statuses)
  "The status legend slots of THEME for STATUSES (symbols present)."
  (let ((legend (append (health-chart-spec--status-legend theme statuses) nil)))
    (list :status_domain (vconcat (mapcar (lambda (e) (plist-get e :label)) legend))
          :status_range (vconcat (mapcar (lambda (e) (plist-get e :color)) legend))
          :status_shape (vconcat (mapcar (lambda (e) (plist-get e :shape)) legend)))))

(defun health-chart-eas--band-slots (props)
  "The ref and optimal slots: PROPS' :ref and :optimal, else the defcustoms."
  (list :ref (health-chart-eas--bool (if (plist-member props :ref) (plist-get props :ref)
                                       health-chart-show-ref-range))
        :optimal (health-chart-eas--bool (if (plist-member props :optimal)
                                             (plist-get props :optimal)
                                           health-chart-show-optimal-range))))

(defun health-chart-eas--common (kind props data statuses)
  "The slots every KIND template shares: theme, words, status legend.
PROPS pick the theme, DATA is the template's data slot and STATUSES the
statuses it will show."
  (let ((theme (health-chart-spec--theme props)))
    (append (list :data data
                  :description (or (plist-get (alist-get kind health-chart-kinds) :doc) ""))
            (health-chart-eas--theme-colors theme)
            (list :config (health-chart-eas--config theme))
            (health-chart-eas--status-slots theme statuses))))

(defun health-chart-eas--words (props title subtitle)
  "(:title :subtitle) from PROPS' overrides, else TITLE and SUBTITLE."
  (list :title (or (plist-get props :title) title)
        :subtitle (or (plist-get props :subtitle) subtitle)))

(defun health-chart-eas--status-set (ms)
  "The statuses (symbols) of measurements MS."
  (mapcar #'health-chart-status ms))

(defun health-chart-eas--pixel-width (props)
  "The width PROPS ask for in pixels: text columns count 7 each."
  (if (eq (plist-get props :target) 'text)
      (* 7 (or (plist-get props :width) health-chart-width))
    (or (plist-get props :pixel-width) health-chart-image-width)))

(defun health-chart-eas--x-slots (ms props &optional per)
  "The time axis slots (:x_format :x_ticks) for measurements MS under PROPS.
PER divides the width among that many side-by-side plots."
  (let* ((dates (health-chart-dates ms))
         (width (/ (health-chart-eas--pixel-width props) (or per 1)))
         (axis (health-chart-spec--date-axis dates nil width)))
    (list :x_format (plist-get axis :tick_format)
          :x_ticks (max 2 (/ width 110)))))

(defun health-chart-eas--series-ms (model)
  "Every measurement drawn by series MODEL, line by line."
  (cl-loop for line in (plist-get model :lines)
           append (mapcar #'cl-third (plist-get line :points))))

;;; Per-kind bindings

(defun health-chart-eas--series-bindings (kind ms props)
  "Bindings of a one-marker series KIND (timeseries, trend, lollipop).
MS and PROPS are the measurements and the caller's props."
  (when-let* ((model (apply #'health-chart-model-series ms props)))
    (let* ((chosen (health-chart-eas--series-ms model))
           (latest (plist-get model :latest)))
      (append (health-chart-eas--common kind props chosen (health-chart-eas--status-set chosen))
              (health-chart-eas--band-slots props)
              (health-chart-eas--x-slots chosen props)
              (health-chart-eas--words
               props
               (format "%s · %s" (plist-get model :label)
                       (health-chart-eas--person (plist-get model :person)))
               (format "latest %s on %s · %s" (health-chart-fmt-value latest)
                       (plist-get latest :date)
                       (health-chart-status-label (health-chart-status latest))))
              (list :y_title (or (plist-get model :unit) ""))))))

(defun health-chart-eas--timeseries-bindings (ms props)
  "Bindings of the timeseries kind over MS under PROPS."
  (health-chart-eas--series-bindings 'timeseries ms props))

(defun health-chart-eas--trend-bindings (ms props)
  "Bindings of the trend kind over MS under PROPS."
  (let ((b (health-chart-eas--series-bindings 'trend ms props)))
    (when b (plist-put b :subtitle (format "%s (linear fit)" (plist-get b :subtitle))))))

(defun health-chart-eas--lollipop-bindings (ms props)
  "Bindings of the lollipop kind over MS under PROPS."
  (health-chart-eas--series-bindings 'lollipop ms props))

(defun health-chart-eas--compare-bindings (ms props)
  "Bindings of the compare kind: one marker, every person, over MS under PROPS."
  (when-let* ((model (apply #'health-chart-model-series ms :compare t props)))
    (let* ((theme (health-chart-spec--theme props))
           (palette (or (alist-get 'series health-chart-colors)
                        (alist-get 'series (health-chart-spec--palette theme))))
           (shapes '("circle" "square" "diamond" "triangle-up" "cross" "triangle-down"))
           (lines (plist-get model :lines))
           (names (mapcar (lambda (line) (or (plist-get line :name) "all")) lines))
           (chosen (health-chart-eas--series-ms model)))
      (append (health-chart-eas--common 'compare props chosen (health-chart-eas--status-set chosen))
              (health-chart-eas--band-slots props)
              (health-chart-eas--x-slots chosen props)
              (health-chart-eas--words
               props
               (format "%s · %s" (plist-get model :label) (string-join names " vs "))
               (concat "latest: "
                       (string-join
                        (cl-loop for line in lines for name in names
                                 collect (let ((m (cl-third (car (last (plist-get line :points))))))
                                           (format "%s %s %s" name (health-chart-fmt-value m)
                                                   (health-chart-status-label (health-chart-status m)))))
                        " · ")))
              (list :y_title (or (plist-get model :unit) "")
                    :series_domain (vconcat names)
                    :series_range (vconcat (cl-loop for i from 0 below (length names)
                                                    collect (nth (mod i (length palette)) palette)))
                    :series_shape (vconcat (cl-loop for i from 0 below (length names)
                                                    collect (nth (mod i (length shapes)) shapes))))))))

(defun health-chart-eas--panel-bindings (ms props)
  "Bindings of the panel kind: small multiples of MS under PROPS.
Up to four columns."
  (when-let* ((models (apply #'health-chart-model-panel ms props)))
    (let* ((n (length models))
           (width (or (plist-get props :pixel-width) health-chart-image-width))
           (columns (min 4 (or (plist-get props :columns)
                               ;; the widest layout that fills every row
                               (let ((base (min n (max 1 (min 4 (/ width 230))))))
                                 (or (seq-find (lambda (c) (zerop (mod n c)))
                                               (number-sequence base 2 -1))
                                     base)))))
           (chosen (cl-loop for model in models append (health-chart-eas--series-ms model)))
           (dates (health-chart-dates chosen))
           (cols (make-vector columns nil)))
      (cl-loop for model in models for i from 0
               do (push (list :marker (plist-get model :marker)
                              :title (format "%s · %s" (plist-get model :label)
                                             (or (plist-get model :unit) "")))
                        (aref cols (mod i columns))))
      (append (health-chart-eas--common 'panel props chosen (health-chart-eas--status-set chosen))
              (health-chart-eas--band-slots props)
              (health-chart-eas--x-slots chosen props columns)
              (health-chart-eas--words
               props
               (format "Panel · %s" (health-chart-eas--person (plist-get (car models) :person)))
               (format "%d markers, %s to %s" n (car dates) (car (last dates))))
              (cl-loop for k from 0 below columns
                       append (list (intern (format ":column_%d" (1+ k)))
                                    (vconcat (nreverse (aref cols k)))))
              (cl-loop for k from 1 below columns
                       append (list (intern (format ":has_column_%d" (1+ k))) t))))))

(defun health-chart-eas--bullet-bindings (ms props)
  "Bindings of the bullet kind: the latest draw of each marker of MS.
PROPS select the person and markers."
  (when-let* ((model (apply #'health-chart-model-bullet ms props)))
    (let ((latest (mapcar (lambda (r) (plist-get r :latest)) model)))
      (append (health-chart-eas--common 'bullet props latest (health-chart-eas--status-set latest))
              (health-chart-eas--band-slots props)
              (health-chart-eas--words
               props
               (format "Latest vs range · %s"
                       (health-chart-eas--person (plist-get (car latest) :person)))
               "latest draw per marker, each on its own scale")))))

(defun health-chart-eas--heatmap-bindings (ms props)
  "Bindings of the heatmap kind: markers of MS by draw dates, under PROPS."
  (let* ((model (apply #'health-chart-model-heatmap ms props))
         (dates (plist-get model :dates))
         (markers (plist-get model :rows)))
    (when (and dates markers)
      (let ((cells (cl-loop for r in markers append (delq nil (copy-sequence (plist-get r :cells))))))
        (append (health-chart-eas--common 'heatmap props cells (health-chart-eas--status-set cells))
                ;; a text row is 14 px: one marker per row keeps labels on their cells
                (list :row_step (if (eq (plist-get props :target) 'text) 14 28))
                (health-chart-eas--words
                 props
                 (format "Status by draw · %s" (health-chart-eas--person (plist-get model :person)))
                 (format "%d markers × %d draws; %d out of range" (length markers) (length dates)
                         (seq-count #'health-chart-out-of-range-p cells))))))))

(defun health-chart-eas--verdict-slots (theme verdicts)
  "The verdict legend slots of THEME for VERDICTS (symbols or nil, present)."
  (let ((present (seq-filter (lambda (v) (member v verdicts)) '(improved on-target steady worsened nil))))
    (list :verdict_domain (vconcat (mapcar #'health-chart-spec--verdict-label present))
          :verdict_range (vconcat (mapcar (lambda (v)
                                            (health-chart-spec--color
                                             theme (if v (health-chart-spec--role v) 'unknown)))
                                          present)))))

(defun health-chart-eas--delta-bindings (ms props)
  "Bindings of the delta kind: the two draws per marker of MS under PROPS."
  (let* ((model (apply #'health-chart-model-delta ms props))
         (rows (plist-get model :rows)))
    (when rows
      (let* ((theme (health-chart-spec--theme props))
             (ms (health-chart-fill-ranges ms))
             (mine (health-chart-filter ms :person (plist-get model :person)
                                        :marker (plist-get props :marker)))
             (draws (seq-filter (lambda (m) (member (plist-get m :date)
                                                    (list (plist-get model :from) (plist-get model :to))))
                                (seq-filter (lambda (m) (seq-some (lambda (r)
                                                                    (health-chart-marker-equal
                                                                     (plist-get r :marker)
                                                                     (plist-get m :marker)))
                                                                  rows))
                                            mine))))
        (append (health-chart-eas--common 'delta props draws (health-chart-eas--status-set draws))
                (health-chart-eas--verdict-slots theme (mapcar (lambda (r) (plist-get r :verdict)) rows))
                (health-chart-eas--words
                 props
                 (format "Change %s → %s · %s" (plist-get model :from) (plist-get model :to)
                         (health-chart-eas--person (plist-get model :person)))
                 "percent change per marker; judged toward or away from target"))))))

(defun health-chart-eas--staleness-bindings (values props)
  "Bindings of the staleness kind over indicator VALUES under PROPS."
  (let* ((model (apply #'health-chart-model-staleness values props))
         (rows (plist-get model :rows))
         (theme (health-chart-spec--theme props))
         (states (delete-dups (mapcar (lambda (r) (plist-get r :state)) rows))))
    (when rows
      (let ((present (seq-filter (lambda (s) (memq s states)) '(fresh due stale undated))))
        (append (list :data values
                      :description (or (plist-get (alist-get 'staleness health-chart-kinds) :doc) "")
                      :as_of (plist-get model :as-of)
                      :due_days (plist-get model :due) :stale_days (plist-get model :stale)
                      :config (health-chart-eas--config theme)
                      :state_domain (vconcat (mapcar #'health-chart-staleness-label present))
                      :state_range (vconcat (mapcar (lambda (s) (health-chart-spec--color theme s))
                                                    present))
                      :due_color (health-chart-spec--color theme 'due)
                      :stale_color (health-chart-spec--color theme 'stale))
                (health-chart-eas--theme-colors theme)
                (health-chart-eas--words
                 props (health-chart-model-indicator-title values "Days since draw")
                 (format "as of %s; due after %d d, stale after %d d" (plist-get model :as-of)
                         (plist-get model :due) (plist-get model :stale))))))))

(defun health-chart-eas--range-ms (groups)
  "The measurements of GROUPS (as `health-chart-spec-gallery--groups' gives)."
  (apply #'append (mapcar (lambda (g) (plist-get g :ms)) groups)))

(defun health-chart-eas--strip-bindings (ms props)
  "Bindings of the strip kind: every draw of each ranged marker of MS.
PROPS select the person and markers."
  (pcase-let* ((`(,person . ,all) (health-chart-spec-gallery--groups ms props))
               (groups (seq-filter (lambda (g) (health-chart-spec-gallery--scale (plist-get g :ranges)))
                                   all)))
    (when groups
      (let ((chosen (health-chart-eas--range-ms groups))
            (latest (mapcar (lambda (g) (car (last (plist-get g :ms)))) groups)))
        (append (health-chart-eas--common 'strip props chosen (health-chart-eas--status-set latest))
                (health-chart-eas--band-slots props)
                (health-chart-eas--words
                 props (format "Every draw vs range · %s" (health-chart-eas--person person))
                 (format "%d markers on their own scales; ticks: earlier draws" (length groups))))))))

(defun health-chart-eas--dumbbell-bindings (ms props)
  "Bindings of the dumbbell kind over MS under PROPS.
The first to the latest draw of each ranged marker."
  (pcase-let* ((`(,person . ,all) (health-chart-spec-gallery--groups ms props))
               (theme (health-chart-spec--theme props))
               (groups (seq-filter (lambda (g)
                                     (and (health-chart-spec-gallery--scale (plist-get g :ranges))
                                          (cdr (plist-get g :ms))))
                                   all)))
    (when groups
      (let* ((chosen (health-chart-eas--range-ms groups))
             (verdicts (mapcar (lambda (g) (health-chart-model--verdict
                                            (car (plist-get g :ms)) (car (last (plist-get g :ms)))))
                               groups))
             (dates (health-chart-dates chosen)))
        (append (health-chart-eas--common 'dumbbell props chosen
                                          (health-chart-eas--status-set chosen))
                (health-chart-eas--band-slots props)
                (health-chart-eas--verdict-slots theme verdicts)
                (health-chart-eas--words
                 props (format "First vs latest draw · %s" (health-chart-eas--person person))
                 (format "hollow: first draw; filled: latest; %s to %s" (car dates) (car (last dates)))))))))

(defun health-chart-eas--inrange-bindings (ms props)
  "Bindings of the inrange kind: every draw of each marker of MS under PROPS."
  (pcase-let ((`(,person . ,groups) (health-chart-spec-gallery--groups ms props)))
    (when groups
      (let ((chosen (health-chart-eas--range-ms groups)))
        (append (health-chart-eas--common 'inrange props chosen (health-chart-eas--status-set chosen))
                (health-chart-eas--words
                 props (format "Draws by status · %s" (health-chart-eas--person person))
                 "share of draws below, inside and above range; worst first"))))))

(defun health-chart-eas--dual-bindings (ms props)
  "Bindings of the dual kind: two markers of MS under PROPS.
One on a left and one on a right axis."
  (let* ((names (health-chart-spec-gallery--dual-markers ms props))
         (person (health-chart-model--pick ms :person props))
         (theme (health-chart-spec--theme props))
         (palette (or (alist-get 'series health-chart-colors)
                      (alist-get 'series (health-chart-spec--palette theme))))
         (inks (list (nth 0 palette) (nth (min 6 (1- (length palette))) palette)))
         (models (mapcar (lambda (name)
                           (apply #'health-chart-model-series ms :marker name :person person
                                  (health-chart--plist-drop props :marker :person)))
                         names)))
    (when (and (= 2 (length models)) (cl-every #'identity models))
      (let* ((sides '("left" "right"))
             (tagged (cl-loop for model in models for side in sides
                              append (mapcar (lambda (m) (plist-put (copy-sequence m) :axis side))
                                             (health-chart-eas--series-ms model))))
             (domain (lambda (model)
                       (let ((r (health-chart-spec--floor-zero
                                 (plist-get model :y-range)
                                 (mapcar (lambda (m) (plist-get m :value))
                                         (health-chart-eas--series-ms model)))))
                         (vector (health-chart-spec--round (car r)) (health-chart-spec--round (cdr r))))))
             (title (lambda (model)
                      (if (string-empty-p (or (plist-get model :unit) ""))
                          (plist-get model :label)
                        (format "%s (%s)" (plist-get model :label) (plist-get model :unit)))))
             (latest-label (lambda (model)
                             (let ((m (plist-get model :latest)))
                               (format "%s %s  %s" (plist-get model :label) (health-chart-fmt-value m)
                                       (health-chart-status-label (health-chart-status m)))))))
        (append (health-chart-eas--common 'dual props tagged (health-chart-eas--status-set tagged))
                (health-chart-eas--band-slots props)
                (health-chart-eas--x-slots tagged props)
                (health-chart-eas--words
                 props (format "%s · %s · %s" (plist-get (nth 0 models) :label)
                               (plist-get (nth 1 models) :label) (health-chart-eas--person person))
                 (concat "latest: " (string-join (mapcar latest-label models) " · ")))
                (list :left_color (nth 0 inks) :right_color (nth 1 inks)
                      :left_title (funcall title (nth 0 models))
                      :right_title (funcall title (nth 1 models))
                      :left_domain (funcall domain (nth 0 models))
                      :right_domain (funcall domain (nth 1 models))))))))

;;; The kinds table

(defvar health-chart-eas-kinds
  '((timeseries :template "health-timeseries" :bindings health-chart-eas--timeseries-bindings)
    (compare :template "health-compare" :bindings health-chart-eas--compare-bindings)
    (panel :template "health-panel" :bindings health-chart-eas--panel-bindings)
    (trend :template "health-trend" :bindings health-chart-eas--trend-bindings)
    (lollipop :template "health-lollipop" :bindings health-chart-eas--lollipop-bindings)
    (bullet :template "health-bullet" :bindings health-chart-eas--bullet-bindings)
    (heatmap :template "health-heatmap" :bindings health-chart-eas--heatmap-bindings)
    (delta :template "health-delta" :bindings health-chart-eas--delta-bindings)
    (staleness :template "health-staleness" :bindings health-chart-eas--staleness-bindings)
    (strip :template "health-strip" :bindings health-chart-eas--strip-bindings)
    (dumbbell :template "health-dumbbell" :bindings health-chart-eas--dumbbell-bindings)
    (dual :template "health-dual" :bindings health-chart-eas--dual-bindings)
    (inrange :template "health-inrange" :bindings health-chart-eas--inrange-bindings))
  "Kinds drawn by eas: (KIND :template NAME :bindings FN).
FN is called with the kind's normalized DATA and the caller's PROPS and
returns the template's slots, or nil when there is nothing to draw.")

(defun health-chart-eas-kind-p (kind)
  "Non-nil when KIND has an eas template."
  (and (assq kind health-chart-eas-kinds) t))

(defun health-chart-eas--entry (kind)
  "KIND's `health-chart-eas-kinds' plist, or signal."
  (or (alist-get kind health-chart-eas-kinds)
      (signal 'health-chart-unknown-kind
              (list (format "%S has no eas template; templated kinds: %s" kind
                            (mapconcat (lambda (e) (symbol-name (car e))) health-chart-eas-kinds ", "))
                    :code "unknown_kind" :kind kind))))

(defun health-chart-eas-template (kind)
  "The eas template name of KIND."
  (plist-get (health-chart-eas--entry kind) :template))

(defun health-chart-eas-template-file (kind)
  "The file of KIND's eas template, or nil."
  (when (health-chart-eas-kind-p kind)
    (plist-get (eas-template-get (health-chart-eas-template kind)) :path)))

(defun health-chart-eas-bindings (kind data &optional props)
  "The slots of KIND's eas template that draw DATA under PROPS, or nil.
DATA is normalized here; nil when nothing is selected."
  (let* ((entry (health-chart-eas--entry kind))
         (data (health-chart-normalize kind data)))
    (when data
      (funcall (plist-get entry :bindings) data (health-chart--plist-drop props :backend :format :scale :out)))))

;;; Resolve, compile, render

(defun health-chart-eas-resolve (kind data &optional props)
  "The pure Vega-Lite spec KIND's template resolves to for DATA and PROPS, or nil."
  (when-let* ((bindings (health-chart-eas-bindings kind data props)))
    (eas-resolve (health-chart-eas-template kind) bindings)))

(defun health-chart-eas--size (target props)
  "The `eas-compile' :size for TARGET (text or svg) under PROPS."
  (if (eq target 'text)
      (list :cols (or (plist-get props :width) health-chart-width)
            :rows (or (plist-get props :height) (max 12 (* 2 health-chart-height))))
    (cons (or (plist-get props :pixel-width) health-chart-image-width)
          (or (plist-get props :pixel-height) health-chart-image-height))))

(defun health-chart-eas-scene (kind data target &optional props)
  "KIND's scene for DATA on TARGET (`text' or `svg') sized by PROPS, or nil.
Text takes :width columns and :height rows, svg :pixel-width and
:pixel-height."
  (when-let* ((resolved (health-chart-eas-resolve kind data (plist-put (copy-sequence props)
                                                                       :target target))))
    (eas-compile resolved :target target :size (health-chart-eas--size target props))))

(defun health-chart-eas-render (kind data format &optional props)
  "KIND drawn from DATA by its eas template as FORMAT (`svg' or `text').
PROPS are as for `health-chart-plot'.  A string, or nil when there is
nothing to draw.  Text keeps eas's text properties (help-echo, datum)."
  (unless (memq format '(svg text))
    (signal 'health-chart-backend-error
            (list (format "eas draws svg and text, not %s" format) :code "unsupported_format")))
  (when-let* ((scene (health-chart-eas-scene kind data format props)))
    (if (eq format 'text) (eas-text-render scene) (eas-svg-render scene))))

(defun health-chart-eas--json (value)
  "VALUE as a JSON string of characters (`eas-json-encode' gives UTF-8 bytes)."
  (let ((s (eas-json-encode value)))
    (if (multibyte-string-p s) s (decode-coding-string s 'utf-8))))

(defun health-chart-eas--export-size (resolved props)
  "RESOLVED with a pixel width (and height) where it said \"container\".
The size comes from PROPS; a Vega-Lite renderer has no container to
measure."
  (let ((size (health-chart-eas--size 'svg props)))
    (when (equal (plist-get resolved :width) "container")
      (setq resolved (eas-plist-put resolved :width (car size))))
    (when (equal (plist-get resolved :height) "container")
      (setq resolved (eas-plist-put resolved :height (cdr size))))
    resolved))

(defun health-chart-eas-vega-lite (kind data &optional props)
  "KIND's template for DATA under PROPS as standalone Vega-Lite JSON, or nil.
It renders with vl2svg or any Vega-Lite renderer; no eas is needed."
  (when-let* ((resolved (health-chart-eas-resolve kind data props)))
    (health-chart-eas--json (health-chart-eas--export-size resolved props))))

(defun health-chart-eas-explain (kind data format &optional props)
  "The plan of drawing KIND's DATA as FORMAT with eas under PROPS.  Pure.
A plist: :backend :format :template (the file), :slots (the slot names
filled), :program (the resolved Vega-Lite JSON) and :steps (nil: eas runs
in this Emacs)."
  (let ((bindings (health-chart-eas-bindings kind data props)))
    (list :backend 'eas :format format
          :template (health-chart-eas-template-file kind)
          :slots (vconcat (mapcar #'eas-key-name (eas-plist-keys bindings)))
          :program (and bindings (health-chart-eas--json
                                  (eas-resolve (health-chart-eas-template kind) bindings)))
          :steps nil)))

(defun health-chart-eas-view (kind data &optional props target)
  "A live eas view of KIND's DATA under PROPS on TARGET, or nil.
Hover, crosshair, zoom, brush and the agent verbs (`eas-agent') work on it."
  (when-let* ((bindings (health-chart-eas-bindings kind data props)))
    (eas-view-open (health-chart-eas-template kind) :bindings bindings :subject (format "%s" kind)
                   :target target
                   :size (and target (health-chart-eas--size target props)))))

;;;###autoload
(defun health-chart-show (kind data &rest props)
  "Show DATA as a live, interactive KIND chart in an eas buffer; return it.
SVG in a graphical frame, text in a terminal.  PROPS as in
`health-chart-plot'.  Needs eas.el."
  (apply #'health-chart-validate kind data props)
  (let ((view (health-chart-eas-view kind data props)))
    (unless view
      (signal 'health-chart-invalid-data
              (list (format "nothing to draw for %s; check :person and :marker" kind)
                    :code "empty_chart")))
    (eas-show view)))

;;; Parity

(defun health-chart-eas--marks (scene ids)
  "The rows of every mark of SCENE whose id is in IDS or ends in /ID, as a list.
IDS is a mark id or a list of them."
  (let ((ids (if (listp ids) ids (list ids))) rows)
    (seq-doseq (view (plist-get scene :views))
      (seq-doseq (mark (plist-get view :marks))
        (when (let ((mid (plist-get mark :id)))
                (seq-some (lambda (id) (or (equal mid id)
                                           (and (stringp mid) (string-suffix-p (concat "/" id) mid))))
                          ids))
          (seq-doseq (row (plist-get mark :rows)) (push row rows)))))
    (nreverse rows)))

(defun health-chart-eas--same-p (a b)
  "Non-nil when A and B are equal, numbers within a relative 1e-6."
  (cond ((and (numberp a) (numberp b)) (<= (abs (- a b)) (* 1e-6 (max 1.0 (abs a) (abs b)))))
        ((and (consp a) (consp b))
         (and (= (length a) (length b)) (cl-every #'health-chart-eas--same-p a b)))
        (t (equal a b))))

(defun health-chart-eas--spec-rows (kind data props)
  "KIND's chartspec/v1 rows for DATA under PROPS, as a list."
  (append (plist-get (apply #'health-chart-spec kind data
                            (health-chart--plist-drop props :backend :format))
                     :rows)
          nil))

(defun health-chart-eas--pick (rows &rest keys)
  "ROWS as lists of KEYS' values, sorted for comparison."
  (sort (mapcar (lambda (row) (mapcar (lambda (k) (let ((v (plist-get row k))) (if (eq v :null) nil v)))
                                      keys))
                rows)
        (lambda (a b) (string< (format "%S" a) (format "%S" b)))))

(defvar health-chart-eas-parity-marks
  '((timeseries "draws" (:marker :date :value :status) (:marker :date :value :status))
    (trend "draws" (:marker :date :value :status) (:marker :date :value :status))
    (lollipop "draws" (:marker :date :value :status) (:marker :date :value :status))
    (compare "draws" (:series :date :value :status) (:person :date :value :status))
    (panel "draws" (:marker :date :value :status) (:marker :date :value :status))
    (dual ("left-draws" "right-draws") (:marker :date :value :status) (:marker :date :value :status))
    (heatmap "cells" (:marker :date :value :status) (:marker :date :value :status))
    (bullet "latest" (:marker :value :status :pos :ref_x :ref_x2 :opt_x :opt_x2)
            (:marker :value :status :pos :ref_x :ref_x2 :opt_x :opt_x2))
    (delta "change" (:marker :before :after :pct :verdict) (:marker :before :after :pct :verdict))
    (dumbbell "latest" (:marker :norm_before :norm_after :verdict)
              (:marker :norm_before :norm_after :verdict))
    (staleness "days" (:id :days :state) (:id :days :state)))
  "How `health-chart-eas-parity' compares KIND (KIND MARK SPEC-KEYS MARK-KEYS).
MARK is the id (or list of ids) of the template marks whose rows carry
the plotted numbers;
SPEC-KEYS the chartspec/v1 row members, MARK-KEYS the mark row members
they correspond to, pairwise.")

(defun health-chart-eas-parity (kind data &optional props)
  "Check, as data, that KIND's template plots DATA's numbers under PROPS.
It compares with the numbers `health-chart-spec' has.
A list of (NAME EXPECTED ACTUAL); every check holds when its EXPECTED and
ACTUAL are equal (numbers within 1e-6).  nil when nothing is drawn.
Strip and inrange are checked by their own numbers (range positions,
status counts)."
  (when-let* ((scene (health-chart-eas-scene kind data 'text props)))
    (let* ((data (health-chart-normalize kind data))
           (props (health-chart--plist-drop props :backend :format))
           (spec (apply #'health-chart-spec kind data props))
           (rows (append (plist-get spec :rows) nil)))
      (pcase kind
        ('strip
         (list (list "positions"
                     (health-chart-eas--pick rows :marker :date :norm :x)
                     (health-chart-eas--pick (append (health-chart-eas--marks scene "earlier")
                                                     (health-chart-eas--marks scene "latest"))
                                             :marker :date :norm :x))))
        ('inrange
         (list (list "counts"
                     (health-chart-eas--pick rows :marker :status :count)
                     (health-chart-eas--pick (health-chart-eas--marks scene "shares")
                                             :marker :status :count))))
        (_
         (pcase-let ((`(,_k ,mark ,spec-keys ,mark-keys)
                      (or (assq kind health-chart-eas-parity-marks)
                          (signal 'health-chart-unknown-kind (list (format "no parity for %s" kind)
                                                                   :code "unknown_kind")))))
           (list (list (format "%s" mark)
                       (apply #'health-chart-eas--pick rows spec-keys)
                       (apply #'health-chart-eas--pick (health-chart-eas--marks scene mark)
                              mark-keys)))))))))

(defun health-chart-eas-parity-ok-p (results)
  "Non-nil if all RESULTS of `health-chart-eas-parity' are true."
  (cl-every (lambda (c) (health-chart-eas--same-p (nth 1 c) (nth 2 c))) results))

(provide 'health-chart-eas-route)
;;; health-chart-eas-route.el ends here
